import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';

/// Synthetic catalogue only. No real customers, phones, or products.
final _created = DateTime(2026, 10, 3, 11, 46, 18);

const fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const otherFingerprint =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

const bigProductId = '1290564103789190763';

void main() {
  group('empty snapshot', () {
    test('restores an empty overlay for a valid dataset', () {
      final dataset = data(
        stocks: [slot(quantity: 5)],
        orders: [
          order(goods: [good(quantity: 2)]),
        ],
      );
      final session = mustRestore(dataset, snap());

      expect(session.dataset, same(dataset));
      expect(session.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(available(session), 5);
      expect(lineReserved(session), 0);
      expect(session.capture(datasetFingerprint: fingerprint), snap());
    });

    test('a service-only order with no reservation is ready', () {
      final dataset = data(
        stocks: [slot()],
        orders: [
          order(goods: [good(service: true)]),
        ],
      );
      final session = mustRestore(dataset, snap());

      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(available(session), 5);
    });

    test('copies reservation and id lists', () {
      final reservations = [entry()];
      final issued = ['ORD-1'];
      final exported = ['ORD-1'];
      final snapshot = snap(
        reservations: reservations,
        issuedOrderIds: issued,
        exportedOrderIds: exported,
      );
      reservations.clear();
      issued.clear();
      exported.clear();

      expect(snapshot.reservations, hasLength(1));
      expect(snapshot.issuedOrderIds, ['ORD-1']);
      expect(snapshot.exportedOrderIds, ['ORD-1']);
    });
  });

  group('valid reservations', () {
    test('restores a partial reservation exactly', () {
      final dataset = data(
        stocks: [slot(quantity: 5)],
        orders: [
          order(goods: [good(quantity: 3)]),
        ],
      );
      final snapshot = snap(reservations: [entry(quantity: 1)]);
      final session = mustRestore(dataset, snapshot);

      expect(lineReserved(session), 1);
      expect(slotReserved(session), 1);
      expect(available(session), 4);
      expect(session.statusOf('ORD-1'), OrderStatus.inProgress);
      expect(session.capture(datasetFingerprint: fingerprint), snapshot);
    });

    test('restores a fully reserved order as ready', () {
      final dataset = data(
        stocks: [
          slot(serialNumber: 'SN-1', quantity: 4),
          slot(serialNumber: 'SN-2', quantity: 4),
        ],
        orders: [
          order(goods: [good(quantity: 3)]),
        ],
      );
      final snapshot = snap(
        reservations: [
          entry(quantity: 1),
          entry(serialNumber: 'SN-2', quantity: 2),
        ],
      );
      final session = mustRestore(dataset, snapshot);

      expect(lineReserved(session), 3);
      expect(available(session), 3);
      expect(available(session, serialNumber: 'SN-2'), 2);
      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('keeps an address and serial exactly', () {
      final dataset = data(
        stocks: [slot(address: 'A-01 ', serialNumber: 'Sn-1')],
        orders: [
          order(goods: [good()]),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(
          reservations: [entry(address: 'A-01 ', serialNumber: 'Sn-1')],
        ),
      );

      expect(slotReserved(session, address: 'A-01 ', serialNumber: 'Sn-1'), 1);
      expect(available(session, address: 'A-01 ', serialNumber: 'Sn-1'), 4);
      expect(available(session, address: 'A-01', serialNumber: 'Sn-1'), 0);
      expect(slotReserved(session, address: 'A-01 ', serialNumber: 'sn-1'), 0);
    });

    test('restores a 19-digit product id without changing the quantity', () {
      final dataset = data(
        stocks: [slot(productId: bigProductId, quantity: 4)],
        orders: [
          order(goods: [good(productId: bigProductId, quantity: 3)]),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(reservations: [entry(productId: bigProductId, quantity: 2)]),
      );

      expect(lineReserved(session, productId: bigProductId), 2);
      expect(available(session, productId: bigProductId), 2);
      expect(session.statusOf('ORD-1'), OrderStatus.inProgress);
      expect(bigProductId, hasLength(19));
    });

    test('captures slots in dataset order', () {
      final dataset = data(
        stocks: [
          slot(serialNumber: 'SN-1'),
          slot(serialNumber: 'SN-2'),
        ],
        orders: [
          order(goods: [good(quantity: 2)]),
        ],
      );
      final session = mustOpen(dataset);
      final second = mustApply(session, serialNumber: 'SN-2').session;
      final both = mustApply(second, serialNumber: 'SN-1').session;

      expect(
        both
            .capture(datasetFingerprint: fingerprint)
            .reservations
            .map((entry) => entry.serialNumber)
            .toList(),
        ['SN-1', 'SN-2'],
      );
    });
  });

  group('issued and exported', () {
    test('restores an issued order and keeps its reservation', () {
      final dataset = readyDataset();
      final session = mustRestore(
        dataset,
        snap(
          reservations: [entry(quantity: 2)],
          issuedOrderIds: const ['ORD-1'],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(lineReserved(session), 2);
      expect(available(session), 3);
    });

    test('restores an exported order and keeps its reservation', () {
      final dataset = readyDataset();
      final session = mustRestore(
        dataset,
        snap(
          reservations: [entry(quantity: 2)],
          issuedOrderIds: const ['ORD-1'],
          exportedOrderIds: const ['ORD-1'],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.exported);
      expect(slotReserved(session), 2);
      expect(available(session), 3);
    });

    test('issues and exports a service-only order', () {
      final dataset = data(
        stocks: [slot()],
        orders: [
          order(goods: [good(service: true)]),
        ],
      );
      final issued = mustRestore(
        dataset,
        snap(issuedOrderIds: const ['ORD-1']),
      );
      final exported = mustRestore(
        dataset,
        snap(
          issuedOrderIds: const ['ORD-1'],
          exportedOrderIds: const ['ORD-1'],
        ),
      );

      expect(issued.statusOf('ORD-1'), OrderStatus.issued);
      expect(exported.statusOf('ORD-1'), OrderStatus.exported);
      expect(available(exported), 5);
    });

    test('issues a mixed order when the stock line is complete', () {
      final dataset = data(
        stocks: [slot(quantity: 2)],
        orders: [
          order(
            goods: [
              good(quantity: 2),
              good(product: 'Доставка', productId: '200', service: true),
            ],
          ),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(
          reservations: [entry(quantity: 2)],
          issuedOrderIds: const ['ORD-1'],
        ),
      );

      expect(session.statusOf('ORD-1'), OrderStatus.issued);
      expect(lineReserved(session, productId: '200'), 0);
    });

    test('captures issued and exported ids in dataset order', () {
      final dataset = data(
        stocks: [slot(quantity: 2)],
        orders: [
          order(goods: [good(service: true)]),
          order(
            orderId: 'ORD-2',
            orderNumber: '2',
            goods: [good(service: true)],
          ),
        ],
      );
      final opened = mustOpen(dataset);
      final first = mustIssue(opened, 'ORD-2');
      final issued = mustIssue(first, 'ORD-1');
      final exported = mustExport(issued, 'ORD-2');
      final snapshot = exported.capture(datasetFingerprint: fingerprint);

      expect(snapshot.issuedOrderIds, ['ORD-1', 'ORD-2']);
      expect(snapshot.exportedOrderIds, ['ORD-2']);
    });

    test('capture after restore uses dataset id order', () {
      final dataset = data(
        stocks: [slot(quantity: 2)],
        orders: [
          order(goods: [good(service: true)]),
          order(
            orderId: 'ORD-2',
            orderNumber: '2',
            goods: [good(service: true)],
          ),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(issuedOrderIds: const ['ORD-2', 'ORD-1']),
      );

      expect(session.capture(datasetFingerprint: fingerprint).issuedOrderIds, [
        'ORD-1',
        'ORD-2',
      ]);
    });

    test('a later reserve on a restored session still caps', () {
      final dataset = data(
        stocks: [slot(quantity: 5)],
        orders: [
          order(goods: [good(quantity: 3)]),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(reservations: [entry(quantity: 1)]),
      );
      final applied = mustApply(session, quantity: 10);

      expect(applied.requestedQuantity, 10);
      expect(applied.appliedQuantity, 2);
      expect(lineReserved(applied.session), 3);
      expect(available(applied.session), 2);
    });
  });

  group('parcel reservations', () {
    test('restores a parcel reserved on its TTN', () {
      final dataset = data(
        stocks: [
          slot(serialNumber: 'TTN-1', quantity: 2),
          slot(serialNumber: 'OTHER', quantity: 2),
        ],
        orders: [
          order(goods: [good(quantity: 1, parcelTtn: 'TTN-1')]),
        ],
      );
      final session = mustRestore(
        dataset,
        snap(reservations: [entry(serialNumber: 'TTN-1')]),
      );

      expect(slotReserved(session, serialNumber: 'TTN-1'), 1);
      expect(available(session, serialNumber: 'OTHER'), 2);
      expect(session.statusOf('ORD-1'), OrderStatus.readyForIssue);
    });

    test('rejects a parcel serial that is not the TTN', () {
      final dataset = data(
        stocks: [
          slot(serialNumber: 'TTN-1'),
          slot(serialNumber: 'OTHER'),
        ],
        orders: [
          order(goods: [good(parcelTtn: 'TTN-1')]),
        ],
      );

      expect(
        rejection(
          restoreOf(
            dataset,
            snap(reservations: [entry(serialNumber: 'OTHER')]),
          ),
        ),
        SessionRestoreReason.parcelMismatch,
      );
    });

    test('rejects an unknown address even when the TTN matches', () {
      final dataset = data(
        stocks: [slot(serialNumber: 'TTN-1')],
        orders: [
          order(goods: [good(parcelTtn: 'TTN-1')]),
        ],
      );

      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: [entry(address: 'MISSING', serialNumber: 'TTN-1')],
            ),
          ),
        ),
        SessionRestoreReason.unknownStock,
      );
    });
  });

  group('rejected snapshots', () {
    test('rejects an unsupported schema version before the fingerprint', () {
      expect(
        rejection(
          restoreOf(
            readyDataset(),
            snap(schemaVersion: 2, datasetFingerprint: 'not-a-hash'),
            expected: 'also-bad',
          ),
        ),
        SessionRestoreReason.unsupportedVersion,
      );
    });

    test('rejects a fingerprint that is not lowercase hex', () {
      final upper = fingerprint.toUpperCase();
      expect(
        rejection(
          restoreOf(
            readyDataset(),
            snap(datasetFingerprint: upper),
            expected: upper,
          ),
        ),
        SessionRestoreReason.invalidFingerprint,
      );
      expect(
        rejection(restoreOf(readyDataset(), snap(), expected: 'abc')),
        SessionRestoreReason.invalidFingerprint,
      );
    });

    test('rejects a dataset fingerprint mismatch', () {
      expect(
        rejection(
          restoreOf(readyDataset(), snap(), expected: otherFingerprint),
        ),
        SessionRestoreReason.fingerprintMismatch,
      );
    });

    test('rejects a dataset that cannot open', () {
      final result = restoreOf(
        data(
          stocks: [slot(quantity: 2), slot(quantity: 9)],
          orders: [
            order(goods: [good()]),
          ],
        ),
        snap(),
      );

      expect(switch (result) {
        SessionRestoreRejected(
          failure: RestoreDatasetRejected(:final problem),
        ) =>
          problem.reason,
        _ => fail('duplicate stock restored: $result'),
      }, DatasetProblemReason.duplicateStock);
    });

    test('rejects unknown orders, lines, and stock slots', () {
      final dataset = readyDataset();
      expect(
        rejection(
          restoreOf(dataset, snap(reservations: [entry(orderId: 'MISSING')])),
        ),
        SessionRestoreReason.unknownOrder,
      );
      expect(
        rejection(
          restoreOf(dataset, snap(reservations: [entry(productId: '999')])),
        ),
        SessionRestoreReason.unknownLine,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(reservations: [entry(serialNumber: 'MISSING')]),
          ),
        ),
        SessionRestoreReason.unknownStock,
      );
    });

    test('rejects a duplicate reservation without merging it', () {
      expect(
        rejection(
          restoreOf(
            data(
              stocks: [slot(quantity: 5)],
              orders: [
                order(goods: [good(quantity: 5)]),
              ],
            ),
            snap(reservations: [entry(quantity: 1), entry(quantity: 1)]),
          ),
        ),
        SessionRestoreReason.duplicateReservation,
      );
    });

    test('rejects quantities that are not positive and in range', () {
      final dataset = readyDataset();
      for (final quantity in [0, -1, DatasetLimits.maxQuantity + 1]) {
        expect(
          rejection(
            restoreOf(dataset, snap(reservations: [entry(quantity: quantity)])),
          ),
          SessionRestoreReason.invalidQuantity,
          reason: 'quantity $quantity',
        );
      }
    });

    test('rejects a line quantity above the order instead of capping it', () {
      expect(
        rejection(
          restoreOf(
            data(
              stocks: [slot(quantity: 10)],
              orders: [
                order(goods: [good(quantity: 2)]),
              ],
            ),
            snap(reservations: [entry(quantity: 3)]),
          ),
        ),
        SessionRestoreReason.lineOverReserved,
      );
    });

    test('rejects two slots that together exceed the line', () {
      expect(
        rejection(
          restoreOf(
            data(
              stocks: [
                slot(serialNumber: 'SN-1', quantity: 5),
                slot(serialNumber: 'SN-2', quantity: 5),
              ],
              orders: [
                order(goods: [good(quantity: 3)]),
              ],
            ),
            snap(
              reservations: [
                entry(quantity: 2),
                entry(serialNumber: 'SN-2', quantity: 2),
              ],
            ),
          ),
        ),
        SessionRestoreReason.lineOverReserved,
      );
    });

    test('rejects reservations that together exceed the stock slot', () {
      final dataset = data(
        stocks: [slot(quantity: 5)],
        orders: [
          order(goods: [good(quantity: 4)]),
          order(orderId: 'ORD-2', orderNumber: '2', goods: [good(quantity: 4)]),
        ],
      );

      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: [
                entry(quantity: 3),
                entry(orderId: 'ORD-2', quantity: 3),
              ],
            ),
          ),
        ),
        SessionRestoreReason.stockOverReserved,
      );
    });

    test('rejects a reservation on a service line', () {
      expect(
        rejection(
          restoreOf(
            data(
              stocks: [slot()],
              orders: [
                order(goods: [good(service: true)]),
              ],
            ),
            snap(reservations: [entry()]),
          ),
        ),
        SessionRestoreReason.serviceReservation,
      );
    });

    test('rejects duplicate, unknown, and unready issued ids', () {
      final dataset = readyDataset();
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: [entry(quantity: 2)],
              issuedOrderIds: const ['ORD-1', 'ORD-1'],
            ),
          ),
        ),
        SessionRestoreReason.duplicateIssued,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: [entry(quantity: 2)],
              issuedOrderIds: const ['MISSING'],
            ),
          ),
        ),
        SessionRestoreReason.unknownIssued,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: [entry(quantity: 1)],
              issuedOrderIds: const ['ORD-1'],
            ),
          ),
        ),
        SessionRestoreReason.issuedNotReady,
      );
    });

    test('rejects duplicate, unknown, and unissued exported ids', () {
      final dataset = readyDataset();
      final reserved = snap(reservations: [entry(quantity: 2)]);
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: reserved.reservations,
              issuedOrderIds: const ['ORD-1', 'ORD-1'],
              exportedOrderIds: const ['ORD-1', 'ORD-1'],
            ),
          ),
        ),
        SessionRestoreReason.duplicateIssued,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: reserved.reservations,
              issuedOrderIds: const ['ORD-1'],
              exportedOrderIds: const ['ORD-1', 'ORD-1'],
            ),
          ),
        ),
        SessionRestoreReason.duplicateExported,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: reserved.reservations,
              issuedOrderIds: const ['ORD-1'],
              exportedOrderIds: const ['MISSING'],
            ),
          ),
        ),
        SessionRestoreReason.unknownExported,
      );
      expect(
        rejection(
          restoreOf(
            dataset,
            snap(
              reservations: reserved.reservations,
              exportedOrderIds: const ['ORD-1'],
            ),
          ),
        ),
        SessionRestoreReason.exportedNotIssued,
      );
    });
  });

  group('capture round trip', () {
    test('restore matches a session built by the live operations', () {
      final dataset = data(
        stocks: [slot(quantity: 4)],
        orders: [
          order(goods: [good(quantity: 2)]),
          order(orderId: 'ORD-2', orderNumber: '2', goods: [good(quantity: 2)]),
        ],
      );
      final opened = mustOpen(dataset);
      final reserved = mustApply(opened, quantity: 2).session;
      final second = mustApply(reserved, orderId: 'ORD-2', quantity: 1).session;
      final issued = mustIssue(second, 'ORD-1');
      final exported = mustExport(issued, 'ORD-1');
      final snapshot = exported.capture(datasetFingerprint: fingerprint);
      final restored = mustRestore(dataset, snapshot);

      expect(restored.capture(datasetFingerprint: fingerprint), snapshot);
      expect(restored.statusOf('ORD-1'), OrderStatus.exported);
      expect(restored.statusOf('ORD-2'), OrderStatus.inProgress);
      expect(lineReserved(restored), 2);
      expect(lineReserved(restored, orderId: 'ORD-2'), 1);
      expect(available(restored), 1);
    });
  });
}

const _fingerprintLength = 64;

RetailDataset readyDataset() {
  return data(
    stocks: [slot(quantity: 5)],
    orders: [
      order(goods: [good(quantity: 2)]),
    ],
  );
}

SessionSnapshot snap({
  int schemaVersion = SessionSnapshot.supportedSchemaVersion,
  String datasetFingerprint = fingerprint,
  List<SnapshotReservation> reservations = const [],
  List<String> issuedOrderIds = const [],
  List<String> exportedOrderIds = const [],
}) {
  return SessionSnapshot(
    schemaVersion: schemaVersion,
    datasetFingerprint: datasetFingerprint,
    reservations: reservations,
    issuedOrderIds: issuedOrderIds,
    exportedOrderIds: exportedOrderIds,
  );
}

SnapshotReservation entry({
  String orderId = 'ORD-1',
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 1,
}) {
  return SnapshotReservation(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    quantity: quantity,
  );
}

RestoreSessionResult restoreOf(
  RetailDataset dataset,
  SessionSnapshot snapshot, {
  String? expected,
}) {
  return FulfilmentSession.restore(
    dataset: dataset,
    snapshot: snapshot,
    expectedFingerprint: expected ?? fingerprint,
  );
}

FulfilmentSession mustRestore(RetailDataset dataset, SessionSnapshot snapshot) {
  expect(fingerprint, hasLength(_fingerprintLength));
  return switch (restoreOf(dataset, snapshot)) {
    SessionRestored(:final session) => session,
    final rejected => fail('restore rejected: $rejected'),
  };
}

SessionRestoreReason rejection(RestoreSessionResult result) {
  return switch (result) {
    SessionRestoreRejected(failure: SessionRestoreViolation(:final reason)) =>
      reason,
    final other => fail('expected a snapshot violation: $other'),
  };
}

DatasetGood good({
  String product = 'Товар',
  String productId = '100',
  int quantity = 1,
  bool service = false,
  String? parcelTtn,
}) {
  return DatasetGood(
    product: product,
    productId: ExactInteger(productId),
    quantity: quantity,
    priceMinorUnits: 100,
    amountMinorUnits: 100,
    isServiceGood: service,
    isParcel: parcelTtn != null,
    parcelTtn: parcelTtn,
  );
}

DatasetStock slot({
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 5,
}) {
  return DatasetStock(
    address: address,
    productId: ExactInteger(productId),
    serialNumber: serialNumber,
    quantity: quantity,
  );
}

DatasetOrder order({
  String orderId = 'ORD-1',
  String orderNumber = '1',
  List<DatasetGood>? goods,
}) {
  final lines = goods ?? [good()];
  return DatasetOrder(
    orderId: orderId,
    invoiceDate: _created,
    invoiceNumber: 'INV',
    orderNumber: ExactInteger(orderNumber),
    customer: 'Клієнт',
    customerPhone: '0501112233',
    totalMinorUnits: 100 * lines.length,
    goods: lines,
  );
}

RetailDataset data({
  String storeName = 'Магазин',
  String dbName = 'Store_01-A',
  required List<DatasetStock> stocks,
  required List<DatasetOrder> orders,
}) {
  return RetailDataset(
    storeName: storeName,
    dbName: dbName,
    dateCreate: _created,
    stocks: stocks,
    orders: orders,
  );
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
  String address = 'A-01',
  String serialNumber = 'SN-1',
  int quantity = 1,
}) {
  return switch (session.reserve(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    quantity: quantity,
  )) {
    ReserveApplied() && final applied => applied,
    final other => fail('reserve failed: $other'),
  };
}

FulfilmentSession mustIssue(FulfilmentSession session, String orderId) {
  return switch (session.issueOrder(orderId)) {
    OrderIssued(:final session) => session,
    final other => fail('issue failed: $other'),
  };
}

FulfilmentSession mustExport(FulfilmentSession session, String orderId) {
  return switch (session.markExported(orderId)) {
    OrderMarkedExported(:final session) => session,
    final other => fail('export failed: $other'),
  };
}

int available(
  FulfilmentSession session, {
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
}) {
  return session.availableQuantity(
    productId: productId,
    address: address,
    serialNumber: serialNumber,
  );
}

int lineReserved(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
}) {
  return session.lineReservedQuantity(orderId: orderId, productId: productId);
}

int slotReserved(
  FulfilmentSession session, {
  String orderId = 'ORD-1',
  String productId = '100',
  String address = 'A-01',
  String serialNumber = 'SN-1',
}) {
  return session.slotReservedQuantity(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
  );
}
