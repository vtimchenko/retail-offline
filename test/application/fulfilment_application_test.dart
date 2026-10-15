import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/core/constants/dataset_messages.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/services/file/cumulative_export_share.dart';
import 'package:retail_offline/services/file/export_share.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';
import 'package:retail_offline/services/json/precision_json_decoder.dart';

import '../support/memory_fulfilment_repository.dart';

const productId = '1290564103789190763';
const address = 'A-01';
const serial = 'SN-0001';

/// Synthetic catalogue. Stock can cover both lines. No real customer data.
const _dataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$productId,"SerialNumber":"SN-0001","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":9007199254740993,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$productId,"Quantity":2,'
    '"Price":324.50,"Amount":649.00,"isServiceGood":0,"isParcel":0}]},'
    '{"OrderID":"ORD-2","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000002","OrderNumber":42,'
    '"Customer":"Тестовий Клієнт Б","CustomerPhone":"0501112244","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$productId,"Quantity":1,'
    '"Price":324.50,"Amount":324.50,"isServiceGood":0,"isParcel":0}]}]}';

void main() {
  group('load and import', () {
    test('reports empty storage', () async {
      final app = FulfilmentApplication(
        repository: MemoryFulfilmentRepository(),
      );

      final result = await app.load();

      expect(result, isA<LoadEmpty>());
      expect(app.session, isNull);
      expect(app.revision, isNull);
      expect(app.fingerprint, isNull);
      expect(app.lastExport, isNull);
      expect(app.block, isNull);
      expect(app.canMutate, isFalse);
    });

    test('imports the first dataset at revision 1', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(repository: repository);
      final bytes = datasetBytes();

      final result = await app.importDataset(bytes);

      expect(result, isA<FulfilmentImported>());
      final imported = result as FulfilmentImported;
      expect(imported.revision, StorageRevision.initial);
      expect(imported.fingerprint, DatasetFingerprint.of(bytes));
      expect(app.session, same(imported.session));
      expect(app.revision, 1);
      expect(app.fingerprint, imported.fingerprint);
      expect(app.lastExport, isNull);
      expect(repository.debugRevision, 1);
      expect(reserved(app, 'ORD-1'), 0);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.noSelection);
    });

    test('restores a committed session into a new instance', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);
      final active = app.session!;

      final restored = FulfilmentApplication(repository: repository);
      final result = await restored.load();

      expect(result, isA<LoadReady>());
      expect(restored.session, isNot(same(active)));
      expect(restored.revision, 2);
      expect(restored.fingerprint, app.fingerprint);
      expect(restored.lastExport, isNull);
      expect(reserved(restored, 'ORD-1'), 1);
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('rejects a malformed file without writing or blocking', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(repository: repository);

      final result = await app.importDataset(utf8.encode('{'));

      expect(result, isA<FulfilmentImportRejected>());
      expect(app.session, isNull);
      expect(app.block, isNull);
      expect(repository.commitAttempts, 0);
      expect(await repository.load(), isA<LoadEmpty>());
    });

    test('does not import again while a session is active', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final attempts = repository.commitAttempts;

      final result = await app.importDataset(datasetBytes());

      expect(result, isA<FulfilmentImportOccupied>());
      expect(app.block, isNull);
      expect(app.revision, 1);
      expect(repository.commitAttempts, attempts);
    });

    test('keeps the caller bytes from changing the stored dataset', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(repository: repository);
      final bytes = datasetBytes();

      await app.importDataset(bytes);
      bytes[0] = 0;

      final restored = FulfilmentApplication(repository: repository);
      final result = await restored.load();

      expect(result, isA<LoadReady>());
      expect(restored.session!.statusOf('ORD-1'), OrderStatus.noSelection);
    });
  });

  group('session commands', () {
    test('adds and removes a reservation', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);

      final added = await reserve(app, quantity: 1);

      expect(added, isA<FulfilmentCommitted<ReserveResult>>());
      expect(app.revision, 2);
      expect(reserved(app, 'ORD-1'), 1);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.inProgress);

      final removed = await app.removeUnits(
        orderId: 'ORD-1',
        productId: productId,
        address: address,
        serialNumber: serial,
        quantity: 1,
      );

      expect(removed, isA<FulfilmentCommitted<RemoveUnitsResult>>());
      expect(app.revision, 3);
      expect(reserved(app, 'ORD-1'), 0);
      expect(repository.debugRevision, 3);
    });

    test('clears reservations and leaves an empty order unchanged', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);

      final cleared = await app.clearOrder('ORD-1');

      expect(cleared, isA<FulfilmentCommitted<ClearOrderResult>>());
      expect(app.revision, 3);
      expect(reserved(app, 'ORD-1'), 0);

      final attempts = repository.commitAttempts;
      final unchanged = await app.clearOrder('ORD-1');

      expect(unchanged, isA<FulfilmentUnchanged<ClearOrderResult>>());
      expect(app.revision, 3);
      expect(repository.debugRevision, 3);
      expect(repository.commitAttempts, attempts);
    });

    test('issues an order and cancels that issuance', () async {
      final app = await imported(MemoryFulfilmentRepository());
      await reserve(app, quantity: 2);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);

      final issued = await app.issueOrder('ORD-1');

      expect(issued, isA<FulfilmentCommitted<IssueOrderResult>>());
      expect(app.revision, 3);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);

      final cancelled = await app.cancelIssuance('ORD-1');

      expect(cancelled, isA<FulfilmentCommitted<CancelIssuanceResult>>());
      expect(app.revision, 4);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(reserved(app, 'ORD-1'), 2);
    });

    test('does not persist a domain rejection', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      final attempts = repository.commitAttempts;

      final result = await reserve(app, orderId: 'ORD-9', quantity: 1);

      expect(result, isA<FulfilmentDomainRejected<ReserveResult>>());
      final rejected = result as FulfilmentDomainRejected<ReserveResult>;
      expect(rejected.result, isA<ReserveRejected>());
      expect(app.session, same(before));
      expect(app.revision, 1);
      expect(app.block, isNull);
      expect(repository.commitAttempts, attempts);
    });

    test('keeps the candidate inactive until the commit finishes', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      final hold = repository.holdNextCommit();

      final pending = reserve(app, quantity: 1);
      await hold.started;

      expect(app.session, same(before));
      expect(app.revision, 1);
      expect(repository.debugRevision, 1);
      expect(reserved(app, 'ORD-1'), 0);

      hold.release();
      final result = await pending;

      expect(result, isA<FulfilmentCommitted<ReserveResult>>());
      expect(app.session, isNot(same(before)));
      expect(app.revision, 2);
      expect(repository.debugRevision, 2);
      expect(reserved(app, 'ORD-1'), 1);
    });
  });

  group('failures and reload', () {
    test('does not activate a session when the commit fails', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      repository.failNextCommit();

      final result = await reserve(app, quantity: 1);

      expect(result, isA<FulfilmentBlocked<ReserveResult>>());
      expect(app.block, PersistenceBlock.storageFailed);
      expect(app.canMutate, isFalse);
      expect(app.session, same(before));
      expect(app.revision, 1);
      expect(reserved(app, 'ORD-1'), 0);
      expect(repository.debugRevision, 1);
    });

    test('blocks later commands without writing them', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      repository.failNextCommit();
      await reserve(app, quantity: 1);
      final attempts = repository.commitAttempts;

      final result = await reserve(app, quantity: 1);

      expect(result, isA<FulfilmentBlocked<ReserveResult>>());
      expect(app.block, PersistenceBlock.storageFailed);
      expect(repository.commitAttempts, attempts);
      expect(repository.debugRevision, 1);
    });

    test('reload restores the stored session and clears the block', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      repository.failNextCommit();
      await reserve(app, quantity: 1);

      final result = await app.reload();

      expect(result, isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
      expect(app.revision, 1);
      expect(reserved(app, 'ORD-1'), 0);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.noSelection);
    });

    test('an unsuccessful reload stays blocked', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      repository.failNextCommit();
      await reserve(app, quantity: 1);
      final before = app.session!;
      repository.debugStorageUnavailable(true);

      final result = await app.reload();

      expect(result, isA<LoadStorageUnavailable>());
      expect(app.block, PersistenceBlock.storageUnavailable);
      expect(app.canMutate, isFalse);
      expect(app.session, same(before));
      expect(app.revision, 1);

      repository.debugStorageUnavailable(false);
      final recovered = await app.reload();

      expect(recovered, isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
    });

    test('a stale revision conflicts and is not retried', () async {
      final repository = MemoryFulfilmentRepository();
      final first = await imported(repository);
      final second = FulfilmentApplication(repository: repository);
      expect(await second.load(), isA<LoadReady>());
      final stale = second.session!;

      await reserve(first, quantity: 1);
      expect(first.revision, 2);
      final attempts = repository.commitAttempts;

      final conflict = await reserve(second, quantity: 1);

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(second.block, PersistenceBlock.revisionConflict);
      expect(second.session, same(stale));
      expect(second.revision, 1);
      expect(reserved(second, 'ORD-1'), 0);
      expect(reserved(first, 'ORD-1'), 1);

      final ignored = await reserve(second, quantity: 1);

      expect(ignored, isA<FulfilmentBlocked<ReserveResult>>());
      expect(repository.commitAttempts, attempts + 1);
      expect(repository.debugRevision, 2);

      expect(await second.reload(), isA<LoadReady>());
      expect(second.block, isNull);
      expect(second.revision, 2);
      expect(reserved(second, 'ORD-1'), 1);
      expect(reserved(first, 'ORD-1'), 1);
    });

    test('rejects a session commit that changes exported orders', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 2);
      await app.issueOrder('ORD-1');
      final issued = app.session!;
      final revision = app.revision!;
      final exported = switch (issued.markExported('ORD-1')) {
        OrderMarkedExported(:final session) => session,
        final other => fail('markExported failed: $other'),
      };

      final result = await repository.commitSession(
        expectedRevision: revision,
        snapshot: exported.capture(datasetFingerprint: app.fingerprint!),
      );

      expect(result, const CommitRejected(CommitRejection.exportedSetChanged));
      expect(repository.debugRevision, revision);
      expect(app.session, same(issued));
      expect(app.revision, revision);
      expect(app.block, isNull);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      final stored = await repository.load();
      expect(stored, isA<LoadReady>());
      expect(
        (stored as LoadReady).state.session.statusOf('ORD-1'),
        OrderStatus.issued,
      );
    });

    test('rejects the next commit at the maximum safe revision', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      repository.debugRevision = StorageRevision.maximum;
      expect(await app.reload(), isA<LoadReady>());
      expect(app.revision, StorageRevision.maximum);

      final result = await reserve(app, quantity: 1);

      expect(result, isA<FulfilmentBlocked<ReserveResult>>());
      expect(app.block, PersistenceBlock.revisionOverflow);
      expect(app.revision, StorageRevision.maximum);
      expect(
        app.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        0,
      );
      expect(repository.debugRevision, StorageRevision.maximum);

      expect(await app.reload(), isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.revision, StorageRevision.maximum);
      expect(reserved(app, 'ORD-1'), 0);
    });

    test('does not replace an unsupported schema', () async {
      final repository = MemoryFulfilmentRepository();
      repository.debugSchemaVersion = 2;
      final app = FulfilmentApplication(repository: repository);

      final result = await app.importDataset(datasetBytes());

      expect(result, isA<FulfilmentImportFailed>());
      expect(app.block, PersistenceBlock.unsupportedVersion);
      expect(app.session, isNull);
      expect(repository.debugRevision, isNull);
      expect(repository.debugSchemaVersion, 2);
      expect(await app.reload(), isA<LoadUnsupportedVersion>());
      expect(app.block, PersistenceBlock.unsupportedVersion);
    });
  });

  group('repository commits', () {
    test('replaceDataset writes every record or none', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);
      final revision = app.revision!;
      final fingerprint = app.fingerprint!;
      final replacement = utf8.encode(
        _dataset.replaceFirst('Магазин Тест', 'Інший магазин'),
      );
      final snapshot = emptySnapshot(replacement);
      repository.failNextCommit();

      final failed = await repository.replaceDataset(
        expectedRevision: revision,
        bytes: replacement,
        fingerprint: DatasetFingerprint.of(replacement),
        snapshot: snapshot,
      );

      expect(failed, const CommitStorageFailed());
      expect(repository.debugRevision, revision);
      final kept = await repository.load() as LoadReady;
      expect(kept.state.fingerprint, fingerprint);
      expect(
        kept.state.session.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        1,
      );

      final replaced = await repository.replaceDataset(
        expectedRevision: revision,
        bytes: replacement,
        fingerprint: DatasetFingerprint.of(replacement),
        snapshot: snapshot,
      );

      expect(replaced, isA<CommitSucceeded>());
      expect((replaced as CommitSucceeded).revision, revision + 1);
      final stored = await repository.load() as LoadReady;
      expect(stored.state.revision, revision + 1);
      expect(stored.state.fingerprint, DatasetFingerprint.of(replacement));
      expect(stored.state.export, isNull);
      expect(stored.state.dataset.storeName, 'Інший магазин');
      expect(reservedSession(stored.state.session, 'ORD-1'), 0);
    });

    test('commitExport writes the snapshot and document together', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 2);
      await app.issueOrder('ORD-1');
      final prepared = const CumulativeJsonExport().prepare(
        app.session!,
        now: () => DateTime(2026, 10, 3, 12),
      );
      expect(prepared, isA<CumulativeExportPrepared>());
      final ready = prepared as CumulativeExportPrepared;
      final document = ready.document;
      final snapshot = ready.pendingSession.capture(
        datasetFingerprint: app.fingerprint!,
      );
      repository.failNextCommit();

      final failed = await repository.commitExport(
        expectedRevision: app.revision!,
        snapshot: snapshot,
        document: document,
      );

      expect(failed, const CommitStorageFailed());
      final kept = await repository.load() as LoadReady;
      expect(kept.state.export, isNull);
      expect(kept.state.revision, app.revision);
      expect(kept.state.session.statusOf('ORD-1'), OrderStatus.issued);

      final stored = await repository.commitExport(
        expectedRevision: app.revision!,
        snapshot: snapshot,
        document: document,
      );

      expect(stored, isA<CommitSucceeded>());
      final after = await repository.load() as LoadReady;
      expect(after.state.revision, app.revision! + 1);
      expect(after.state.export!.filename, document.filename);
      expect(after.state.export!.bytes, document.bytes);
      expect(after.state.session.statusOf('ORD-1'), OrderStatus.exported);

      final continuedSession = switch (after.state.session.reserve(
        orderId: 'ORD-2',
        productId: productId,
        address: address,
        serialNumber: serial,
        quantity: 1,
      )) {
        ReserveApplied(:final session) => session,
        final rejected => fail('reserve failed: $rejected'),
      };
      final continued = await repository.commitSession(
        expectedRevision: after.state.revision,
        snapshot: continuedSession.capture(
          datasetFingerprint: after.state.fingerprint,
        ),
      );

      expect(continued, isA<CommitSucceeded>());
      final finalState = await repository.load() as LoadReady;
      expect(finalState.state.export!.filename, document.filename);
      expect(finalState.state.session.statusOf('ORD-1'), OrderStatus.exported);
      expect(reservedSession(finalState.state.session, 'ORD-2'), 1);
    });

    test(
      'commitExport rejects an inconsistent document without writing',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await reserve(app, quantity: 2);
        await app.issueOrder('ORD-1');
        final revision = app.revision!;
        final prepared = const CumulativeJsonExport().prepare(
          app.session!,
          now: () => DateTime(2026, 10, 3, 12),
        );
        final ready = prepared as CumulativeExportPrepared;
        final bad = ExportDocument(
          filename: ready.document.filename,
          bytes: Uint8List.fromList(const [1, 2, 3]),
          dateCreate: ready.document.dateCreate,
        );

        final rejected = await repository.commitExport(
          expectedRevision: revision,
          snapshot: ready.pendingSession.capture(
            datasetFingerprint: app.fingerprint!,
          ),
          document: bad,
        );

        expect(
          rejected,
          const CommitRejected(CommitRejection.invalidCandidate),
        );
        expect(repository.debugRevision, revision);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);
        final stored = await repository.load() as LoadReady;
        expect(stored.state.export, isNull);
        expect(stored.state.revision, revision);
        expect(stored.state.session.statusOf('ORD-1'), OrderStatus.issued);
      },
    );
  });

  group('dataset replacement', () {
    test('replaces an eligible session and increments revision once', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      final attempts = repository.commitAttempts;
      final next = catalogue(
        storeName: 'Інший магазин',
        dbName: 'Store_02-B',
        orderId: 'NEW-1',
      );

      final result = await app.replaceDataset(next);

      expect(result, isA<FulfilmentReplaced>());
      final replaced = result as FulfilmentReplaced;
      expect(replaced.revision, 2);
      expect(replaced.fingerprint, DatasetFingerprint.of(next));
      expect(app.session, same(replaced.session));
      expect(app.session, isNot(same(before)));
      expect(app.revision, 2);
      expect(app.fingerprint, replaced.fingerprint);
      expect(app.lastExport, isNull);
      expect(app.block, isNull);
      expect(app.session!.dataset.storeName, 'Інший магазин');
      expect(app.session!.dataset.dbName, 'Store_02-B');
      expect(app.session!.statusOf('NEW-1'), OrderStatus.noSelection);
      expect(app.session!.statusOf('ORD-1'), isNull);
      expect(reserved(app, 'ORD-1'), 0);
      expect(repository.commitAttempts, attempts + 1);
      expect(repository.debugRevision, 2);

      final stored = await persisted(repository);
      expect(stored.revision, 2);
      expect(stored.fingerprint, app.fingerprint);
      expect(stored.dataset.dbName, 'Store_02-B');
      expect(stored.export, isNull);
      expect(stored.session.statusOf('NEW-1'), OrderStatus.noSelection);
      expect(reservedSession(stored.session, 'ORD-1'), 0);
    });

    test('replaces a dataset that keeps the same dbName', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);
      await app.clearOrder('ORD-1');
      final revision = app.revision!;
      final next = catalogue(
        storeName: 'Інший магазин',
        serialNumber: 'SN-0002',
      );

      final result = await app.replaceDataset(next);

      expect(result, isA<FulfilmentReplaced>());
      expect(app.revision, revision + 1);
      expect(app.session!.dataset.dbName, 'Store_01-A');
      expect(app.session!.dataset.storeName, 'Інший магазин');
      expect(app.fingerprint, DatasetFingerprint.of(next));
      expect(reserved(app, 'ORD-1'), 0);
      expect(
        app.session!.availableQuantity(
          productId: productId,
          address: address,
          serialNumber: 'SN-0002',
        ),
        3,
      );
      expect(
        app.session!.availableQuantity(
          productId: productId,
          address: address,
          serialNumber: serial,
        ),
        0,
      );

      final stored = await persisted(repository);
      expect(stored.revision, revision + 1);
      expect(stored.dataset.dbName, 'Store_01-A');
      expect(reservedSession(stored.session, 'ORD-1'), 0);
    });

    test('identical bytes still replace the overlay', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);
      await app.clearOrder('ORD-1');
      final before = app.session!;
      final fingerprint = app.fingerprint!;
      final revision = app.revision!;
      final attempts = repository.commitAttempts;

      final result = await app.replaceDataset(datasetBytes());

      expect(result, isA<FulfilmentReplaced>());
      expect(app.session, isNot(same(before)));
      expect(app.revision, revision + 1);
      expect(app.fingerprint, fingerprint);
      expect(reserved(app, 'ORD-1'), 0);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(repository.commitAttempts, attempts + 1);

      final stored = await persisted(repository);
      expect(stored.revision, revision + 1);
      expect(stored.fingerprint, fingerprint);
      expect(reservedSession(stored.session, 'ORD-1'), 0);
    });

    test(
      'replaces after every issued order is exported and clears the export',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await storeExport(repository, app);
        final revision = app.revision!;
        final next = catalogue(
          storeName: 'Інший магазин',
          dbName: 'Store_02-B',
          orderId: 'NEW-1',
        );

        final result = await app.replaceDataset(next);

        expect(result, isA<FulfilmentReplaced>());
        expect(app.revision, revision + 1);
        expect(app.lastExport, isNull);
        expect(app.session!.dataset.dbName, 'Store_02-B');
        expect(app.session!.statusOf('ORD-1'), isNull);
        expect(reserved(app, 'ORD-1'), 0);

        final stored = await persisted(repository);
        expect(stored.revision, revision + 1);
        expect(stored.export, isNull);
        expect(stored.session.statusOf('ORD-1'), isNull);
        expect(stored.fingerprint, DatasetFingerprint.of(next));
      },
    );

    test('rejects replacement while an issued order is not exported', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 2);
      await app.issueOrder('ORD-1');
      final before = app.session!;
      final revision = app.revision!;
      final attempts = repository.commitAttempts;

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementRejected>());
      final rejected = result as FulfilmentReplacementRejected;
      expect(
        switch (rejected.result) {
          ReplacementBlocked(:final orderIds) => orderIds,
          final other => fail('expected a block, got $other'),
        },
        ['ORD-1'],
      );
      expect(app.session, same(before));
      expect(app.revision, revision);
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts);

      final stored = await persisted(repository);
      expect(stored.revision, revision);
      expect(stored.session.statusOf('ORD-1'), OrderStatus.issued);
      expect(stored.dataset.dbName, 'Store_01-A');
    });

    test('rejects replacement while an unissued reservation remains', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 1);
      final before = app.session!;
      final attempts = repository.commitAttempts;

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementRejected>());
      expect(
        switch ((result as FulfilmentReplacementRejected).result) {
          ReplacementBlocked(:final orderIds) => orderIds,
          final other => fail('expected a block, got $other'),
        },
        ['ORD-1'],
      );
      expect(app.session, same(before));
      expect(app.revision, 2);
      expect(app.block, isNull);
      expect(reserved(app, 'ORD-1'), 1);
      expect(repository.commitAttempts, attempts);

      final stored = await persisted(repository);
      expect(stored.revision, 2);
      expect(reservedSession(stored.session, 'ORD-1'), 1);
    });

    test('rejects invalid JSON without writing or blocking', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final attempts = repository.commitAttempts;

      final result = await app.replaceDataset(utf8.encode('{'));

      expect(result, isA<FulfilmentReplacementInputRejected>());
      final rejected = result as FulfilmentReplacementInputRejected;
      expect(rejected.failure.reason, DatasetRestoreReason.malformedJson);
      expect(rejected.failure.message, contains('Некоректний JSON'));
      expect(app.revision, 1);
      expect(app.block, isNull);
      expect(app.session!.dataset.storeName, 'Магазин Тест');
      expect(repository.commitAttempts, attempts);
      expect((await persisted(repository)).revision, 1);
    });

    test('rejects malformed UTF-8 without writing or blocking', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final attempts = repository.commitAttempts;

      final result = await app.replaceDataset(Uint8List.fromList(const [0x80]));

      expect(result, isA<FulfilmentReplacementInputRejected>());
      final rejected = result as FulfilmentReplacementInputRejected;
      expect(rejected.failure.reason, DatasetRestoreReason.malformedUtf8);
      expect(rejected.failure.message, isNull);
      expect(app.revision, 1);
      expect(app.block, isNull);
      expect(repository.commitAttempts, attempts);
      expect((await persisted(repository)).fingerprint, app.fingerprint);
    });

    test('rejects a dataset validation error without writing', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final attempts = repository.commitAttempts;
      final duplicate = _dataset.replaceFirst(
        '"stocks":[',
        '"stocks":[{"Address":"A-01","ProductID":$productId,'
            '"SerialNumber":"SN-0001","Quantity":5},',
      );

      final result = await app.replaceDataset(utf8.encode(duplicate));

      expect(result, isA<FulfilmentReplacementInputRejected>());
      final rejected = result as FulfilmentReplacementInputRejected;
      expect(rejected.failure.reason, DatasetRestoreReason.invalidDataset);
      expect(
        rejected.failure.message,
        DatasetMessages.duplicateStock(
          productId: productId,
          address: address,
          serialNumber: serial,
          firstIndex: 1,
          duplicateIndex: 2,
        ),
      );
      expect(app.revision, 1);
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
      expect(repository.commitAttempts, attempts);
      expect((await persisted(repository)).dataset.storeName, 'Магазин Тест');
    });

    test('keeps the previous export when the commit does not finish', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final document = await storeExport(repository, app);
      final before = app.session!;
      final revision = app.revision!;
      final fingerprint = app.fingerprint!;
      repository.failNextCommit();

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementFailed>());
      expect(app.block, PersistenceBlock.storageFailed);
      expect(app.canMutate, isFalse);
      expect(app.session, same(before));
      expect(app.revision, revision);
      expect(app.fingerprint, fingerprint);
      expect(app.lastExport, same(document));
      expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(repository.debugRevision, revision);

      final kept = await persisted(repository);
      expect(kept.revision, revision);
      expect(kept.fingerprint, fingerprint);
      expect(kept.export, isNotNull);
      expect(kept.export!.filename, document.filename);
      expect(kept.export!.bytes, document.bytes);
      expect(kept.session.statusOf('ORD-1'), OrderStatus.exported);
    });

    test(
      'stays blocked after a failed replacement and does not retry it',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await storeExport(repository, app);
        final revision = app.revision!;
        repository.failNextCommit();
        await app.replaceDataset(
          catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
        );
        final attempts = repository.commitAttempts;

        final ignored = await app.replaceDataset(
          catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
        );

        expect(ignored, isA<FulfilmentReplacementBlocked>());
        expect(app.block, PersistenceBlock.storageFailed);
        expect(repository.commitAttempts, attempts);
        expect(repository.debugRevision, revision);

        final recovered = await app.reload();

        expect(recovered, isA<LoadReady>());
        expect(app.block, isNull);
        expect(app.canMutate, isTrue);
        expect(app.revision, revision);
        expect(app.lastExport, isNotNull);
        expect(app.session!.dataset.storeName, 'Магазин Тест');
        expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect((await persisted(repository)).export, isNotNull);
      },
    );

    test(
      'a stale revision conflicts and the replacement is not retried',
      () async {
        final repository = MemoryFulfilmentRepository();
        final first = await imported(repository);
        final second = FulfilmentApplication(repository: repository);
        expect(await second.load(), isA<LoadReady>());
        final stale = second.session!;
        final next = catalogue(
          storeName: 'Інший магазин',
          dbName: 'Store_02-B',
          orderId: 'NEW-1',
        );

        expect(await first.replaceDataset(next), isA<FulfilmentReplaced>());
        expect(first.revision, 2);
        final attempts = repository.commitAttempts;

        final conflict = await second.replaceDataset(next);

        expect(conflict, isA<FulfilmentReplacementFailed>());
        expect(second.block, PersistenceBlock.revisionConflict);
        expect(second.session, same(stale));
        expect(second.revision, 1);
        expect(second.session!.dataset.dbName, 'Store_01-A');
        expect(first.session!.dataset.dbName, 'Store_02-B');

        final ignored = await second.replaceDataset(next);

        expect(ignored, isA<FulfilmentReplacementBlocked>());
        expect(repository.commitAttempts, attempts + 1);
        expect(repository.debugRevision, 2);

        expect(await second.reload(), isA<LoadReady>());
        expect(second.block, isNull);
        expect(second.revision, 2);
        expect(second.session!.dataset.dbName, 'Store_02-B');
        expect(second.session!.statusOf('NEW-1'), OrderStatus.noSelection);
        expect(
          (await persisted(repository)).dataset.storeName,
          'Інший магазин',
        );
      },
    );

    test(
      'does not activate the replacement until the commit finishes',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        final document = await storeExport(repository, app);
        final before = app.session!;
        final revision = app.revision!;
        final hold = repository.holdNextCommit();
        final next = catalogue(
          storeName: 'Інший магазин',
          dbName: 'Store_02-B',
        );

        final pending = app.replaceDataset(next);
        await hold.started;

        expect(app.session, same(before));
        expect(app.revision, revision);
        expect(app.lastExport, same(document));
        expect(repository.debugRevision, revision);
        expect(before.statusOf('ORD-1'), OrderStatus.exported);

        hold.release();
        final result = await pending;

        expect(result, isA<FulfilmentReplaced>());
        expect(app.session, isNot(same(before)));
        expect(app.revision, revision + 1);
        expect(app.lastExport, isNull);
        expect(repository.debugRevision, revision + 1);
        expect((await persisted(repository)).export, isNull);
      },
    );

    test('blocks replacement when the next revision would overflow', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      repository.debugRevision = StorageRevision.maximum;
      expect(await app.reload(), isA<LoadReady>());
      final before = app.session!;

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementFailed>());
      expect(app.block, PersistenceBlock.revisionOverflow);
      expect(app.session, same(before));
      expect(app.revision, StorageRevision.maximum);
      expect(repository.debugRevision, StorageRevision.maximum);

      expect(await app.reload(), isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.revision, StorageRevision.maximum);
      expect(app.session!.dataset.storeName, 'Магазин Тест');
    });

    test('storage unavailable blocks replacement without writing', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      repository.debugStorageUnavailable(true);

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementFailed>());
      expect(app.block, PersistenceBlock.storageUnavailable);
      expect(app.session, same(before));
      expect(app.revision, 1);

      repository.debugStorageUnavailable(false);
      expect(await app.reload(), isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.session!.dataset.storeName, 'Магазин Тест');
      expect((await persisted(repository)).revision, 1);
    });

    test('an unsupported schema is not overwritten', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      final before = app.session!;
      repository.debugSchemaVersion = 2;

      final result = await app.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(result, isA<FulfilmentReplacementFailed>());
      expect(app.block, PersistenceBlock.unsupportedVersion);
      expect(app.session, same(before));
      expect(repository.debugRevision, 1);
      expect(repository.debugSchemaVersion, 2);
      expect(await app.reload(), isA<LoadUnsupportedVersion>());
      expect(app.block, PersistenceBlock.unsupportedVersion);
      expect(app.session, same(before));
    });

    test(
      'corrupted storage blocks replacement and keeps the active session',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        final before = app.session!;
        repository.debugRevision = StorageRevision.maximum + 1;

        final result = await app.replaceDataset(
          catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
        );

        expect(result, isA<FulfilmentReplacementFailed>());
        expect(app.block, PersistenceBlock.corrupted);
        expect(app.session, same(before));
        expect(app.revision, 1);
        expect(app.session!.dataset.storeName, 'Магазин Тест');
        expect(repository.debugRevision, StorageRevision.maximum + 1);
      },
    );
  });

  group('cumulative export', () {
    test('exports the first issued order once', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 2);
      await app.issueOrder('ORD-1');
      final before = app.session!;
      final revision = app.revision!;
      final fingerprint = app.fingerprint!;
      final attempts = repository.commitAttempts;

      final result = await app.commitCumulativeExport(now: _exportClock);

      expect(result, isA<FulfilmentExported>());
      final exported = result as FulfilmentExported;
      expect(exported.revision, revision + 1);
      expect(
        exported.document.filename,
        'export_Store_01-A_$_exportStamp.json',
      );
      expect(exported.document.dateCreate, _exportStamp);
      expect(app.session, same(exported.session));
      expect(app.session, isNot(same(before)));
      expect(app.revision, revision + 1);
      expect(app.fingerprint, fingerprint);
      expect(app.lastExport, same(exported.document));
      expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(app.session!.statusOf('ORD-2'), OrderStatus.noSelection);
      expect(repository.commitAttempts, attempts + 1);
      expect(_orderIds(exported.document), ['ORD-1']);
      expect(_productLiteral(exported.document), productId);
      expect(_orderNumberLiteral(exported.document), '9007199254740993');

      final stored = await persisted(repository);
      expect(stored.revision, revision + 1);
      expect(stored.fingerprint, fingerprint);
      expect(stored.dataset.storeName, 'Магазин Тест');
      expect(stored.dataset.dbName, 'Store_01-A');
      expect(stored.session.statusOf('ORD-1'), OrderStatus.exported);
      expect(stored.session.statusOf('ORD-2'), OrderStatus.noSelection);
      expect(stored.export!.bytes, exported.document.bytes);
      expect(stored.export!.filename, exported.document.filename);
      expect(_orderIds(stored.export!), ['ORD-1']);
    });

    test('exports several issued orders without duplicating them', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await reserve(app, quantity: 2);
      await reserve(app, orderId: 'ORD-2', quantity: 1);
      await app.issueOrder('ORD-1');
      await app.issueOrder('ORD-2');
      final revision = app.revision!;

      final result = await app.commitCumulativeExport(now: _exportClock);

      expect(result, isA<FulfilmentExported>());
      expect(app.revision, revision + 1);
      expect(_orderIds(app.lastExport!), ['ORD-1', 'ORD-2']);
      expect(_orderIds(app.lastExport!).toSet(), {'ORD-1', 'ORD-2'});
      expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(app.session!.statusOf('ORD-2'), OrderStatus.exported);

      final stored = await persisted(repository);
      expect(stored.revision, revision + 1);
      expect(_orderIds(stored.export!), ['ORD-1', 'ORD-2']);
      expect(stored.session.statusOf('ORD-2'), OrderStatus.exported);
    });

    test('a later export keeps the previously exported orders', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await _issue(app, 'ORD-1', quantity: 2);
      expect(
        await app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      final firstBytes = Uint8List.fromList(app.lastExport!.bytes);
      final fingerprint = app.fingerprint;
      await _issue(app, 'ORD-2', quantity: 1);
      final revision = app.revision!;
      final attempts = repository.commitAttempts;

      final second = await app.commitCumulativeExport(
        now: () => DateTime(2026, 10, 14, 16, 8, 9),
      );

      expect(second, isA<FulfilmentExported>());
      expect(app.revision, revision + 1);
      expect(repository.commitAttempts, attempts + 1);
      expect(app.fingerprint, fingerprint);
      expect(app.lastExport!.filename, 'export_Store_01-A_20261014160809.json');
      expect(app.lastExport!.bytes, isNot(firstBytes));
      expect(_orderIds(app.lastExport!), ['ORD-1', 'ORD-2']);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(app.session!.statusOf('ORD-2'), OrderStatus.exported);

      final stored = await persisted(repository);
      expect(stored.revision, revision + 1);
      expect(stored.fingerprint, fingerprint);
      expect(_orderIds(stored.export!), ['ORD-1', 'ORD-2']);
    });

    test('does nothing when no newly issued order exists', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await _issue(app, 'ORD-1', quantity: 2);
      expect(
        await app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      final revision = app.revision!;
      final document = app.lastExport!;
      final attempts = repository.commitAttempts;

      final result = await app.commitCumulativeExport(
        now: () => fail('unchanged export read the clock'),
      );

      expect(result, isA<FulfilmentExportUnchanged>());
      expect((result as FulfilmentExportUnchanged).revision, revision);
      expect(app.revision, revision);
      expect(app.lastExport, same(document));
      expect(app.block, isNull);
      expect(repository.commitAttempts, attempts);
      final stored = await persisted(repository);
      expect(stored.revision, revision);
      expect(stored.export!.bytes, document.bytes);
    });

    test('a preparation rejection does not write or block', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(
        repository: repository,
        exports: const _RejectingExport(),
      );
      expect(
        await app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      await _issue(app, 'ORD-1', quantity: 2);
      final before = app.session!;
      final revision = app.revision!;
      final attempts = repository.commitAttempts;

      final result = await app.commitCumulativeExport(now: _exportClock);

      expect(result, isA<FulfilmentExportRejected>());
      expect(
        (result as FulfilmentExportRejected).failures.single.reason,
        CumulativeExportReason.reservationMismatch,
      );
      expect(app.session, same(before));
      expect(app.revision, revision);
      expect(app.lastExport, isNull);
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
      expect(repository.commitAttempts, attempts);
      final stored = await persisted(repository);
      expect(stored.revision, revision);
      expect(stored.export, isNull);
      expect(stored.session.statusOf('ORD-1'), OrderStatus.issued);
    });

    test(
      'keeps the pending export inactive until the commit finishes',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await _issue(app, 'ORD-1', quantity: 2);
        final before = app.session!;
        final revision = app.revision!;
        final hold = repository.holdNextCommit();

        final pending = app.commitCumulativeExport(now: _exportClock);
        await hold.started;

        expect(app.session, same(before));
        expect(app.revision, revision);
        expect(app.lastExport, isNull);
        expect(repository.debugRevision, revision);
        expect(before.statusOf('ORD-1'), OrderStatus.issued);

        hold.release();
        final result = await pending;

        expect(result, isA<FulfilmentExported>());
        expect(app.session, isNot(same(before)));
        expect(app.revision, revision + 1);
        expect(app.lastExport, isNotNull);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect((await persisted(repository)).export, isNotNull);
      },
    );

    test('a failed export keeps the previous session and document', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await imported(repository);
      await _issue(app, 'ORD-1', quantity: 2);
      expect(
        await app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      await _issue(app, 'ORD-2', quantity: 1);
      final before = app.session!;
      final revision = app.revision!;
      final document = app.lastExport!;
      repository.failNextCommit();

      final result = await app.commitCumulativeExport(
        now: () => DateTime(2026, 10, 14, 16, 8, 9),
      );

      expect(result, isA<FulfilmentExportFailed>());
      expect(app.block, PersistenceBlock.storageFailed);
      expect(app.canMutate, isFalse);
      expect(app.session, same(before));
      expect(app.revision, revision);
      expect(app.lastExport, same(document));
      expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(app.session!.statusOf('ORD-2'), OrderStatus.issued);
      expect(repository.debugRevision, revision);

      final stored = await persisted(repository);
      expect(stored.revision, revision);
      expect(stored.export!.bytes, document.bytes);
      expect(stored.session.statusOf('ORD-2'), OrderStatus.issued);
      expect(_orderIds(stored.export!), ['ORD-1']);
    });

    test(
      'stays blocked after a failed export and recovers on reload',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await _issue(app, 'ORD-1', quantity: 2);
        final revision = app.revision!;
        repository.failNextCommit();
        await app.commitCumulativeExport(now: _exportClock);
        final attempts = repository.commitAttempts;

        final ignored = await app.commitCumulativeExport(now: _exportClock);

        expect(ignored, isA<FulfilmentExportBlocked>());
        expect(repository.commitAttempts, attempts);
        expect(repository.debugRevision, revision);

        expect(await app.reload(), isA<LoadReady>());
        expect(app.block, isNull);
        expect(app.canMutate, isTrue);
        expect(app.revision, revision);
        expect(app.lastExport, isNull);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);

        final recovered = await app.commitCumulativeExport(now: _exportClock);
        expect(recovered, isA<FulfilmentExported>());
        expect(app.revision, revision + 1);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect((await persisted(repository)).export, isNotNull);
      },
    );

    test('a stale export conflicts and is not retried', () async {
      final repository = MemoryFulfilmentRepository();
      final first = await imported(repository);
      await _issue(first, 'ORD-1', quantity: 2);
      final second = FulfilmentApplication(repository: repository);
      expect(await second.load(), isA<LoadReady>());
      final stale = second.session!;
      final revision = second.revision!;

      expect(
        await first.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      expect(first.revision, revision + 1);
      final attempts = repository.commitAttempts;

      final conflict = await second.commitCumulativeExport(now: _exportClock);

      expect(conflict, isA<FulfilmentExportFailed>());
      expect(second.block, PersistenceBlock.revisionConflict);
      expect(second.session, same(stale));
      expect(second.revision, revision);
      expect(second.lastExport, isNull);
      expect(second.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(first.session!.statusOf('ORD-1'), OrderStatus.exported);

      final ignored = await second.commitCumulativeExport(now: _exportClock);
      expect(ignored, isA<FulfilmentExportBlocked>());
      expect(repository.commitAttempts, attempts + 1);
      expect(repository.debugRevision, revision + 1);

      expect(await second.reload(), isA<LoadReady>());
      expect(second.block, isNull);
      expect(second.revision, revision + 1);
      expect(second.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(second.lastExport!.bytes, first.lastExport!.bytes);
      expect(_orderIds(second.lastExport!), ['ORD-1']);
    });

    test(
      'restores a valid export and leaves an unexported issue out',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await _issue(app, 'ORD-1', quantity: 2);
        await app.commitCumulativeExport(now: _exportClock);
        await _issue(app, 'ORD-2', quantity: 1);
        final fingerprint = app.fingerprint!;

        final restored = FulfilmentApplication(repository: repository);
        expect(await restored.load(), isA<LoadReady>());

        expect(restored.revision, app.revision);
        expect(restored.fingerprint, fingerprint);
        expect(restored.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect(restored.session!.statusOf('ORD-2'), OrderStatus.issued);
        expect(restored.lastExport!.bytes, app.lastExport!.bytes);
        expect(_orderIds(restored.lastExport!), ['ORD-1']);
        expect(_orderIds(restored.lastExport!), isNot(contains('ORD-2')));

        final stored = await persisted(repository);
        expect(stored.session.statusOf('ORD-2'), OrderStatus.issued);
        expect(_orderIds(stored.export!), ['ORD-1']);
      },
    );

    test('rejects a corrupted export document on load', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await _exported(repository);
      final before = app.session!;
      repository.debugAlterExport(bytes: utf8.encode('{'), rehash: true);

      expect(await app.reload(), isA<LoadCorrupted>());
      expect(app.block, PersistenceBlock.corrupted);
      expect(app.session, same(before));
      expect(app.canMutate, isFalse);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadCorrupted>());
      expect(other.session, isNull);
      expect(other.lastExport, isNull);
    });

    test('rejects an export document with the wrong structure', () async {
      final repository = MemoryFulfilmentRepository();
      await _exported(repository);
      repository.debugAlterExport(
        bytes: utf8.encode(
          '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
          '"dateCreate":"$_exportStamp"}',
        ),
        rehash: true,
      );

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadCorrupted>());
      expect(other.lastExport, isNull);
    });

    test(
      'rejects an export whose order ids disagree with the snapshot',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await _exported(repository);
        final tampered = utf8
            .decode(app.lastExport!.bytes)
            .replaceFirst('"OrderID": "ORD-1"', '"OrderID": "ORD-2"');
        repository.debugAlterExport(bytes: utf8.encode(tampered), rehash: true);

        final other = FulfilmentApplication(repository: repository);
        expect(await other.load(), isA<LoadCorrupted>());
        expect(other.session, isNull);
      },
    );

    test('rejects an export for a different dataset identity', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await _exported(repository);
      final tampered = utf8
          .decode(app.lastExport!.bytes)
          .replaceFirst('Магазин Тест', 'Інший магазин');
      repository.debugAlterExport(bytes: utf8.encode(tampered), rehash: true);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadCorrupted>());
      expect(other.lastExport, isNull);
    });

    test('rejects an export filename or date that breaks the format', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await _exported(repository);
      repository.debugAlterExport(filename: 'export_Store_01-A_bad.json');

      final renamed = FulfilmentApplication(repository: repository);
      expect(await renamed.load(), isA<LoadCorrupted>());

      repository.debugAlterExport(
        filename: 'export_Store_01-A_$_exportStamp.json',
        dateCreate: '20261340150722',
      );
      final redated = FulfilmentApplication(repository: repository);
      expect(await redated.load(), isA<LoadCorrupted>());
      expect(redated.lastExport, isNull);
      expect(app.lastExport!.dateCreate, _exportStamp);
    });

    test('rejects tampered export bytes or a tampered digest', () async {
      final repository = MemoryFulfilmentRepository();
      final app = await _exported(repository);
      final bytes = Uint8List.fromList(app.lastExport!.bytes)..[0] ^= 0x01;
      repository.debugAlterExport(bytes: bytes);

      final changedBytes = FulfilmentApplication(repository: repository);
      expect(await changedBytes.load(), isA<LoadCorrupted>());

      repository.debugAlterExport(
        bytes: app.lastExport!.bytes,
        digest: 'ab' * 32,
      );
      final changedDigest = FulfilmentApplication(repository: repository);
      expect(await changedDigest.load(), isA<LoadCorrupted>());
      expect(changedDigest.session, isNull);
      expect(changedDigest.lastExport, isNull);
    });

    test(
      'overflow and unavailable storage do not activate an export',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = await imported(repository);
        await _issue(app, 'ORD-1', quantity: 2);
        repository.debugRevision = StorageRevision.maximum;
        expect(await app.reload(), isA<LoadReady>());
        final before = app.session!;

        final overflow = await app.commitCumulativeExport(now: _exportClock);

        expect(overflow, isA<FulfilmentExportFailed>());
        expect(app.block, PersistenceBlock.revisionOverflow);
        expect(app.session, same(before));
        expect(app.lastExport, isNull);
        expect(app.revision, StorageRevision.maximum);
        expect(repository.debugRevision, StorageRevision.maximum);

        expect(await app.reload(), isA<LoadReady>());
        repository.debugStorageUnavailable(true);
        final unavailable = await app.commitCumulativeExport(now: _exportClock);
        expect(unavailable, isA<FulfilmentExportFailed>());
        expect(app.block, PersistenceBlock.storageUnavailable);
        expect(app.lastExport, isNull);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);
      },
    );
  });

  group('commit notifications', () {
    test('notifies each successful commit in order', () async {
      final log = _CommitLog();
      final app = log.app;
      final fingerprint = DatasetFingerprint.of(datasetBytes());

      expect(
        await app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      expect(await reserve(app), isA<FulfilmentCommitted<ReserveResult>>());
      expect(
        await app.removeUnits(
          orderId: 'ORD-1',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<RemoveUnitsResult>>(),
      );
      expect(
        await reserve(app, orderId: 'ORD-2'),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await app.clearOrder('ORD-2'),
        isA<FulfilmentCommitted<ClearOrderResult>>(),
      );
      expect(
        await reserve(app, quantity: 2),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await app.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      expect(
        await app.cancelIssuance('ORD-1'),
        isA<FulfilmentCommitted<CancelIssuanceResult>>(),
      );
      expect(
        await app.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      expect(
        await app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );

      expect(log.notices, [
        ('1', fingerprint),
        ('2', fingerprint),
        ('3', fingerprint),
        ('4', fingerprint),
        ('5', fingerprint),
        ('6', fingerprint),
        ('7', fingerprint),
        ('8', fingerprint),
        ('9', fingerprint),
        ('10', fingerprint),
      ]);
      expect(log.sawStoredExport, isTrue);
      expect(app.lastExport, isNotNull);
    });

    test('dataset replacement notifies the new fingerprint', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      final next = catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B');

      final replaced = await log.app.replaceDataset(next);

      expect(replaced, isA<FulfilmentReplaced>());
      expect(log.notices, [
        ('1', DatasetFingerprint.of(datasetBytes())),
        ('2', DatasetFingerprint.of(next)),
      ]);
    });

    test('a revision conflict does not notify', () async {
      final repository = MemoryFulfilmentRepository();
      final writer = FulfilmentApplication(repository: repository);
      expect(
        await writer.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      final stale = _CommitLog(repository: repository);
      expect(await stale.app.load(), isA<LoadReady>());
      expect(await reserve(writer), isA<FulfilmentCommitted<ReserveResult>>());

      final conflict = await reserve(stale.app);

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(stale.app.block, PersistenceBlock.revisionConflict);
      expect(stale.notices, isEmpty);
    });

    test('storage failure does not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      log.repository.failNextCommit();

      final failed = await reserve(log.app);

      expect(failed, isA<FulfilmentBlocked<ReserveResult>>());
      expect(log.app.block, PersistenceBlock.storageFailed);
      expect(log.notices, hasLength(1));
    });

    test('domain rejection does not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      final rejected = await log.app.reserve(
        orderId: 'missing',
        productId: productId,
        address: address,
        serialNumber: serial,
        quantity: 1,
      );

      expect(rejected, isA<FulfilmentDomainRejected<ReserveResult>>());
      expect(log.app.block, isNull);
      expect(log.notices, hasLength(1));
    });

    test('a no-op clear does not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      final cleared = await log.app.clearOrder('ORD-1');

      expect(cleared, isA<FulfilmentUnchanged<ClearOrderResult>>());
      expect(log.notices, hasLength(1));
    });

    test('an unchanged cumulative export does not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      await _issue(log.app, 'ORD-1', quantity: 2);
      expect(
        await log.app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      final afterExport = log.notices.length;

      final unchanged = await log.app.commitCumulativeExport(now: _exportClock);

      expect(unchanged, isA<FulfilmentExportUnchanged>());
      expect(log.notices, hasLength(afterExport));
    });

    test('load and reload do not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      expect(await log.app.reload(), isA<LoadReady>());
      expect(log.notices, hasLength(1));

      final loaded = _CommitLog(repository: log.repository);
      expect(await loaded.app.load(), isA<LoadReady>());
      expect(loaded.notices, isEmpty);
    });

    test('sharing a stored export does not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      await _issue(log.app, 'ORD-1', quantity: 2);
      expect(
        await log.app.commitCumulativeExport(now: _exportClock),
        isA<FulfilmentExported>(),
      );
      final afterExport = log.notices.length;
      var shared = 0;
      final share = CumulativeExportShare(
        shareJson: ({required String filename, required Uint8List bytes}) {
          shared++;
          return Future<ExportShareResult>.value(const ExportShareHandedOff());
        },
      );

      final result = await share.share(log.app.lastExport);

      expect(result, isA<ExportShareHandedOff>());
      expect(shared, 1);
      expect(log.notices, hasLength(afterExport));
      expect(log.app.revision, afterExport);
    });

    test('blocked commands do not notify', () async {
      final log = _CommitLog();
      expect(
        await log.app.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      log.repository.failNextCommit();
      expect(await reserve(log.app), isA<FulfilmentBlocked<ReserveResult>>());

      final blocked = await reserve(log.app);

      expect(blocked, isA<FulfilmentBlocked<ReserveResult>>());
      expect(log.app.block, PersistenceBlock.storageFailed);
      expect(log.notices, hasLength(1));
      expect(log.repository.commitAttempts, 2);
    });

    test('a callback exception leaves the commit successful', () async {
      var calls = 0;
      final notices = <(String, String)>[];
      final fingerprint = DatasetFingerprint.of(datasetBytes());
      final app = FulfilmentApplication(
        repository: MemoryFulfilmentRepository(),
        onCommitted: (revision, fingerprint) {
          calls++;
          if (calls == 1) throw StateError('notify failed');
          notices.add((revision, fingerprint));
        },
      );

      final importedResult = await app.importDataset(datasetBytes());

      expect(importedResult, isA<FulfilmentImported>());
      expect(app.revision, 1);
      expect(app.fingerprint, fingerprint);
      expect(app.block, isNull);
      expect(app.canMutate, isTrue);
      expect(notices, isEmpty);

      final reserved = await reserve(app);

      expect(reserved, isA<FulfilmentCommitted<ReserveResult>>());
      expect(app.revision, 2);
      expect(app.block, isNull);
      expect(notices, [('2', fingerprint)]);
    });
  });
}

Uint8List datasetBytes() => Uint8List.fromList(utf8.encode(_dataset));

Future<FulfilmentApplication> imported(
  MemoryFulfilmentRepository repository,
) async {
  final app = FulfilmentApplication(repository: repository);
  final result = await app.importDataset(datasetBytes());
  expect(result, isA<FulfilmentImported>());
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

int reserved(FulfilmentApplication app, String orderId) {
  return reservedSession(app.session!, orderId);
}

int reservedSession(FulfilmentSession session, String orderId) {
  return session.lineReservedQuantity(orderId: orderId, productId: productId);
}

Uint8List catalogue({
  String storeName = 'Магазин Тест',
  String dbName = 'Store_01-A',
  String? serialNumber,
  String? orderId,
}) {
  var source = _dataset
      .replaceFirst('Магазин Тест', storeName)
      .replaceFirst('Store_01-A', dbName);
  if (serialNumber != null) {
    source = source
        .replaceFirst(
          '"SerialNumber":"SN-0001"',
          '"SerialNumber":"$serialNumber"',
        )
        .replaceFirst('"Quantity":5', '"Quantity":3');
  }
  if (orderId != null) {
    source = source.replaceFirst('"OrderID":"ORD-1"', '"OrderID":"$orderId"');
  }
  return Uint8List.fromList(utf8.encode(source));
}

Future<ExportDocument> storeExport(
  MemoryFulfilmentRepository repository,
  FulfilmentApplication app,
) async {
  await reserve(app, quantity: 2);
  expect(
    await app.issueOrder('ORD-1'),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
  final exported = await app.commitCumulativeExport(now: _exportClock);
  expect(exported, isA<FulfilmentExported>());
  expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
  expect(app.lastExport!.dateCreate, _exportStamp);
  expect(repository.debugRevision, app.revision);
  return app.lastExport!;
}

const _exportStamp = '20261014150722';

DateTime _exportClock() => DateTime(2026, 10, 14, 15, 7, 22);

Future<void> _issue(
  FulfilmentApplication app,
  String orderId, {
  required int quantity,
}) async {
  expect(
    await reserve(app, orderId: orderId, quantity: quantity),
    isA<FulfilmentCommitted<ReserveResult>>(),
  );
  expect(
    await app.issueOrder(orderId),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
}

Future<FulfilmentApplication> _exported(
  MemoryFulfilmentRepository repository,
) async {
  final app = await imported(repository);
  await _issue(app, 'ORD-1', quantity: 2);
  expect(
    await app.commitCumulativeExport(now: _exportClock),
    isA<FulfilmentExported>(),
  );
  return app;
}

List<String> _orderIds(ExportDocument document) {
  final root = _exportRoot(document);
  final orders = root.fields['orders']! as JsonArrayValue;
  return [
    for (final item in orders.items)
      ((item as JsonObjectValue).fields['OrderID']! as JsonStringValue).text,
  ];
}

String _productLiteral(ExportDocument document) {
  final good = _firstGood(document);
  return (good.fields['ProductID']! as JsonNumberValue).literal;
}

String _orderNumberLiteral(ExportDocument document) {
  final root = _exportRoot(document);
  final order =
      (root.fields['orders']! as JsonArrayValue).items.first as JsonObjectValue;
  return (order.fields['OrderNumber']! as JsonNumberValue).literal;
}

JsonObjectValue _firstGood(ExportDocument document) {
  final root = _exportRoot(document);
  final order =
      (root.fields['orders']! as JsonArrayValue).items.first as JsonObjectValue;
  return (order.fields['Goods']! as JsonArrayValue).items.first
      as JsonObjectValue;
}

JsonObjectValue _exportRoot(ExportDocument document) {
  final value = const PrecisionJsonDecoder().decode(
    utf8.decode(document.bytes),
  );
  return value as JsonObjectValue;
}

class _RejectingExport extends CumulativeJsonExport {
  const _RejectingExport();

  @override
  CumulativeExportResult prepare(
    FulfilmentSession session, {
    DateTime Function()? now,
  }) {
    return const CumulativeExportRejected([
      CumulativeExportFailure(
        reason: CumulativeExportReason.reservationMismatch,
        orderId: 'ORD-1',
        productId: productId,
      ),
    ]);
  }
}

Future<PersistedFulfilment> persisted(
  MemoryFulfilmentRepository repository,
) async {
  final result = await repository.load();
  expect(result, isA<LoadReady>());
  return (result as LoadReady).state;
}

/// Records [FulfilmentApplication.onCommitted] and checks that the instance
/// already holds the notified revision and fingerprint.
final class _CommitLog {
  _CommitLog({MemoryFulfilmentRepository? repository})
    : repository = repository ?? MemoryFulfilmentRepository() {
    app = FulfilmentApplication(
      repository: this.repository,
      onCommitted: (revision, fingerprint) {
        expect(app.revision.toString(), revision);
        expect(app.fingerprint, fingerprint);
        expect(app.session, isNotNull);
        if (app.lastExport != null) {
          expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
          sawStoredExport = true;
        }
        notices.add((revision, fingerprint));
      },
    );
  }

  final MemoryFulfilmentRepository repository;
  late final FulfilmentApplication app;
  final List<(String, String)> notices = [];
  bool sawStoredExport = false;
}

SessionSnapshot emptySnapshot(Uint8List bytes) {
  final fingerprint = DatasetFingerprint.of(bytes);
  final restored = const DatasetByteRestore().restore(
    bytes: bytes,
    expectedFingerprint: fingerprint,
  );
  final dataset = switch (restored) {
    DatasetRestored(:final dataset) => dataset,
    final other => fail('replacement did not restore: $other'),
  };
  final opened = switch (FulfilmentSession.open(dataset)) {
    DatasetOpened(:final session) => session,
    final other => fail('replacement did not open: $other'),
  };
  return opened.capture(datasetFingerprint: fingerprint);
}
