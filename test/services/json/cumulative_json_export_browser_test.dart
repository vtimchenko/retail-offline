@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';
import 'package:retail_offline/services/json/precision_json_decoder.dart';

/// Proves cumulative export on Chrome, where `JSON.parse` rounds integers
/// past 2^53. The export text is checked as digits, not as a JavaScript
/// number.
void main() {
  const productId = '1292834549023548345';
  const orderNumber = '9007199254740993';
  const stamp = '20261014150722';
  const orderId = 'ORD-1';
  const importedStamp = '20261003114618';

  test('prepare keeps large identifiers exact in Chrome', () {
    expect(kIsWeb, isTrue);
    final session = _issued(
      orderId: orderId,
      productId: productId,
      orderNumber: orderNumber,
    );
    var reads = 0;

    final result = const CumulativeJsonExport().prepare(
      session,
      now: () {
        reads++;
        return DateTime(2026, 10, 14, 15, 7, 22);
      },
    );

    expect(reads, 1);
    expect(result, isA<CumulativeExportPrepared>());
    final prepared = result as CumulativeExportPrepared;
    final bytes = prepared.document.bytes;
    expect(bytes, isNotEmpty);
    expect(bytes.first, isNot(0xEF));
    final text = utf8.decode(bytes);

    expect(text, _expected);
    expect(text, contains('"OrderNumber": $orderNumber'));
    expect(text, isNot(contains('"OrderNumber": "$orderNumber"')));
    expect(text, contains('"ProductID": $productId'));
    expect(text, isNot(contains('"ProductID": "$productId"')));
    expect(text, isNot(contains(importedStamp)));
    expect(text, contains('ТВ Київ Тест'));
    expect(text, contains('РОЗ234234234'));
    expect(text, isNot(contains('\r')));
    expect(text, endsWith('}'));

    expect(prepared.document.dateCreate, stamp);
    expect(
      prepared.document.filename,
      'export_retail_ki_kiev_test_$stamp.json',
    );
    expect(session.statusOf(orderId), OrderStatus.issued);
    expect(prepared.pendingSession.statusOf(orderId), OrderStatus.exported);
    expect(identical(prepared.pendingSession, session), isFalse);
    expect(
      session.lineReservedQuantity(orderId: orderId, productId: productId),
      1,
    );

    final root = const PrecisionJsonDecoder().decode(text) as JsonObjectValue;
    expect(root.fields.keys.toList(), [
      'storeName',
      'dbName',
      'dateCreate',
      'orders',
    ]);
    expect((root.fields['storeName']! as JsonStringValue).text, 'ТВ Київ Тест');
    expect(
      (root.fields['dbName']! as JsonStringValue).text,
      'retail_ki_kiev_test',
    );
    expect((root.fields['dateCreate']! as JsonStringValue).text, stamp);

    final order =
        (root.fields['orders']! as JsonArrayValue).items.single
            as JsonObjectValue;
    expect(order.fields.keys.toList(), [
      'OrderID',
      'InvoiceNumber',
      'OrderNumber',
      'Goods',
    ]);
    expect((order.fields['OrderID']! as JsonStringValue).text, orderId);
    expect(
      (order.fields['InvoiceNumber']! as JsonStringValue).text,
      'РОЗ234234234',
    );
    final writtenOrder = order.fields['OrderNumber']! as JsonNumberValue;
    expect(writtenOrder.literal, orderNumber);
    expect(writtenOrder.literal, isNot(contains('e')));
    expect(writtenOrder.literal, isNot(contains('E')));

    final line =
        (order.fields['Goods']! as JsonArrayValue).items.single
            as JsonObjectValue;
    expect(line.fields.keys.toList(), [
      'ProductID',
      'Quantity',
      'Address',
      'SerialNumber',
    ]);
    final writtenProduct = line.fields['ProductID']! as JsonNumberValue;
    expect(writtenProduct.literal, productId);
    expect(writtenProduct.literal, isNot(contains('e')));
    expect(writtenProduct.literal, isNot(contains('E')));
    expect((line.fields['Quantity']! as JsonNumberValue).literal, '1');
    expect((line.fields['Address']! as JsonStringValue).text, 'AL.3.1.1.1');
    expect((line.fields['SerialNumber']! as JsonStringValue).text, 'SN-1');

    expect(_jsJsonNumber(orderNumber), '9007199254740992');
    expect(_jsJsonNumber(productId), isNot(productId));
  });
}

const _expected = '''{
  "storeName": "ТВ Київ Тест",
  "dbName": "retail_ki_kiev_test",
  "dateCreate": "20261014150722",
  "orders": [
    {
      "OrderID": "ORD-1",
      "InvoiceNumber": "РОЗ234234234",
      "OrderNumber": 9007199254740993,
      "Goods": [
        {
          "ProductID": 1292834549023548345,
          "Quantity": 1,
          "Address": "AL.3.1.1.1",
          "SerialNumber": "SN-1"
        }
      ]
    }
  ]
}''';

FulfilmentSession _issued({
  required String orderId,
  required String productId,
  required String orderNumber,
}) {
  final opened = switch (FulfilmentSession.open(
    RetailDataset(
      storeName: 'ТВ Київ Тест',
      dbName: 'retail_ki_kiev_test',
      dateCreate: DateTime(2026, 10, 3, 11, 46, 18),
      stocks: [
        DatasetStock(
          address: 'AL.3.1.1.1',
          productId: ExactInteger(productId),
          serialNumber: 'SN-1',
          quantity: 1,
        ),
      ],
      orders: [
        DatasetOrder(
          orderId: orderId,
          invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
          invoiceNumber: 'РОЗ234234234',
          orderNumber: ExactInteger(orderNumber),
          customer: 'Тестовий Клієнт А',
          customerPhone: '0501112233',
          totalMinorUnits: 100,
          goods: [
            DatasetGood(
              product: 'Тестовий товар',
              productId: ExactInteger(productId),
              quantity: 1,
              priceMinorUnits: 100,
              amountMinorUnits: 100,
              isServiceGood: false,
              isParcel: false,
            ),
          ],
        ),
      ],
    ),
  )) {
    DatasetOpened(:final session) => session,
    DatasetRejected(:final problem) => fail('dataset rejected: $problem'),
  };
  final reserved = switch (opened.reserve(
    orderId: orderId,
    productId: productId,
    address: 'AL.3.1.1.1',
    serialNumber: 'SN-1',
    quantity: 1,
  )) {
    ReserveApplied(:final session) => session,
    final other => fail('reserve failed: $other'),
  };
  return switch (reserved.issueOrder(orderId)) {
    OrderIssued(:final session) => session,
    final other => fail('issue failed: $other'),
  };
}

String _jsJsonNumber(String literal) => globalContext
    .callMethod<JSString>(
      'eval'.toJS,
      "String(JSON.parse('[$literal]')[0])".toJS,
    )
    .toDart;
