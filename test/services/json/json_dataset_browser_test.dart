@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/dataset_parse_exception.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/services/json/json_dataset_parser.dart';

/// Proves the parser on Chrome, where `JSON.parse` rounds integers past
/// 2^53 and a 19-digit value cannot survive as a JavaScript number.
void main() {
  const overInt64 = '9999999999999999999';
  const productId = '1290564103789190763';
  const orderNumber = '9007199254740993';

  test('large numeric identifiers keep their exact digits', () {
    final source =
        '''
{
  "storeName": "Магазин Тест",
  "dbName": "Store_01-A",
  "dateCreate": "20261003114618",
  "stocks": [{
    "Address": "A-01",
    "ProductID": $overInt64,
    "SerialNumber": "SN-0001",
    "Quantity": 1
  }],
  "orders": [{
    "OrderID": "ORD-1",
    "InvoiceDate": "20261003114618",
    "InvoiceNumber": "ТЕСТ000001",
    "OrderNumber": $orderNumber,
    "Customer": "Тестовий Клієнт А",
    "CustomerPhone": "0501112233",
    "Goods": [{
      "Product": "Тестовий товар 1",
      "ProductID": $productId,
      "Quantity": 1,
      "Price": 324.50,
      "Amount": 324.50,
      "isServiceGood": 0,
      "isParcel": 0
    }]
  }]
}
''';

    final dataset = const JsonDatasetParser().parse(source);

    expect(dataset.stocks.single.productId.literal, overInt64);
    expect(dataset.stocks.single.productId.literal, hasLength(19));
    expect(dataset.orders.single.orderNumber.literal, orderNumber);
    expect(dataset.orders.single.goods.single.productId.literal, productId);
    expect(dataset.orders.single.goods.single.productId.literal, hasLength(19));

    expect(_jsJsonNumber(overInt64), isNot(overInt64));
    expect(_jsJsonNumber(productId), isNot(productId));
    expect(_jsJsonNumber(orderNumber), '9007199254740992');
    expect(dataset.orders.single.totalMinorUnits, 32450);
  });

  test('an order total at the safe integer limit stays exact', () {
    const remainder = '71992547410.81';
    final goods = <String>[
      for (var i = 0; i < 90; i++)
        '{"Product":"T${i + 1}","ProductID":${i + 1},'
            '"Quantity":1,"Price":0,"Amount":999999999999.99,'
            '"isServiceGood":0,"isParcel":0}',
      '{"Product":"Rest","ProductID":91,"Quantity":1,"Price":0,'
          '"Amount":$remainder,"isServiceGood":0,"isParcel":0}',
    ];
    final source = _chromeDataset(goods.join(','));
    final dataset = const JsonDatasetParser().parse(source);

    expect(
      dataset.orders.single.totalMinorUnits,
      DatasetLimits.maxSafeMinorUnits,
    );
    expect(
      _jsAdd(DatasetLimits.maxSafeMinorUnits, 2),
      isNot('9007199254740993'),
    );

    final over = source.replaceFirst(remainder, '71992547410.82');
    expect(
      () => const JsonDatasetParser().parse(over),
      throwsA(
        isA<DatasetValidationException>().having(
          (error) => error.message,
          'message',
          contains('${DatasetLimits.maxSafeMinorUnits}'),
        ),
      ),
    );
  });
}

String _chromeDataset(String goods) =>
    '''
{
  "storeName": "Магазин Тест",
  "dbName": "Store_01-A",
  "dateCreate": "20261003114618",
  "stocks": [{
    "Address": "A-01",
    "ProductID": 1,
    "SerialNumber": "SN-0001",
    "Quantity": 1
  }],
  "orders": [{
    "OrderID": "ORD-1",
    "InvoiceDate": "20261003114618",
    "InvoiceNumber": "ТЕСТ000001",
    "OrderNumber": 1,
    "Customer": "Тестовий Клієнт А",
    "CustomerPhone": "0501112233",
    "Goods": [$goods]
  }]
}
''';

String _jsAdd(int left, int right) => globalContext
    .callMethod<JSString>('eval'.toJS, 'String($left + $right)'.toJS)
    .toDart;

String _jsJsonNumber(String literal) => globalContext
    .callMethod<JSString>(
      'eval'.toJS,
      "String(JSON.parse('[$literal]')[0])".toJS,
    )
    .toDart;
