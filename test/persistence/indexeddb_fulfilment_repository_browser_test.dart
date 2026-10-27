@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/persistence/session_snapshot_codec.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_schema.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';
import 'package:retail_offline/services/json/precision_json_decoder.dart';

import 'indexeddb_probe.dart';

const productId = '1290564103789190763';
const orderNumber = '9007199254740993';
const address = 'A-01';
const serial = 'SN-0001';

const _dataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$productId,"SerialNumber":"SN-0001","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":$orderNumber,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$productId,"Quantity":2,'
    '"Price":324.50,"Amount":649.00,"isServiceGood":0,"isParcel":0}]},'
    '{"OrderID":"ORD-2","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000002","OrderNumber":42,'
    '"Customer":"Тестовий Клієнт Б","CustomerPhone":"0501112244","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$productId,"Quantity":1,'
    '"Price":324.50,"Amount":324.50,"isServiceGood":0,"isParcel":0}]}]}';

void main() {
  var sequence = 0;
  late String databaseName;

  setUp(() {
    sequence += 1;
    databaseName =
        'retail-offline-test-$sequence-${DateTime.now().microsecondsSinceEpoch}';
    requireTestDatabase(databaseName);
  });

  tearDown(() async {
    await IndexedDbProbe(databaseName).deleteDatabase();
  });

  test(
    'an empty database loads as empty and creates the four stores',
    () async {
      final repository = IndexedDbFulfilmentRepository(
        databaseName: databaseName,
      );

      expect(await repository.load(), isA<LoadEmpty>());

      final names = await IndexedDbProbe(databaseName).storeNames();
      expect(names, containsAll(IndexedDbFulfilmentSchema.stores));
      expect(
        await IndexedDbProbe(databaseName)
            .read(IndexedDbFulfilmentSchema.dataset),
        isNull,
      );
    },
  );

  test(
    'the first import stores revision 1 and reloads the same bytes',
    () async {
      final bytes = datasetBytes();
      final handle = await _imported(databaseName, bytes);
      final stored = await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.dataset);
      final metadata = await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.metadata);

      expect(handle.app.revision, 1);
      expect(probeBytes(stored!, 'bytes'), bytes);
      expect(probeText(stored, 'fingerprint'), DatasetFingerprint.of(bytes));
      expect(probeText(stored, 'schemaVersion'), '1');
      expect(probeText(metadata!, 'revision'), '1');
      expect(probeText(metadata, 'fingerprint'), handle.app.fingerprint);
      expect(
        await IndexedDbProbe(databaseName)
            .read(IndexedDbFulfilmentSchema.exports),
        isNull,
      );

      final again = await handle.repository.importDataset(
        bytes: bytes,
        fingerprint: handle.app.fingerprint!,
        snapshot: handle.app.session!.capture(
          datasetFingerprint: handle.app.fingerprint!,
        ),
      );
      expect(again, isA<CommitRevisionConflict>());

      final restored = await reload(databaseName);
      expect(restored.revision, 1);
      expect(restored.fingerprint, DatasetFingerprint.of(bytes));
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(
        restored.session!.dataset.orders.first.orderNumber.literal,
        orderNumber,
      );
      expect(
        restored.session!.dataset.stocks.single.productId.literal,
        productId,
      );
    },
  );

  test(
    'reservations, issuance, and cancellation survive a new instance',
    () async {
      final handle = await _imported(databaseName, datasetBytes());
      expect(
        await reserve(handle.app, quantity: 1),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );

      var restored = await reload(databaseName);
      expect(restored.revision, 2);
      expect(reserved(restored), 1);
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.inProgress);

      expect(
        await reserve(restored, quantity: 1),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await restored.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      restored = await reload(databaseName);
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.issued);

      expect(
        await restored.cancelIssuance('ORD-1'),
        isA<FulfilmentCommitted<CancelIssuanceResult>>(),
      );
      restored = await reload(databaseName);
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(reserved(restored), 2);
    },
  );

  test('dataset replacement removes the previous export', () async {
    final handle = await _imported(databaseName, datasetBytes());
    final document = await storeExport(handle.app);
    final replacement = datasetBytes(dbName: 'Store_02-B');

    final replaced = await handle.app.replaceDataset(replacement);

    expect(replaced, isA<FulfilmentReplaced>());
    expect(handle.app.lastExport, isNull);
    expect(handle.app.revision, greaterThan(1));
    expect(
      await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.exports),
      isNull,
    );

    final restored = await reload(databaseName);
    expect(restored.fingerprint, DatasetFingerprint.of(replacement));
    expect(restored.lastExport, isNull);
    expect(restored.session!.dataset.dbName, 'Store_02-B');
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.noSelection);
    expect(reserved(restored), 0);
    expect(document.bytes, isNotEmpty);
  });

  test('an aborted replacement keeps the dataset and the export', () async {
    final bytes = datasetBytes();
    final handle = await _imported(databaseName, bytes);
    final document = await storeExport(handle.app);
    final exportBytes = Uint8List.fromList(document.bytes);
    final fingerprint = handle.app.fingerprint!;
    final revision = handle.app.revision!;
    final snapshot = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.session);
    handle.repository.abortNextTransaction = true;

    final failed = await handle.app.replaceDataset(
      datasetBytes(dbName: 'Store_02-B'),
    );

    expect(failed, isA<FulfilmentReplacementFailed>());
    expect(handle.app.block, PersistenceBlock.storageFailed);
    expect(handle.app.revision, revision);
    expect(handle.app.fingerprint, fingerprint);
    expect(handle.app.lastExport!.bytes, exportBytes);
    expect(handle.app.session!.dataset.dbName, 'Store_01-A');
    expect(handle.app.session!.statusOf('ORD-1'), OrderStatus.exported);

    final restored = await reload(databaseName);
    expect(restored.revision, revision);
    expect(restored.fingerprint, fingerprint);
    expect(restored.lastExport!.bytes, exportBytes);
    expect(restored.lastExport!.filename, document.filename);
    expect(restored.session!.dataset.dbName, 'Store_01-A');
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.exported);
    expect(reserved(restored), 2);

    final storedDataset = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.dataset);
    expect(probeBytes(storedDataset!, 'bytes'), bytes);
    expect(probeText(storedDataset, 'fingerprint'), fingerprint);

    final storedExport = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.exports);
    expect(probeBytes(storedExport!, 'bytes'), exportBytes);
    expect(probeText(storedExport, 'filename'), document.filename);

    final metadata = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.metadata);
    expect(probeText(metadata!, 'revision'), '$revision');
    expect(probeText(metadata, 'fingerprint'), fingerprint);

    final storedSession = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.session);
    expect(storedSession!['snapshot'], snapshot!['snapshot']);
  });

  test('a cumulative export restores its exact bytes and digest', () async {
    final handle = await _imported(databaseName, datasetBytes());
    final document = await storeExport(handle.app);
    final before = Uint8List.fromList(document.bytes);
    expect(
      await reserve(handle.app, orderId: 'ORD-2', quantity: 1),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );

    final restored = await reload(databaseName);
    final stored = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.exports);
    final digest = DatasetFingerprint.of(before);

    expect(restored.lastExport!.bytes, before);
    expect(restored.lastExport!.filename, document.filename);
    expect(restored.lastExport!.dateCreate, '20261014150722');
    expect(probeBytes(stored!, 'bytes'), before);
    expect(probeText(stored, 'digest'), digest);
    expect(probeText(stored, 'filename'), document.filename);
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.exported);
    expect(reserved(restored, 'ORD-2'), 1);

    final root = const PrecisionJsonDecoder().decode(utf8.decode(before));
    final order =
        ((root as JsonObjectValue).fields['orders']! as JsonArrayValue)
                .items
                .first
            as JsonObjectValue;
    final good =
        (order.fields['Goods']! as JsonArrayValue).items.first
            as JsonObjectValue;
    expect(
      (order.fields['OrderNumber']! as JsonNumberValue).literal,
      orderNumber,
    );
    expect((good.fields['ProductID']! as JsonNumberValue).literal, productId);
    expect(
      (await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.session))!['snapshot'],
      contains(productId),
    );
  });

  test('a second instance cannot overwrite a newer revision', () async {
    final first = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final second = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final appA = FulfilmentApplication(repository: first);
    final appB = FulfilmentApplication(repository: second);
    expect(await appA.importDataset(datasetBytes()), isA<FulfilmentImported>());
    expect(await appB.load(), isA<LoadReady>());
    expect(appA.revision, appB.revision);

    expect(
      await reserve(appA, quantity: 1),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    final conflict = await reserve(appB, quantity: 1);

    expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
    expect(appB.block, PersistenceBlock.revisionConflict);
    expect(appB.canMutate, isFalse);
    expect(appB.revision, 1);
    expect(reserved(appB), 0);
    expect(appB.session!.statusOf('ORD-1'), OrderStatus.noSelection);

    expect(await appB.reload(), isA<LoadReady>());
    expect(appB.block, isNull);
    expect(appB.revision, 2);
    expect(reserved(appB), 1);
    expect(appB.canMutate, isTrue);
  });

  test('an aborted transaction does not activate the candidate', () async {
    final handle = await _imported(databaseName, datasetBytes());
    handle.repository.abortNextTransaction = true;

    final failed = await reserve(handle.app, quantity: 1);

    expect(failed, isA<FulfilmentBlocked<ReserveResult>>());
    expect(handle.app.block, PersistenceBlock.storageFailed);
    expect(handle.app.revision, 1);
    expect(reserved(handle.app), 0);
    expect(handle.app.canMutate, isFalse);

    expect(await handle.app.reload(), isA<LoadReady>());
    expect(handle.app.block, isNull);
    expect(handle.app.revision, 1);
    expect(reserved(handle.app), 0);

    final restored = await reload(databaseName);
    expect(restored.revision, 1);
    expect(reserved(restored), 0);
  });

  test('corrupt records stay in place and fail closed', () async {
    final bytes = datasetBytes();
    final handle = await _imported(databaseName, bytes);
    final fingerprint = handle.app.fingerprint!;

    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.dataset, {
          'schemaVersion': '1',
          'bytes': Uint8List.fromList(utf8.encode('{')),
          'fingerprint': fingerprint,
        });
    expect(await handle.repository.load(), isA<LoadCorrupted>());
    expect(await handle.repository.load(), isA<LoadCorrupted>());
    expect(
      probeBytes(
        (await IndexedDbProbe(databaseName)
            .read(IndexedDbFulfilmentSchema.dataset))!,
        'bytes',
      ),
      utf8.encode('{'),
    );

    await IndexedDbProbe(databaseName).write(
      IndexedDbFulfilmentSchema.dataset,
      {'schemaVersion': '1', 'bytes': bytes, 'fingerprint': fingerprint},
    );
    await IndexedDbProbe(databaseName).write(
      IndexedDbFulfilmentSchema.session,
      {'schemaVersion': '1', 'snapshot': '{'},
    );
    expect(await handle.repository.load(), isA<LoadCorrupted>());

    final document = ExportDocument(
      filename: 'export_Store_01-A_20261014150722.json',
      bytes: Uint8List.fromList(utf8.encode('{"orders":[]}')),
      dateCreate: '20261014150722',
    );
    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.session, {
          'schemaVersion': '1',
          'snapshot': const SessionSnapshotReader().textFor(bytes, fingerprint),
        });
    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.exports, {
          'schemaVersion': '1',
          'filename': document.filename,
          'dateCreate': document.dateCreate,
          'bytes': document.bytes,
          'digest': 'a' * 64,
        });
    expect(await handle.repository.load(), isA<LoadCorrupted>());
    expect(
      await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.exports),
      isNotNull,
    );
  });

  test('an unsupported schema is distinct and is not overwritten', () async {
    final handle = await _imported(databaseName, datasetBytes());
    final metadata = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.metadata);
    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.metadata, {
          'schemaVersion': '2',
          'revision': probeText(metadata!, 'revision'),
          'fingerprint': probeText(metadata, 'fingerprint'),
        });

    expect(await handle.repository.load(), isA<LoadUnsupportedVersion>());
    final importedAgain = await handle.repository.importDataset(
      bytes: datasetBytes(),
      fingerprint: handle.app.fingerprint!,
      snapshot: handle.app.session!.capture(
        datasetFingerprint: handle.app.fingerprint!,
      ),
    );
    expect(importedAgain, isA<CommitUnsupportedVersion>());
    expect(await handle.repository.load(), isA<LoadUnsupportedVersion>());

    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.metadata, {
          'schemaVersion': '01',
          'revision': '1',
          'fingerprint': handle.app.fingerprint!,
        });
    expect(await handle.repository.load(), isA<LoadCorrupted>());
  });

  test('a newer IndexedDB database version is unsupported', () async {
    await IndexedDbProbe(databaseName).createDatabaseVersion(2);
    final repository = IndexedDbFulfilmentRepository(
      databaseName: databaseName,
    );

    expect(await repository.load(), isA<LoadUnsupportedVersion>());
    expect(await IndexedDbProbe(databaseName).storeNames(), contains('probe'));
  });

  test('revision overflow does not increment the stored revision', () async {
    final handle = await _imported(databaseName, datasetBytes());
    final metadata = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.metadata);
    final ceiling = IndexedDbFulfilmentSchema.revisionText(
      StorageRevision.maximum,
    );
    await IndexedDbProbe(databaseName)
        .write(IndexedDbFulfilmentSchema.metadata, {
          'schemaVersion': '1',
          'revision': ceiling,
          'fingerprint': probeText(metadata!, 'fingerprint'),
        });

    final loaded = await handle.repository.load();
    expect(loaded, isA<LoadReady>());
    expect((loaded as LoadReady).state.revision, StorageRevision.maximum);

    final result = await handle.repository.commitSession(
      expectedRevision: StorageRevision.maximum,
      snapshot: handle.app.session!.capture(
        datasetFingerprint: handle.app.fingerprint!,
      ),
    );

    expect(result, isA<CommitRevisionOverflow>());
    expect(
      probeText(
        (await IndexedDbProbe(databaseName)
            .read(IndexedDbFulfilmentSchema.metadata))!,
        'revision',
      ),
      ceiling,
    );
  });

  test('caller changes after import do not change the stored bytes', () async {
    final bytes = datasetBytes();
    await _imported(databaseName, bytes);
    bytes[0] = 0;

    final restored = await reload(databaseName);
    expect(restored.session!.dataset.dbName, 'Store_01-A');
  });

  test('a legacy snapshot without excise stamps stays readable', () async {
    final handle = await _imported(databaseName, datasetBytes());
    expect(
      await reserve(handle.app, quantity: 1),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );

    final stored = await IndexedDbProbe(databaseName)
        .read(IndexedDbFulfilmentSchema.session);
    final snapshot = stored!['snapshot']! as String;
    expect(snapshot, isNot(contains('exciseStamps')));
    expect(
      handle.app.session!.dataset.orders.first.goods.single.isAlko,
      isFalse,
    );

    final restored = await reload(databaseName);
    expect(reserved(restored), 1);
    expect(
      restored.session!.slotExciseStamps(
        orderId: 'ORD-1',
        productId: productId,
        address: address,
        serialNumber: serial,
      ),
      isEmpty,
    );
  });

  test(
    'excise stamps survive reload and a failed commit writes nothing',
    () async {
      final bytes = Uint8List.fromList(utf8.encode(_alcoholDataset));
      final handle = await _imported(databaseName, bytes);
      expect(
        await _reserveStamp(handle.app, 'qwer123456'),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await _reserveStamp(handle.app, 'ASDF654321'),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );

      var restored = await reload(databaseName);
      expect(_stamps(restored), ['QWER123456', 'ASDF654321']);
      expect(reserved(restored), 2);
      expect(
        restored.session!.dataset.orders.single.goods.single.isAlko,
        isTrue,
      );

      final blocked = IndexedDbFulfilmentRepository(databaseName: databaseName);
      final blockedApp = FulfilmentApplication(repository: blocked);
      expect(await blockedApp.load(), isA<LoadReady>());
      blocked.abortNextTransaction = true;
      expect(
        await _reserveStamp(blockedApp, 'ZXCV111111'),
        isA<FulfilmentBlocked<ReserveResult>>(),
      );

      restored = await reload(databaseName);
      expect(restored.revision, 3);
      expect(_stamps(restored), ['QWER123456', 'ASDF654321']);
      expect(reserved(restored), 2);
    },
  );

  test('a conflicting tab cannot replace the stored excise stamp', () async {
    final bytes = Uint8List.fromList(utf8.encode(_alcoholDataset));
    final first = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final second = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final appA = FulfilmentApplication(repository: first);
    final appB = FulfilmentApplication(repository: second);
    expect(await appA.importDataset(bytes), isA<FulfilmentImported>());
    expect(await appB.load(), isA<LoadReady>());

    expect(
      await _reserveStamp(appA, 'QWER123456'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    final conflict = await _reserveStamp(appB, 'ASDF654321');

    expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
    expect(appB.block, PersistenceBlock.revisionConflict);
    expect(await appB.reload(), isA<LoadReady>());
    expect(_stamps(appB), ['QWER123456']);
    expect(appB.revision, 2);
  });

  test('a reloaded session rejects a duplicate excise stamp', () async {
    final bytes = Uint8List.fromList(utf8.encode(_alcoholDataset));
    final handle = await _imported(databaseName, bytes);
    expect(
      await _reserveStamp(handle.app, 'QWER123456'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );

    final restored = await reload(databaseName);
    final duplicate = await _reserveStamp(restored, 'qwer123456');

    expect(duplicate, isA<FulfilmentDomainRejected<ReserveResult>>());
    final rejected =
        (duplicate as FulfilmentDomainRejected<ReserveResult>).result
            as ReserveRejected;
    expect(rejected.reason, ReserveRejection.duplicateExciseStamp);
    expect(rejected.exciseStamp, 'QWER123456');

    final again = await reload(databaseName);
    expect(again.revision, restored.revision);
    expect(_stamps(again), ['QWER123456']);
    expect(reserved(again), 1);
  });

  test('concurrent tabs reload before a duplicate stamp is judged', () async {
    final bytes = Uint8List.fromList(utf8.encode(_alcoholDataset));
    final first = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final second = IndexedDbFulfilmentRepository(databaseName: databaseName);
    final appA = FulfilmentApplication(repository: first);
    final appB = FulfilmentApplication(repository: second);
    expect(await appA.importDataset(bytes), isA<FulfilmentImported>());
    expect(await appB.load(), isA<LoadReady>());

    expect(
      await _reserveStamp(appA, 'QWER123456'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    final conflict = await _reserveStamp(appB, 'qwer123456');
    final whileBlocked = await _reserveStamp(appB, 'ASDF654321');

    expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
    expect(whileBlocked, isA<FulfilmentBlocked<ReserveResult>>());
    expect(appB.block, PersistenceBlock.revisionConflict);

    final stored = await reload(databaseName);
    expect(stored.revision, 2);
    expect(_stamps(stored), ['QWER123456']);

    expect(await appB.reload(), isA<LoadReady>());
    final retry = await _reserveStamp(appB, 'QWER123456');
    expect(retry, isA<FulfilmentDomainRejected<ReserveResult>>());
    final rejected =
        (retry as FulfilmentDomainRejected<ReserveResult>).result
            as ReserveRejected;
    expect(rejected.reason, ReserveRejection.duplicateExciseStamp);
    expect(appB.revision, 2);
    expect(_stamps(appB), ['QWER123456']);
    expect(reserved(appB), 1);
  });

  test('an alcohol export commits atomically and reloads the stamps', () async {
    final bytes = Uint8List.fromList(utf8.encode(_alcoholDataset));
    final handle = await _imported(databaseName, bytes);
    expect(
      await _reserveStamp(handle.app, 'QWER123456'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    expect(
      await _reserveStamp(handle.app, 'ASDF654321'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    expect(
      await _reserveStamp(handle.app, 'ZXCV112233'),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    expect(
      await handle.app.issueOrder('ORD-1'),
      isA<FulfilmentCommitted<IssueOrderResult>>(),
    );
    final issuedRevision = handle.app.revision;

    handle.repository.abortNextTransaction = true;
    final failed = await handle.app.commitCumulativeExport(
      now: () => DateTime(2026, 10, 14, 15, 7, 22),
    );
    expect(failed, isA<FulfilmentExportFailed>());

    var restored = await reload(databaseName);
    expect(restored.revision, issuedRevision);
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.issued);
    expect(_stamps(restored), ['QWER123456', 'ASDF654321', 'ZXCV112233']);
    expect(
      await IndexedDbProbe(databaseName)
          .read(IndexedDbFulfilmentSchema.exports),
      isNull,
    );

    final exported = await restored.commitCumulativeExport(
      now: () => DateTime(2026, 10, 14, 15, 7, 22),
    );
    expect(exported, isA<FulfilmentExported>());
    final document = (exported as FulfilmentExported).document;
    final text = utf8.decode(document.bytes);
    expect(text, contains('"ExciseStamp": "QWER123456"'));
    expect(text, contains('"ExciseStamp": "ASDF654321"'));
    expect(text, contains('"ExciseStamp": "ZXCV112233"'));

    restored = await reload(databaseName);
    expect(restored.revision, issuedRevision! + 1);
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.exported);
    expect(_stamps(restored), ['QWER123456', 'ASDF654321', 'ZXCV112233']);
    expect(restored.lastExport!.bytes, document.bytes);
  });
}

const _alcoholDataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$productId,"SerialNumber":"SN-0001","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":$orderNumber,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Алкоголь","ProductID":$productId,"Quantity":3,'
    '"Price":324.50,"Amount":973.50,"isServiceGood":0,"isParcel":0,'
    '"isAlko":1}]}]}';

Uint8List datasetBytes({String dbName = 'Store_01-A'}) {
  return Uint8List.fromList(
    utf8.encode(_dataset.replaceFirst('Store_01-A', dbName)),
  );
}

class _Handle {
  _Handle(this.repository, this.app);

  final IndexedDbFulfilmentRepository repository;
  final FulfilmentApplication app;
}

Future<_Handle> _imported(String databaseName, Uint8List bytes) async {
  final repository = IndexedDbFulfilmentRepository(databaseName: databaseName);
  final app = FulfilmentApplication(repository: repository);
  expect(await app.importDataset(bytes), isA<FulfilmentImported>());
  return _Handle(repository, app);
}

Future<FulfilmentApplication> reload(String databaseName) async {
  final app = FulfilmentApplication(
    repository: IndexedDbFulfilmentRepository(databaseName: databaseName),
  );
  expect(await app.load(), isA<LoadReady>());
  return app;
}

Future<FulfilmentCommandResult<ReserveResult>> reserve(
  FulfilmentApplication app, {
  String orderId = 'ORD-1',
  int quantity = 1,
}) {
  return app.reserve(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serial,
    quantity: quantity,
  );
}

Future<FulfilmentCommandResult<ReserveResult>> _reserveStamp(
  FulfilmentApplication app,
  String stamp,
) {
  return app.reserve(
    orderId: 'ORD-1',
    productId: productId,
    address: address,
    serialNumber: serial,
    quantity: 1,
    exciseStamps: [stamp],
  );
}

List<String> _stamps(FulfilmentApplication app) {
  return app.session!.slotExciseStamps(
    orderId: 'ORD-1',
    productId: productId,
    address: address,
    serialNumber: serial,
  );
}

int reserved(FulfilmentApplication app, [String orderId = 'ORD-1']) {
  return app.session!.lineReservedQuantity(
    orderId: orderId,
    productId: productId,
  );
}

Future<ExportDocument> storeExport(FulfilmentApplication app) async {
  expect(
    await reserve(app, quantity: 2),
    isA<FulfilmentCommitted<ReserveResult>>(),
  );
  expect(
    await app.issueOrder('ORD-1'),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
  final exported = await app.commitCumulativeExport(
    now: () => DateTime(2026, 10, 14, 15, 7, 22),
  );
  expect(exported, isA<FulfilmentExported>());
  return (exported as FulfilmentExported).document;
}

/// Snapshot text for an empty overlay of [bytes].
class SessionSnapshotReader {
  const SessionSnapshotReader();

  String textFor(Uint8List bytes, String fingerprint) {
    final restored = const DatasetByteRestore().restore(
      bytes: bytes,
      expectedFingerprint: fingerprint,
    );
    final dataset = (restored as DatasetRestored).dataset;
    final opened = FulfilmentSession.open(dataset) as DatasetOpened;
    return const SessionSnapshotCodec().encode(
      opened.session.capture(datasetFingerprint: fingerprint),
    );
  }
}
