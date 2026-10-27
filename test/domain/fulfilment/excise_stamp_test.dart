import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/domain/fulfilment/excise_stamp.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';

import '../../support/memory_fulfilment_repository.dart';

const _stampA = 'QWER123456';
const _stampB = 'ASDF654321';
const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('ExciseStamp.normalize', () {
    test('accepts a canonical stamp and uppercases Latin letters', () {
      expect(ExciseStamp.normalize(_stampA), _stampA);
      expect(ExciseStamp.normalize('qwer123456'), _stampA);
      expect(ExciseStamp.normalize('QwEr123456'), _stampA);
      expect(ExciseStamp.isValid(_stampA), isTrue);
    });

    test('rejects Cyrillic, length, spaces, and other characters', () {
      expect(ExciseStamp.normalize('QWE123456'), isNull);
      expect(ExciseStamp.normalize('QWER12345'), isNull);
      expect(ExciseStamp.normalize('QWER1234567'), isNull);
      expect(ExciseStamp.normalize('\u0410BCD123456'), isNull);
      expect(ExciseStamp.normalize('QWER 12345'), isNull);
      expect(ExciseStamp.normalize('QWER12345 '), isNull);
      expect(ExciseStamp.normalize(''), isNull);
      expect(ExciseStamp.normalize('QWE-123456'), isNull);
    });
  });

  group('alcohol reservations', () {
    test('stores one stamp per unit and rejects a missing stamp', () {
      final session = alcohol(quantity: 2);
      final before = session.capture(datasetFingerprint: _fingerprint);

      final missing = session.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );
      final applied = mustApply(session, exciseStamps: const ['qwer123456']);

      expect(missing, isA<ReserveRejected>());
      expect(
        (missing as ReserveRejected).reason,
        ReserveRejection.invalidExciseStamp,
      );
      expect(session.capture(datasetFingerprint: _fingerprint), before);
      expect(applied.appliedQuantity, 1);
      expect(stamps(applied.session), [_stampA]);
      expect(slotQuantity(applied.session), 1);
      expect(available(applied.session), 4);
    });

    test('keeps a separate stamp for every unit of one serial', () {
      final first = mustApply(
        alcohol(quantity: 2),
        exciseStamps: const [_stampA],
      ).session;
      final second = mustApply(first, exciseStamps: const [_stampB]).session;

      expect(stamps(second), [_stampA, _stampB]);
      expect(slotQuantity(second), 2);
      expect(available(second), 3);

      final removed = mustDrop(second, _stampB);
      expect(removed.removedQuantity, 1);
      expect(stamps(removed.session), [_stampA]);
      expect(slotQuantity(removed.session), 1);

      final cleared = switch (removed.session.clearOrder('ORD-1')) {
        OrderCleared(:final session) => session,
        final other => fail('clear failed: $other'),
      };
      expect(stamps(cleared), isEmpty);
      expect(slotQuantity(cleared), 0);
      expect(available(cleared), 5);
    });

    test('two serials keep their own stamps', () {
      final opened = open(
        stocks: [
          slot(serialNumber: 'SN-1'),
          slot(serialNumber: 'SN-2'),
        ],
        goods: [line(quantity: 2)],
      );
      final first = mustApply(
        opened,
        serialNumber: 'SN-1',
        exciseStamps: const [_stampA],
      ).session;
      final second = mustApply(
        first,
        serialNumber: 'SN-2',
        exciseStamps: const [_stampB],
      ).session;

      expect(
        second.slotExciseStamps(
          orderId: 'ORD-1',
          productId: '100',
          address: 'A-01',
          serialNumber: 'SN-1',
        ),
        [_stampA],
      );
      expect(
        second.slotExciseStamps(
          orderId: 'ORD-1',
          productId: '100',
          address: 'A-01',
          serialNumber: 'SN-2',
        ),
        [_stampB],
      );
      expect(
        second.lineReservedQuantity(orderId: 'ORD-1', productId: '100'),
        2,
      );
    });

    test(
      'does not reserve alcohol when every supplied stamp cannot be stored',
      () {
        final session = alcohol(stock: 1, quantity: 2);
        final result = session.reserve(
          orderId: 'ORD-1',
          productId: '100',
          address: 'A-01',
          serialNumber: 'SN-1',
          quantity: 2,
          exciseStamps: const [_stampA, _stampB],
        );

        expect(result, isA<ReserveRejected>());
        expect(
          (result as ReserveRejected).reason,
          ReserveRejection.exciseQuantity,
        );
        expect(slotQuantity(session), 0);
        expect(available(session), 1);
      },
    );

    test('a regular reservation still applies a partial quantity', () {
      final session = alcohol(stock: 1, quantity: 2, alko: false);
      final applied = mustApply(session, quantity: 2);

      expect(applied.appliedQuantity, 1);
      expect(stamps(applied.session), isEmpty);
      expect(available(applied.session), 0);
    });

    test('a regular product rejects an excise stamp', () {
      final session = alcohol(alko: false);
      final result = session.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
        exciseStamps: const [_stampA],
      );

      expect(
        (result as ReserveRejected).reason,
        ReserveRejection.unexpectedExciseStamp,
      );
      expect(slotQuantity(session), 0);
    });
  });

  group('restore', () {
    test('restores stamps and reads a legacy reservation without them', () {
      final dataset = catalogue(goods: [line(quantity: 2)]);
      final reserved = mustApply(
        mustOpen(dataset),
        exciseStamps: const [_stampA],
      ).session;
      final again = mustApply(
        reserved,
        exciseStamps: const ['asdf654321'],
      ).session;
      final snapshot = again.capture(datasetFingerprint: _fingerprint);
      final restored = mustRestore(dataset, snapshot);

      expect(stamps(restored), [_stampA, _stampB]);
      expect(restored.capture(datasetFingerprint: _fingerprint), snapshot);
      expect(restored.statusOf('ORD-1'), OrderStatus.readyForIssue);

      final legacy = SessionSnapshot(
        schemaVersion: 1,
        datasetFingerprint: _fingerprint,
        reservations: const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 2,
          ),
        ],
        issuedOrderIds: const [],
        exportedOrderIds: const [],
      );
      final regular = catalogue(goods: [line(quantity: 2, alko: false)]);
      final restoredLegacy = mustRestore(regular, legacy);
      expect(stamps(restoredLegacy), isEmpty);
      expect(slotQuantity(restoredLegacy), 2);
    });

    test('rejects an alcohol reservation that has no valid stamp', () {
      final dataset = catalogue(goods: [line()]);
      final missing = restoreOf(
        dataset,
        snap(const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
          ),
        ]),
      );
      final invalid = restoreOf(
        dataset,
        snap(const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
            exciseStamps: ['qwer123456'],
          ),
        ]),
      );

      expect(reason(missing), SessionRestoreReason.invalidExciseStamp);
      expect(reason(invalid), SessionRestoreReason.invalidExciseStamp);
    });
  });

  group('excise stamp uniqueness', () {
    test('rejects a second copy of a stamp in the same order', () {
      final held = mustApply(
        alcohol(quantity: 2),
        exciseStamps: const [_stampA],
      ).session;
      final before = held.capture(datasetFingerprint: _fingerprint);

      final rejected = held.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
        exciseStamps: const [_stampA],
      );
      final fresh = alcohol(quantity: 2);
      final repeated = fresh.reserve(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 2,
        exciseStamps: const [_stampA, _stampA],
      );

      expect(duplicateOf(rejected), _stampA);
      expect(duplicateOf(repeated), _stampA);
      expect(held.capture(datasetFingerprint: _fingerprint), before);
      expect(slotQuantity(held), 1);
      expect(available(held), 4);
      expect(stamps(fresh), isEmpty);
      expect(slotQuantity(fresh), 0);
    });

    test('rejects a stamp already reserved on another order', () {
      final opened = catalogueOf(
        stocks: [slot(quantity: 5)],
        orders: [
          order(goods: [line()]),
          order(orderId: 'ORD-2', orderNumber: '2', goods: [line()]),
        ],
      );
      final held = mustApply(opened, exciseStamps: const [_stampA]).session;
      final before = held.capture(datasetFingerprint: _fingerprint);

      final rejected = held.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
        exciseStamps: const [_stampA],
      );

      expect(duplicateOf(rejected), _stampA);
      expect(held.capture(datasetFingerprint: _fingerprint), before);
      expect(slotQuantity(held), 1);
      expect(held.lineReservedQuantity(orderId: 'ORD-2', productId: '100'), 0);
    });

    test('rejects a stamp already reserved on another product', () {
      final opened = catalogueOf(
        stocks: [
          slot(),
          slot(productId: '200', serialNumber: 'SN-2'),
        ],
        orders: [
          order(
            goods: [
              line(),
              line(productId: '200', product: 'Вино'),
            ],
          ),
        ],
      );
      final held = mustApply(opened, exciseStamps: const [_stampA]).session;
      final before = held.capture(datasetFingerprint: _fingerprint);

      final rejected = held.reserve(
        orderId: 'ORD-1',
        productId: '200',
        address: 'A-01',
        serialNumber: 'SN-2',
        quantity: 1,
        exciseStamps: const [_stampA],
      );

      expect(duplicateOf(rejected), _stampA);
      expect(held.capture(datasetFingerprint: _fingerprint), before);
      expect(
        held.slotExciseStamps(
          orderId: 'ORD-1',
          productId: '200',
          address: 'A-01',
          serialNumber: 'SN-2',
        ),
        isEmpty,
      );
    });

    test('rejects a lowercase copy of a stamp on an issued order', () {
      final opened = catalogueOf(
        stocks: [slot()],
        orders: [
          order(goods: [line()]),
          order(orderId: 'ORD-2', orderNumber: '2', goods: [line()]),
        ],
      );
      final ready = mustApply(opened, exciseStamps: const [_stampA]).session;
      final issued = mustIssue(ready);
      final before = issued.capture(datasetFingerprint: _fingerprint);

      final rejected = issued.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
        exciseStamps: const ['qwer123456'],
      );
      final removed = issued.removeAlcoholUnit(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: _stampA,
      );

      expect(duplicateOf(rejected), _stampA);
      expect(removed, isA<RemoveUnitsRejected>());
      expect(
        (removed as RemoveUnitsRejected).reason,
        RemoveRejection.orderLocked,
      );
      expect(issued.capture(datasetFingerprint: _fingerprint), before);
      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(stamps(issued), [_stampA]);
    });

    test('rejects a stamp that belongs to an exported order', () {
      final opened = catalogueOf(
        stocks: [slot()],
        orders: [
          order(goods: [line()]),
          order(orderId: 'ORD-2', orderNumber: '2', goods: [line()]),
        ],
      );
      final exported = mustExport(
        mustIssue(mustApply(opened, exciseStamps: const [_stampA]).session),
      );
      final before = exported.capture(datasetFingerprint: _fingerprint);

      final rejected = exported.reserve(
        orderId: 'ORD-2',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
        exciseStamps: const [_stampA],
      );

      expect(duplicateOf(rejected), _stampA);
      expect(exported.capture(datasetFingerprint: _fingerprint), before);
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(available(exported), 4);
    });

    test('removes one named stamp and leaves the other units', () {
      var held = alcohol(quantity: 3);
      held = mustApply(held, exciseStamps: const [_stampA]).session;
      held = mustApply(held, exciseStamps: const [_stampB]).session;
      held = mustApply(held, exciseStamps: const ['ZXCV112233']).session;
      final before = held.capture(datasetFingerprint: _fingerprint);

      final lifo = held.removeUnits(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        quantity: 1,
      );
      final missing = held.removeAlcoholUnit(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: 'QQQQ000000',
      );
      final removed = mustDrop(held, 'asdf654321');

      expect(
        (lifo as RemoveUnitsRejected).reason,
        RemoveRejection.alcoholRequiresStamp,
      );
      expect(
        (missing as RemoveUnitsRejected).reason,
        RemoveRejection.exciseStampNotFound,
      );
      expect(held.capture(datasetFingerprint: _fingerprint), before);
      expect(stamps(removed.session), [_stampA, 'ZXCV112233']);
      expect(slotQuantity(removed.session), 2);
      expect(available(removed.session), 3);

      final reused = mustApply(
        removed.session,
        exciseStamps: const [_stampB],
      ).session;
      expect(stamps(reused), [_stampA, 'ZXCV112233', _stampB]);
      expect(slotQuantity(reused), 3);
    });

    test('a regular product still removes by quantity', () {
      final reserved = mustApply(
        alcohol(quantity: 3, alko: false),
        quantity: 2,
      ).session;
      final before = reserved.capture(datasetFingerprint: _fingerprint);
      final exact = reserved.removeAlcoholUnit(
        orderId: 'ORD-1',
        productId: '100',
        address: 'A-01',
        serialNumber: 'SN-1',
        exciseStamp: _stampA,
      );
      final removed = mustRemove(reserved);

      expect((exact as RemoveUnitsRejected).reason, RemoveRejection.notAlcohol);
      expect(reserved.capture(datasetFingerprint: _fingerprint), before);
      expect(stamps(reserved), isEmpty);
      expect(removed.removedQuantity, 1);
      expect(slotQuantity(removed.session), 1);
      expect(stamps(removed.session), isEmpty);
      expect(available(removed.session), 4);
    });

    test('restore rejects a snapshot that repeats a stamp', () {
      final sameSlot = restoreOf(
        alcohol(quantity: 2).dataset,
        snap(const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 2,
            exciseStamps: [_stampA, _stampA],
          ),
        ]),
      );
      final twoSerials = restoreOf(
        catalogueOf(
          stocks: [
            slot(),
            slot(serialNumber: 'SN-2'),
          ],
          orders: [
            order(goods: [line(quantity: 2)]),
          ],
        ).dataset,
        snap(const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 1,
            exciseStamps: [_stampA],
          ),
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-2',
            quantity: 1,
            exciseStamps: [_stampA],
          ),
        ]),
      );

      expect(sameSlot, isA<SessionRestoreRejected>());
      expect(twoSerials, isA<SessionRestoreRejected>());
      expect(reason(sameSlot), SessionRestoreReason.duplicateExciseStamp);
      expect(reason(twoSerials), SessionRestoreReason.duplicateExciseStamp);
    });
  });

  group('persistence', () {
    test(
      'a failed commit does not keep the stamp, and a reload does',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = FulfilmentApplication(repository: repository);
        expect(await app.importDataset(_bytes()), isA<FulfilmentImported>());
        repository.failNextCommit();

        final failed = await _reserve(app, _stampA);

        expect(failed, isA<FulfilmentBlocked<ReserveResult>>());
        expect(app.block, PersistenceBlock.storageFailed);
        expect(_storedStamps(app), isEmpty);
        expect(app.revision, 1);

        expect(await app.reload(), isA<LoadReady>());
        final committed = await _reserve(app, 'qwer123456');
        expect(committed, isA<FulfilmentCommitted<ReserveResult>>());

        final again = FulfilmentApplication(repository: repository);
        expect(await again.load(), isA<LoadReady>());
        expect(_storedStamps(again), [_stampA]);
        expect(again.revision, 2);
        expect(
          again.session!.dataset.orders.single.goods.single.isAlko,
          isTrue,
        );
      },
    );

    test('a stale revision cannot overwrite the stored stamp', () async {
      final repository = MemoryFulfilmentRepository();
      final first = FulfilmentApplication(repository: repository);
      final second = FulfilmentApplication(repository: repository);
      expect(await first.importDataset(_bytes()), isA<FulfilmentImported>());
      expect(await second.load(), isA<LoadReady>());

      expect(
        await _reserve(first, _stampA),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      final conflict = await _reserve(second, _stampB);

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(second.block, PersistenceBlock.revisionConflict);
      expect(_storedStamps(second), isEmpty);

      expect(await second.reload(), isA<LoadReady>());
      expect(_storedStamps(second), [_stampA]);
      expect(second.revision, 2);
    });

    test('a reloaded session rejects a duplicate stamp', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(repository: repository);
      expect(await app.importDataset(_bytes()), isA<FulfilmentImported>());
      expect(
        await _reserve(app, _stampA),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );

      final again = FulfilmentApplication(repository: repository);
      expect(await again.load(), isA<LoadReady>());
      final attempts = repository.commitAttempts;
      final duplicate = await _reserve(again, 'qwer123456');

      expect(duplicate, isA<FulfilmentDomainRejected<ReserveResult>>());
      final rejected =
          (duplicate as FulfilmentDomainRejected<ReserveResult>).result;
      expect(duplicateOf(rejected), _stampA);
      expect(repository.commitAttempts, attempts);
      expect(again.revision, 2);
      expect(_storedStamps(again), [_stampA]);
      expect(stamps(again.session!), [_stampA]);
    });

    test(
      'a conflicting tab reloads and does not retry the reservation',
      () async {
        final repository = MemoryFulfilmentRepository();
        final first = FulfilmentApplication(repository: repository);
        final second = FulfilmentApplication(repository: repository);
        expect(await first.importDataset(_bytes()), isA<FulfilmentImported>());
        expect(await second.load(), isA<LoadReady>());
        expect(
          await _reserve(first, _stampA),
          isA<FulfilmentCommitted<ReserveResult>>(),
        );

        final conflict = await _reserve(second, 'qwer123456');
        final attempts = repository.commitAttempts;
        final whileBlocked = await _reserve(second, _stampB);

        expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
        expect(second.block, PersistenceBlock.revisionConflict);
        expect(whileBlocked, isA<FulfilmentBlocked<ReserveResult>>());
        expect(repository.commitAttempts, attempts);
        expect(_storedStamps(second), isEmpty);

        expect(await second.reload(), isA<LoadReady>());
        final retry = await _reserve(second, _stampA);
        expect(retry, isA<FulfilmentDomainRejected<ReserveResult>>());
        expect(
          duplicateOf(
            (retry as FulfilmentDomainRejected<ReserveResult>).result,
          ),
          _stampA,
        );
        expect(repository.commitAttempts, attempts);
        expect(second.revision, 2);
        expect(_storedStamps(second), [_stampA]);
        expect(second.session!.statusOf('ORD-1'), OrderStatus.inProgress);
      },
    );

    test(
      'an issued alcohol order exports and reloads with its stamps',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = FulfilmentApplication(repository: repository);
        expect(await app.importDataset(_bytes()), isA<FulfilmentImported>());
        expect(
          await _reserve(app, _stampA),
          isA<FulfilmentCommitted<ReserveResult>>(),
        );
        expect(
          await _reserve(app, _stampB),
          isA<FulfilmentCommitted<ReserveResult>>(),
        );
        expect(
          await app.issueOrder('ORD-1'),
          isA<FulfilmentCommitted<IssueOrderResult>>(),
        );
        final issuedRevision = app.revision;

        final exported = await app.commitCumulativeExport(
          now: () => DateTime(2026, 10, 14, 15, 7, 22),
        );

        expect(exported, isA<FulfilmentExported>());
        final document = (exported as FulfilmentExported).document;
        final text = utf8.decode(document.bytes);
        expect(text, contains('"ExciseStamp": "$_stampA"'));
        expect(text, contains('"ExciseStamp": "$_stampB"'));
        expect(text, contains('"ProductID": 100'));
        expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect(_storedStamps(app), [_stampA, _stampB]);
        expect(app.revision, issuedRevision! + 1);

        final again = FulfilmentApplication(repository: repository);
        expect(await again.load(), isA<LoadReady>());
        expect(again.revision, app.revision);
        expect(again.session!.statusOf('ORD-1'), OrderStatus.exported);
        expect(_storedStamps(again), [_stampA, _stampB]);
        expect(again.lastExport!.bytes, document.bytes);
      },
    );

    test('a failed alcohol export does not mark the order exported', () async {
      final repository = MemoryFulfilmentRepository();
      final app = FulfilmentApplication(repository: repository);
      expect(await app.importDataset(_bytes()), isA<FulfilmentImported>());
      expect(
        await _reserve(app, _stampA),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await _reserve(app, _stampB),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await app.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      final revision = app.revision;
      repository.failNextCommit();

      final failed = await app.commitCumulativeExport(
        now: () => DateTime(2026, 10, 14, 15, 7, 22),
      );

      expect(failed, isA<FulfilmentExportFailed>());
      expect(app.block, PersistenceBlock.storageFailed);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(_storedStamps(app), [_stampA, _stampB]);
      expect(app.lastExport, isNull);

      expect(await app.reload(), isA<LoadReady>());
      expect(app.block, isNull);
      expect(app.revision, revision);
      expect(app.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(_storedStamps(app), [_stampA, _stampB]);
      expect(app.lastExport, isNull);
    });

    test(
      'export after replacing one stamp keeps the stamp that stayed',
      () async {
        final repository = MemoryFulfilmentRepository();
        final app = FulfilmentApplication(repository: repository);
        expect(await app.importDataset(_bytes()), isA<FulfilmentImported>());
        expect(
          await _reserve(app, _stampA),
          isA<FulfilmentCommitted<ReserveResult>>(),
        );
        expect(
          await _reserve(app, _stampB),
          isA<FulfilmentCommitted<ReserveResult>>(),
        );
        expect(
          await app.removeAlcoholUnit(
            orderId: 'ORD-1',
            productId: '100',
            address: 'A-01',
            serialNumber: 'SN-1',
            exciseStamp: _stampA,
          ),
          isA<FulfilmentCommitted<RemoveUnitsResult>>(),
        );
        expect(
          await _reserve(app, _stampA),
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
        final text = utf8.decode(
          (exported as FulfilmentExported).document.bytes,
        );
        expect(text, contains('"ExciseStamp": "$_stampB"'));
        expect(text, contains('"ExciseStamp": "$_stampA"'));
        expect(_storedStamps(app), [_stampB, _stampA]);
        expect(app.session!.statusOf('ORD-1'), OrderStatus.exported);
      },
    );
  });
}

Future<FulfilmentCommandResult<ReserveResult>> _reserve(
  FulfilmentApplication app,
  String stamp,
) {
  return app.reserve(
    orderId: 'ORD-1',
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
    quantity: 1,
    exciseStamps: [stamp],
  );
}

List<String> _storedStamps(FulfilmentApplication app) => stamps(app.session!);

Uint8List _bytes() => Uint8List.fromList(
  utf8.encode(
    '{"storeName":"Магазин","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":100,"SerialNumber":"SN-1","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"INV","OrderNumber":1,"Customer":"Клієнт",'
    '"CustomerPhone":"0501112233","Goods":[{"Product":"Алкоголь",'
    '"ProductID":100,"Quantity":2,"Price":10.00,"Amount":10.00,'
    '"isServiceGood":0,"isParcel":0,"isAlko":1}]}]}',
  ),
);

FulfilmentSession alcohol({int stock = 5, int quantity = 1, bool alko = true}) {
  return open(
    stocks: [slot(quantity: stock)],
    goods: [line(quantity: quantity, alko: alko)],
  );
}

FulfilmentSession open({
  required List<DatasetStock> stocks,
  required List<DatasetGood> goods,
}) {
  return mustOpen(catalogue(stocks: stocks, goods: goods));
}

FulfilmentSession mustOpen(RetailDataset dataset) {
  return switch (FulfilmentSession.open(dataset)) {
    DatasetOpened(:final session) => session,
    DatasetRejected(:final problem) => fail('dataset rejected: $problem'),
  };
}

ReserveApplied mustApply(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
  String serialNumber = 'SN-1',
  int quantity = 1,
  List<String> exciseStamps = const [],
}) {
  return switch (session.reserve(
    orderId: orderId,
    productId: productId,
    address: 'A-01',
    serialNumber: serialNumber,
    quantity: quantity,
    exciseStamps: exciseStamps,
  )) {
    ReserveApplied() && final applied => applied,
    final other => fail('reserve failed: $other'),
  };
}

UnitsRemoved mustDrop(FulfilmentSession session, String exciseStamp) {
  return switch (session.removeAlcoholUnit(
    orderId: 'ORD-1',
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
    exciseStamp: exciseStamp,
  )) {
    UnitsRemoved() && final removed => removed,
    final other => fail('remove failed: $other'),
  };
}

String duplicateOf(ReserveResult result) {
  return switch (result) {
    ReserveRejected(:final reason, :final exciseStamp)
        when reason == ReserveRejection.duplicateExciseStamp &&
            exciseStamp != null =>
      exciseStamp,
    final other => fail('expected a duplicate stamp: $other'),
  };
}

FulfilmentSession mustIssue(FulfilmentSession session) {
  return switch (session.issueOrder('ORD-1')) {
    OrderIssued(:final session) => session,
    final other => fail('issue failed: $other'),
  };
}

FulfilmentSession mustExport(FulfilmentSession session) {
  return switch (session.markExported('ORD-1')) {
    OrderMarkedExported(:final session) => session,
    final other => fail('export mark failed: $other'),
  };
}

UnitsRemoved mustRemove(FulfilmentSession session) {
  return switch (session.removeUnits(
    orderId: 'ORD-1',
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
    quantity: 1,
  )) {
    UnitsRemoved() && final removed => removed,
    final other => fail('remove failed: $other'),
  };
}

List<String> stamps(FulfilmentSession session) {
  return session.slotExciseStamps(
    orderId: 'ORD-1',
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
  );
}

int slotQuantity(FulfilmentSession session) {
  return session.slotReservedQuantity(
    orderId: 'ORD-1',
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
  );
}

int available(FulfilmentSession session) {
  return session.availableQuantity(
    productId: '100',
    address: 'A-01',
    serialNumber: 'SN-1',
  );
}

RetailDataset catalogue({
  List<DatasetStock>? stocks,
  required List<DatasetGood> goods,
}) {
  return RetailDataset(
    storeName: 'Магазин',
    dbName: 'Store_01-A',
    dateCreate: DateTime(2026, 10, 3, 11, 46, 18),
    stocks: stocks ?? [slot()],
    orders: [order(goods: goods)],
  );
}

FulfilmentSession catalogueOf({
  required List<DatasetStock> stocks,
  required List<DatasetOrder> orders,
}) {
  return mustOpen(
    RetailDataset(
      storeName: 'Магазин',
      dbName: 'Store_01-A',
      dateCreate: DateTime(2026, 10, 3, 11, 46, 18),
      stocks: stocks,
      orders: orders,
    ),
  );
}

DatasetOrder order({
  String orderId = 'ORD-1',
  String orderNumber = '1',
  required List<DatasetGood> goods,
}) {
  return DatasetOrder(
    orderId: orderId,
    invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
    invoiceNumber: 'INV',
    orderNumber: ExactInteger(orderNumber),
    customer: 'Клієнт',
    customerPhone: '0501112233',
    totalMinorUnits: 1000,
    goods: goods,
  );
}

DatasetGood line({
  int quantity = 1,
  bool alko = true,
  String productId = '100',
  String product = 'Алкоголь',
}) {
  return DatasetGood(
    product: product,
    productId: ExactInteger(productId),
    quantity: quantity,
    priceMinorUnits: 1000,
    amountMinorUnits: 1000,
    isServiceGood: false,
    isParcel: false,
    isAlko: alko,
  );
}

DatasetStock slot({
  String serialNumber = 'SN-1',
  int quantity = 5,
  String productId = '100',
}) {
  return DatasetStock(
    address: 'A-01',
    productId: ExactInteger(productId),
    serialNumber: serialNumber,
    quantity: quantity,
  );
}

SessionSnapshot snap(List<SnapshotReservation> reservations) {
  return SessionSnapshot(
    schemaVersion: 1,
    datasetFingerprint: _fingerprint,
    reservations: reservations,
    issuedOrderIds: const [],
    exportedOrderIds: const [],
  );
}

RestoreSessionResult restoreOf(
  RetailDataset dataset,
  SessionSnapshot snapshot,
) {
  return FulfilmentSession.restore(
    dataset: dataset,
    snapshot: snapshot,
    expectedFingerprint: _fingerprint,
  );
}

FulfilmentSession mustRestore(RetailDataset dataset, SessionSnapshot snapshot) {
  return switch (restoreOf(dataset, snapshot)) {
    SessionRestored(:final session) => session,
    final rejected => fail('restore rejected: $rejected'),
  };
}

SessionRestoreReason reason(RestoreSessionResult result) {
  return switch (result) {
    SessionRestoreRejected(failure: SessionRestoreViolation(:final reason)) =>
      reason,
    final other => fail('expected a snapshot violation: $other'),
  };
}
