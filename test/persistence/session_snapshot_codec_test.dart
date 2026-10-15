import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/persistence/session_snapshot_codec.dart';

const fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const bigProductId = '1290564103789190763';

void main() {
  const codec = SessionSnapshotCodec();

  group('round trip', () {
    test('writes one deterministic document and reads it back', () {
      final snapshot = SessionSnapshot(
        schemaVersion: SessionSnapshot.supportedSchemaVersion,
        datasetFingerprint: fingerprint,
        reservations: const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: bigProductId,
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 2,
          ),
        ],
        issuedOrderIds: const ['ORD-1'],
        exportedOrderIds: const [],
      );

      expect(codec.encode(snapshot), codec.encode(snapshot));
      expect(codec.encode(snapshot), _golden);
      expect(decoded(codec.decode(_golden)), snapshot);
      expect(_golden, contains('"productId": "$bigProductId"'));
      expect(_golden, isNot(contains('"productId": $bigProductId')));
    });

    test('preserves a 19-digit product id through restore', () {
      final snapshot = SessionSnapshot(
        schemaVersion: 1,
        datasetFingerprint: fingerprint,
        reservations: const [
          SnapshotReservation(
            orderId: 'ORD-1',
            productId: bigProductId,
            address: 'A-01',
            serialNumber: 'SN-1',
            quantity: 2,
          ),
        ],
        issuedOrderIds: const [],
        exportedOrderIds: const [],
      );
      final encoded = codec.encode(snapshot);
      final restoredSnapshot = decoded(codec.decode(encoded));
      final dataset = RetailDataset(
        storeName: 'Магазин',
        dbName: 'Store_01-A',
        dateCreate: DateTime(2026, 10, 3, 11, 46, 18),
        stocks: [
          DatasetStock(
            address: 'A-01',
            productId: ExactInteger(bigProductId),
            serialNumber: 'SN-1',
            quantity: 4,
          ),
        ],
        orders: [
          DatasetOrder(
            orderId: 'ORD-1',
            invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
            invoiceNumber: 'INV',
            orderNumber: const ExactInteger('1'),
            customer: 'Клієнт',
            customerPhone: '0501112233',
            totalMinorUnits: 100,
            goods: const [
              DatasetGood(
                product: 'Товар',
                productId: ExactInteger(bigProductId),
                quantity: 3,
                priceMinorUnits: 100,
                amountMinorUnits: 100,
                isServiceGood: false,
                isParcel: false,
              ),
            ],
          ),
        ],
      );

      final session = switch (FulfilmentSession.restore(
        dataset: dataset,
        snapshot: restoredSnapshot,
        expectedFingerprint: fingerprint,
      )) {
        SessionRestored(:final session) => session,
        final rejected => fail('restore rejected: $rejected'),
      };

      expect(restoredSnapshot.reservations.single.productId, bigProductId);
      expect(restoredSnapshot.reservations.single.productId, hasLength(19));
      expect(
        session.lineReservedQuantity(orderId: 'ORD-1', productId: bigProductId),
        2,
      );
      expect(
        session.availableQuantity(
          productId: bigProductId,
          address: 'A-01',
          serialNumber: 'SN-1',
        ),
        2,
      );
      expect(session.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    test('escapes strings and keeps an empty overlay stable', () {
      final snapshot = SessionSnapshot(
        schemaVersion: 1,
        datasetFingerprint: fingerprint,
        reservations: const [
          SnapshotReservation(
            orderId: 'ORD-\n1',
            productId: '100',
            address: 'A "01"',
            serialNumber: r'SN-\1',
            quantity: 1,
          ),
        ],
        issuedOrderIds: const [],
        exportedOrderIds: const [],
      );

      expect(decoded(codec.decode(codec.encode(snapshot))), snapshot);
    });

    test('accepts fields in any order and writes them in schema order', () {
      final source =
          '''
{
  "exportedOrderIds": [],
  "issuedOrderIds": ["ORD-2", "ORD-1"],
  "reservations": [],
  "datasetFingerprint": "$fingerprint",
  "schemaVersion": 1
}
''';
      final snapshot = decoded(codec.decode(source));

      expect(snapshot.issuedOrderIds, ['ORD-2', 'ORD-1']);
      expect(codec.encode(snapshot), startsWith('{\n  "schemaVersion": 1,\n'));
      expect(codec.encode(snapshot), endsWith('\n}'));
    });

    test('keeps duplicate reservation entries for later validation', () {
      final source = codec.encode(
        SessionSnapshot(
          schemaVersion: 1,
          datasetFingerprint: fingerprint,
          reservations: const [
            SnapshotReservation(
              orderId: 'ORD-1',
              productId: '100',
              address: 'A-01',
              serialNumber: 'SN-1',
              quantity: 1,
            ),
            SnapshotReservation(
              orderId: 'ORD-1',
              productId: '100',
              address: 'A-01',
              serialNumber: 'SN-1',
              quantity: 1,
            ),
          ],
          issuedOrderIds: const [],
          exportedOrderIds: const [],
        ),
      );

      expect(decoded(codec.decode(source)).reservations, hasLength(2));
    });
  });

  group('rejected json', () {
    test('accepts the maximum canonical quantity', () {
      final source = _reservation(quantity: '${DatasetLimits.maxQuantity}');
      expect(
        decoded(codec.decode(source)).reservations.single.quantity,
        DatasetLimits.maxQuantity,
      );
    });

    test('rejects malformed json', () {
      expect(reason(codec.decode('{')), SnapshotDecodeReason.malformedJson);
      expect(
        reason(codec.decode('{"schemaVersion": 1,}')),
        SnapshotDecodeReason.malformedJson,
      );
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '01'))),
        SnapshotDecodeReason.malformedJson,
      );
      expect(
        reason(
          codec.decode(
            '{"schemaVersion": 1, "schemaVersion": 1, '
            '"datasetFingerprint": "$fingerprint", "reservations": [], '
            '"issuedOrderIds": [], "exportedOrderIds": []}',
          ),
        ),
        SnapshotDecodeReason.malformedJson,
      );
    });

    test('rejects a non-object root and wrong value types', () {
      expect(
        reason(codec.decode('null')),
        SnapshotDecodeReason.malformedStructure,
      );
      expect(
        reason(codec.decode('[]')),
        SnapshotDecodeReason.malformedStructure,
      );
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '"1"'))),
        SnapshotDecodeReason.malformedStructure,
      );
      expect(
        reason(codec.decode(snapshotJson(issuedOrderIds: '[1]'))),
        SnapshotDecodeReason.malformedStructure,
      );
      expect(
        reason(
          codec.decode(
            _reservation(productId: bigProductId, quotedProduct: false),
          ),
        ),
        SnapshotDecodeReason.malformedStructure,
      );
    });

    test('rejects unknown and missing fields', () {
      expect(
        reason(codec.decode(snapshotJson(extraLines: const ['"note": true']))),
        SnapshotDecodeReason.unknownField,
      );
      expect(
        reason(codec.decode(snapshotJson(includeReservations: false))),
        SnapshotDecodeReason.missingField,
      );
      expect(
        reason(codec.decode(_reservation(extra: '"bin": "A"'))),
        SnapshotDecodeReason.unknownField,
      );
    });

    test('rejects non-canonical numbers and out-of-range quantities', () {
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '1.0'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '1e0'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(_reservation(quantity: '0'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(_reservation(quantity: '-1'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(_reservation(quantity: '1e2'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(_reservation(quantity: '1000000000'))),
        SnapshotDecodeReason.invalidNumber,
      );
      expect(
        reason(codec.decode(_reservation(quantity: bigProductId))),
        SnapshotDecodeReason.invalidNumber,
      );
    });

    test('rejects an unsupported canonical schema version', () {
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '2'))),
        SnapshotDecodeReason.unsupportedVersion,
      );
      expect(
        reason(codec.decode(snapshotJson(schemaVersion: '0'))),
        SnapshotDecodeReason.unsupportedVersion,
      );
      expect(
        reason(
          codec.decode(snapshotJson(schemaVersion: '9999999999999999999')),
        ),
        SnapshotDecodeReason.unsupportedVersion,
      );
    });

    test('rejects a fingerprint that is not lowercase hex', () {
      expect(
        reason(
          codec.decode(
            snapshotJson(datasetFingerprint: '"${fingerprint.toUpperCase()}"'),
          ),
        ),
        SnapshotDecodeReason.invalidFingerprint,
      );
      expect(
        reason(codec.decode(snapshotJson(datasetFingerprint: '"abc"'))),
        SnapshotDecodeReason.invalidFingerprint,
      );
      expect(
        reason(codec.decode(snapshotJson(datasetFingerprint: '1'))),
        SnapshotDecodeReason.malformedStructure,
      );
    });
  });
}

SessionSnapshot decoded(SnapshotDecodeResult result) {
  return switch (result) {
    SnapshotDecoded(:final snapshot) => snapshot,
    SnapshotDecodeRejected(:final reason, :final detail) => fail(
      'decode rejected: $reason $detail',
    ),
  };
}

SnapshotDecodeReason reason(SnapshotDecodeResult result) {
  return switch (result) {
    SnapshotDecodeRejected(:final reason) => reason,
    SnapshotDecoded() => fail('decode succeeded'),
  };
}

String snapshotJson({
  String schemaVersion = '1',
  String datasetFingerprint = '"$fingerprint"',
  String reservations = '[]',
  String issuedOrderIds = '[]',
  String exportedOrderIds = '[]',
  bool includeReservations = true,
  List<String> extraLines = const [],
}) {
  final lines = <String>[
    '  "schemaVersion": $schemaVersion',
    '  "datasetFingerprint": $datasetFingerprint',
    if (includeReservations) '  "reservations": $reservations',
    '  "issuedOrderIds": $issuedOrderIds',
    '  "exportedOrderIds": $exportedOrderIds',
    for (final line in extraLines) '  $line',
  ];
  return '{\n${lines.join(',\n')}\n}';
}

String _reservation({
  String productId = '100',
  bool quotedProduct = true,
  String quantity = '1',
  String extra = '',
}) {
  final product = quotedProduct ? '"$productId"' : productId;
  final extraField = extra.isEmpty ? '' : ',\n      $extra';
  return '''
{
  "schemaVersion": 1,
  "datasetFingerprint": "$fingerprint",
  "reservations": [
    {
      "orderId": "ORD-1",
      "productId": $product,
      "address": "A-01",
      "serialNumber": "SN-1",
      "quantity": $quantity$extraField
    }
  ],
  "issuedOrderIds": [],
  "exportedOrderIds": []
}
''';
}

const _golden =
    '''{
  "schemaVersion": 1,
  "datasetFingerprint": "$fingerprint",
  "reservations": [
    {
      "orderId": "ORD-1",
      "productId": "$bigProductId",
      "address": "A-01",
      "serialNumber": "SN-1",
      "quantity": 2
    }
  ],
  "issuedOrderIds": [
    "ORD-1"
  ],
  "exportedOrderIds": []
}''';
