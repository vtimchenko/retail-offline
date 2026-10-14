import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/dataset_parse_exception.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/services/json/json_dataset_parser.dart';

/// Synthetic data only: no real customers, phones or products.
///
/// [bigProductId] is the same 19-digit sample the Excel tests use. It is
/// outside JavaScript's safe integer range. [overInt64] also exceeds a
/// 64-bit integer.
const bigProductId = '1290564103789190763';
const bigProductId2 = '1289540227082816241';
const overInt64 = '9999999999999999999';
const largeOrderNumber = '9007199254740993';

const _parser = JsonDatasetParser();
const _created = '20261003114618';

String _s(String value) => jsonEncode(value);

String _obj(List<String?> parts) => '{${parts.whereType<String>().join(',')}}';

String? _field(String name, String? raw) => raw == null ? null : '"$name":$raw';

String _stock({
  String? address = 'A-01',
  String? productId = bigProductId,
  bool quoteProductId = false,
  String? serialNumber = 'SN-0001',
  String? quantity = '1',
  String? extra,
}) => _obj([
  _field('Address', address == null ? null : _s(address)),
  _field(
    'ProductID',
    productId == null ? null : (quoteProductId ? _s(productId) : productId),
  ),
  _field('SerialNumber', serialNumber == null ? null : _s(serialNumber)),
  _field('Quantity', quantity),
  ?extra,
]);

String _good({
  String? product = 'Тестовий товар 1',
  String? productId = bigProductId,
  bool quoteProductId = false,
  String? quantity = '1',
  String? price = '324.50',
  String? amount = '324.50',
  String? isServiceGood = '0',
  String? isParcel = '0',
  String? parcelTtnRaw,
  String? meestTtnRaw,
  String? extra,
}) => _obj([
  _field('Product', product == null ? null : _s(product)),
  _field(
    'ProductID',
    productId == null ? null : (quoteProductId ? _s(productId) : productId),
  ),
  _field('Quantity', quantity),
  _field('Price', price),
  _field('Amount', amount),
  _field('isServiceGood', isServiceGood),
  _field('isParcel', isParcel),
  if (parcelTtnRaw != null) _field('ParcelTTN', parcelTtnRaw),
  if (meestTtnRaw != null) _field('MeestTTN', meestTtnRaw),
  ?extra,
]);

String _order({
  String? orderId = 'ORD-1',
  String? invoiceDate = _created,
  bool dateAsNumber = false,
  String? invoiceNumber = 'ТЕСТ000001',
  String? orderNumber = '900000001',
  bool quoteOrderNumber = false,
  String? customer = 'Тестовий Клієнт А',
  String? customerPhone = '0501112233',
  bool includeGoods = true,
  String? goodsArray,
  String? extra,
}) {
  final goods = goodsArray ?? '[${_good()}]';
  return _obj([
    _field('OrderID', orderId == null ? null : _s(orderId)),
    _field(
      'InvoiceDate',
      invoiceDate == null
          ? null
          : (dateAsNumber ? invoiceDate : _s(invoiceDate)),
    ),
    _field('InvoiceNumber', invoiceNumber == null ? null : _s(invoiceNumber)),
    _field(
      'OrderNumber',
      orderNumber == null
          ? null
          : (quoteOrderNumber ? _s(orderNumber) : orderNumber),
    ),
    _field('Customer', customer == null ? null : _s(customer)),
    _field('CustomerPhone', customerPhone == null ? null : _s(customerPhone)),
    if (includeGoods) _field('Goods', goods),
    ?extra,
  ]);
}

String _dataset({
  String? storeName = 'Магазин Тест',
  String? dbName = 'Store_01-A',
  String? dateCreate = _created,
  bool dateAsNumber = false,
  bool includeStocks = true,
  String? stocksArray,
  bool includeOrders = true,
  String? ordersArray,
  String? extra,
}) {
  final stocks = stocksArray ?? '[${_stock()}]';
  final orders = ordersArray ?? '[${_order()}]';
  return _obj([
    _field('storeName', storeName == null ? null : _s(storeName)),
    _field('dbName', dbName == null ? null : _s(dbName)),
    _field(
      'dateCreate',
      dateCreate == null ? null : (dateAsNumber ? dateCreate : _s(dateCreate)),
    ),
    ?extra,
    if (includeStocks) _field('stocks', stocks),
    if (includeOrders) _field('orders', orders),
  ]);
}

RetailDataset _parse([String? source]) => _parser.parse(source ?? _dataset());

DatasetValidationException _invalid(String source) {
  try {
    _parser.parse(source);
  } on DatasetValidationException catch (error) {
    return error;
  }
  fail('Expected DatasetValidationException');
}

JsonSyntaxException _syntaxError(String source) {
  try {
    _parser.parse(source);
  } on JsonSyntaxException catch (error) {
    return error;
  }
  fail('Expected JsonSyntaxException');
}

String _goodsWithAmounts(List<String> amounts) =>
    '[${[for (var i = 0; i < amounts.length; i++) _good(product: 'Товар ${i + 1}', productId: '${i + 1}', price: '0', amount: amounts[i])].join(',')}]';

void main() {
  group('valid dataset', () {
    test('parses a valid dataset and ignores unknown fields', () {
      final dataset = _parse(
        _dataset(
          extra: '"comment":"ignore","version":1',
          stocksArray: '[${_stock(extra: '"Note":1e+2')}]',
          ordersArray:
              '[${_order(
                extra: '"Priority":false',
                goodsArray: '[${_good(extra: '"Discount":0')}]',
              )}]',
        ),
      );

      expect(dataset.storeName, 'Магазин Тест');
      expect(dataset.dbName, 'Store_01-A');
      expect(dataset.dateCreate, DateTime(2026, 10, 3, 11, 46, 18));

      final stock = dataset.stocks.single;
      expect(stock.address, 'A-01');
      expect(stock.productId, const ExactInteger(bigProductId));
      expect(stock.productId.literal, hasLength(19));
      expect(stock.serialNumber, 'SN-0001');
      expect(stock.quantity, 1);

      final order = dataset.orders.single;
      expect(order.orderId, 'ORD-1');
      expect(order.invoiceDate, DateTime(2026, 10, 3, 11, 46, 18));
      expect(order.invoiceNumber, 'ТЕСТ000001');
      expect(order.orderNumber.literal, '900000001');
      expect(order.customer, 'Тестовий Клієнт А');
      expect(order.customerPhone, '0501112233');

      final good = order.goods.single;
      expect(good.product, 'Тестовий товар 1');
      expect(good.productId.literal, bigProductId);
      expect(good.quantity, 1);
      expect(good.priceMinorUnits, 32450);
      expect(good.amountMinorUnits, 32450);
      expect(order.totalMinorUnits, 32450);
      expect(good.isServiceGood, isFalse);
      expect(good.isParcel, isFalse);
      expect(good.parcelTtn, isNull);
      expect(good.meestTtn, isNull);
    });

    test('trims required strings and accepts a leap-day timestamp', () {
      final dataset = _parse(
        _dataset(
          storeName: '  Магазин Тест  ',
          dbName: '  Store_01-A  ',
          dateCreate: '20240229120000',
          ordersArray:
              '[${_order(orderId: '  ORD-1  ', invoiceDate: '20240229120000', customerPhone: ' 0501112233 ')}]',
        ),
      );

      expect(dataset.storeName, 'Магазин Тест');
      expect(dataset.dbName, 'Store_01-A');
      expect(dataset.dateCreate, DateTime(2024, 2, 29, 12));
      expect(dataset.orders.single.orderId, 'ORD-1');
      expect(dataset.orders.single.customerPhone, '0501112233');
    });

    test('rejects compact dates written as JSON numbers', () {
      final created = _invalid(_dataset(dateAsNumber: true));
      expect(created.message, contains('«dateCreate»'));
      expect(created.message, contains('некоректна дата'));

      final invoice = _invalid(
        _dataset(ordersArray: '[${_order(dateAsNumber: true)}]'),
      );
      expect(invoice.message, contains('«InvoiceDate»'));
      expect(invoice.message, contains('ORD-1'));
      expect(invoice.message, contains('некоректна дата'));
    });
  });

  group('large identifiers', () {
    test('keeps an exact 19-digit ProductID', () {
      final dataset = _parse(
        _dataset(
          stocksArray: '[${_stock(productId: overInt64)}]',
          ordersArray:
              '[${_order(goodsArray: '[${_good(productId: bigProductId2)}]')}]',
        ),
      );

      expect(dataset.stocks.single.productId.literal, overInt64);
      expect(dataset.stocks.single.productId.literal, hasLength(19));
      expect(
        dataset.orders.single.goods.single.productId.literal,
        bigProductId2,
      );
      expect(bigProductId2, hasLength(19));
      expect(dataset.stocks.single.productId.literal, isNot(contains('.')));
      expect(
        dataset.stocks.single.productId.literal.toLowerCase(),
        isNot(contains('e')),
      );
    });

    test('keeps a large OrderNumber', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(orderNumber: largeOrderNumber)},'
              '${_order(orderId: 'ORD-2', orderNumber: overInt64, invoiceNumber: 'ТЕСТ000002')}]',
        ),
      );

      expect(dataset.orders[0].orderNumber.literal, largeOrderNumber);
      expect(dataset.orders[1].orderNumber.literal, overInt64);
      expect(dataset.orders[1].orderNumber.literal, hasLength(19));
    });

    test('accepts ProductID and OrderNumber equal to zero', () {
      final dataset = _parse(
        _dataset(
          stocksArray: '[${_stock(productId: '0')}]',
          ordersArray:
              '[${_order(
                orderNumber: '0',
                goodsArray: '[${_good(productId: '0')}]',
              )}]',
        ),
      );
      expect(dataset.stocks.single.productId.literal, '0');
      expect(dataset.orders.single.orderNumber.literal, '0');
      expect(dataset.orders.single.goods.single.productId.literal, '0');
    });

    for (final literal in ['-1', '-0', '-42']) {
      test('rejects ProductID $literal', () {
        final stock = _invalid(
          _dataset(stocksArray: '[${_stock(productId: literal)}]'),
        );
        expect(stock.message, contains('«ProductID»'));
        expect(stock.message, contains('невід’ємне'));

        final good = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(productId: literal)}]')}]',
          ),
        );
        expect(good.message, contains('«ProductID»'));
        expect(good.message, contains('товарі 1'));
      });

      test('rejects OrderNumber $literal', () {
        final error = _invalid(
          _dataset(ordersArray: '[${_order(orderNumber: literal)}]'),
        );
        expect(error.message, contains('«OrderNumber»'));
        expect(error.message, contains('ORD-1'));
        expect(error.message, contains('невід’ємне'));
      });
    }

    test('rejects null ProductID and OrderNumber', () {
      final product = _invalid(
        _dataset(
          stocksArray: '[{"Address":"A-01","ProductID":null,"SerialNumber":"SN-0001","Quantity":1}]',
        ),
      );
      expect(product.message, contains('«ProductID»'));
      expect(product.message, contains('залишку 1'));

      final order = _order().replaceFirst(
        '"OrderNumber":900000001',
        '"OrderNumber":null',
      );
      final number = _invalid(_dataset(ordersArray: '[$order]'));
      expect(number.message, contains('«OrderNumber»'));
      expect(number.message, contains('ORD-1'));
    });
  });

  group('quoted, fractional and exponent identifiers', () {
    test('rejects a quoted ProductID', () {
      final error = _invalid(
        _dataset(stocksArray: '[${_stock(quoteProductId: true)}]'),
      );
      expect(error.message, contains('ProductID'));
      expect(error.message, contains('залишку 1'));
      expect(error.message, contains('без лапок'));
    });

    test('rejects a quoted OrderNumber', () {
      final error = _invalid(
        _dataset(ordersArray: '[${_order(quoteOrderNumber: true)}]'),
      );
      expect(error.message, contains('OrderNumber'));
      expect(error.message, contains('ORD-1'));
      expect(error.message, contains('без лапок'));
    });

    test('rejects a quoted goods ProductID', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: '[${_good(quoteProductId: true)}]')}]',
        ),
      );
      expect(error.message, contains('ProductID'));
      expect(error.message, contains('товарі 1'));
    });

    for (final literal in ['12.5', '12.0', '1e18', '1E+2', '1.5e1']) {
      test('rejects ProductID $literal', () {
        final error = _invalid(
          _dataset(stocksArray: '[${_stock(productId: literal)}]'),
        );
        expect(error.message, contains('ProductID'));
        expect(error.message, contains('дробової частини та експоненти'));
      });

      test('rejects OrderNumber $literal', () {
        final error = _invalid(
          _dataset(ordersArray: '[${_order(orderNumber: literal)}]'),
        );
        expect(error.message, contains('OrderNumber'));
        expect(error.message, contains('експоненти'));
      });
    }

    test('rejects a leading-zero identifier as invalid JSON', () {
      expect(
        () => _parser.parse(
          _dataset(stocksArray: '[${_stock(productId: '01')}]'),
        ),
        throwsA(isA<JsonSyntaxException>()),
      );
    });
  });

  group('missing and blank fields', () {
    test('rejects a missing required field before later errors', () {
      final error = _invalid(
        _dataset(storeName: null, stocksArray: '[]', includeOrders: false),
      );
      expect(error.message, contains('У наборі даних'));
      expect(error.message, contains('«storeName»'));
      expect(error.message, contains('відсутнє'));
      expect(error.message, isNot(contains('stocks')));
    });

    test('rejects a missing stock field with its index', () {
      final error = _invalid(
        _dataset(stocksArray: '[${_stock()}, ${_stock(serialNumber: null)}]'),
      );
      expect(error.message, contains('залишку 2'));
      expect(error.message, contains('«SerialNumber»'));
    });

    test('rejects a missing order field before the order id exists', () {
      final error = _invalid(
        _dataset(ordersArray: '[${_order()}, ${_order(orderId: null)}]'),
      );
      expect(error.message, contains('замовленні 2'));
      expect(error.message, contains('«OrderID»'));
    });

    test('rejects the first invalid goods field', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '[${_good(product: null, quantity: null, isServiceGood: '1', isParcel: '1')}]',
              )}]',
        ),
      );
      expect(error.message, contains('«Product»'));
      expect(error.message, contains('товарі 1'));
      expect(error.message, isNot(contains('isServiceGood')));
    });

    for (final (label, source) in [
      ('storeName', _dataset(storeName: null)),
      ('dbName', _dataset(dbName: null)),
      ('dateCreate', _dataset(dateCreate: null)),
      ('stocks', _dataset(includeStocks: false)),
      ('orders', _dataset(includeOrders: false)),
      ('Address', _dataset(stocksArray: '[${_stock(address: null)}]')),
      ('Goods', _dataset(ordersArray: '[${_order(includeGoods: false)}]')),
      ('Customer', _dataset(ordersArray: '[${_order(customer: null)}]')),
    ]) {
      test('rejects missing $label', () {
        final error = _invalid(source);
        expect(error.message, contains('«$label»'));
        expect(error.message, contains('відсутнє'));
      });
    }

    for (final (label, source) in [
      ('storeName', _dataset(storeName: '   ')),
      ('dbName', _dataset(dbName: '')),
      ('Address', _dataset(stocksArray: '[${_stock(address: ' \n ')}]')),
      ('OrderID', _dataset(ordersArray: '[${_order(orderId: '  ')}]')),
      ('Customer', _dataset(ordersArray: '[${_order(customer: '   ')}]')),
      (
        'CustomerPhone',
        _dataset(ordersArray: '[${_order(customerPhone: '')}]'),
      ),
      (
        'Product',
        _dataset(
          ordersArray: '[${_order(goodsArray: '[${_good(product: '  ')}]')}]',
        ),
      ),
    ]) {
      test('rejects blank $label', () {
        final error = _invalid(source);
        expect(error.message, contains('«$label»'));
        expect(error.message, contains('не заповнено'));
      });
    }

    test(
      'rejects dbName outside ASCII letters, digits, underscore and hyphen',
      () {
        for (final name in ['Магазин', 'store.name', 'db/name', 'store name']) {
          final error = _invalid(_dataset(dbName: name));
          expect(error.message, contains('dbName'));
          expect(error.message, contains('латинські літери'));
        }
      },
    );

    test('rejects JSON null for a required field', () {
      final error = _invalid(
        '{"storeName":null,"dbName":"Store_01-A","dateCreate":"$_created",'
        '"stocks":[${_stock()}],"orders":[${_order()}]}',
      );
      expect(error.message, contains('«storeName»'));
      expect(error.message, contains('відсутнє'));
    });
  });

  group('dates', () {
    for (final raw in [
      '20260230114618',
      '20261301114618',
      '20261003240000',
      '20261003114660',
      '20230229120000',
      '20261003',
      '2026-10-03T11:46:18',
      'not-a-date',
      '20261003114618Z',
    ]) {
      test('rejects dateCreate $raw', () {
        final error = _invalid(_dataset(dateCreate: raw));
        expect(error.message, contains('«dateCreate»'));
        expect(error.message, contains('ррррММддГГххсс'));
      });

      test('rejects InvoiceDate $raw', () {
        final error = _invalid(
          _dataset(ordersArray: '[${_order(invoiceDate: raw)}]'),
        );
        expect(error.message, contains('«InvoiceDate»'));
        expect(error.message, contains('ORD-1'));
        expect(error.message, contains('20261003114618'));
      });
    }

    test('accepts an exact 14-digit timestamp on both fields', () {
      final dataset = _parse(
        _dataset(
          dateCreate: '20240229120000',
          ordersArray: '[${_order(invoiceDate: '20261003114618')}]',
        ),
      );
      expect(dataset.dateCreate, DateTime(2024, 2, 29, 12, 0, 0));
      expect(
        dataset.orders.single.invoiceDate,
        DateTime(2026, 10, 3, 11, 46, 18),
      );
    });

    for (final raw in [
      ' $_created',
      '$_created ',
      ' $_created ',
      '\t$_created',
      '$_created\n',
      '$_created\t',
      '',
      '   ',
    ]) {
      test('rejects padded dateCreate ${jsonEncode(raw)}', () {
        final error = _invalid(_dataset(dateCreate: raw));
        expect(error.message, contains('«dateCreate»'));
        expect(error.message, contains('некоректна дата'));
        expect(error.message, isNot(contains('не заповнено')));
      });

      test('rejects padded InvoiceDate ${jsonEncode(raw)}', () {
        final error = _invalid(
          _dataset(ordersArray: '[${_order(invoiceDate: raw)}]'),
        );
        expect(error.message, contains('«InvoiceDate»'));
        expect(error.message, contains('ORD-1'));
        expect(error.message, contains('некоректна дата'));
      });
    }

    test('rejects a missing or null timestamp', () {
      final missingCreated = _invalid(_dataset(dateCreate: null));
      expect(missingCreated.message, contains('«dateCreate»'));
      expect(missingCreated.message, contains('відсутнє'));

      final nullCreated = _invalid(
        _dataset().replaceFirst(
          '"dateCreate":"$_created"',
          '"dateCreate":null',
        ),
      );
      expect(nullCreated.message, contains('«dateCreate»'));
      expect(nullCreated.message, contains('відсутнє'));

      final missingInvoice = _invalid(
        _dataset(ordersArray: '[${_order(invoiceDate: null)}]'),
      );
      expect(missingInvoice.message, contains('«InvoiceDate»'));
      expect(missingInvoice.message, contains('відсутнє'));

      final nullInvoice = _invalid(
        _dataset(
          ordersArray:
              '[${_order().replaceFirst('"InvoiceDate":"$_created"', '"InvoiceDate":null')}]',
        ),
      );
      expect(nullInvoice.message, contains('«InvoiceDate»'));
      expect(nullInvoice.message, contains('ORD-1'));
      expect(nullInvoice.message, contains('відсутнє'));
    });

    test('still trims other required strings', () {
      final dataset = _parse(
        _dataset(
          storeName: '  Магазин Тест  ',
          dbName: '  Store_01-A  ',
          ordersArray:
              '[${_order(orderId: '  ORD-1  ', customerPhone: ' 0501112233 ')}]',
        ),
      );
      expect(dataset.storeName, 'Магазин Тест');
      expect(dataset.dbName, 'Store_01-A');
      expect(dataset.orders.single.orderId, 'ORD-1');
      expect(dataset.orders.single.customerPhone, '0501112233');
    });
  });

  group('empty collections', () {
    test('rejects empty stocks', () {
      final error = _invalid(_dataset(stocksArray: '[]'));
      expect(error.message, contains('«stocks»'));
      expect(error.message, contains('порожній'));
    });

    test('rejects empty orders', () {
      final error = _invalid(_dataset(ordersArray: '[]'));
      expect(error.message, contains('«orders»'));
      expect(error.message, contains('порожній'));
    });

    test('rejects empty Goods', () {
      final error = _invalid(
        _dataset(ordersArray: '[${_order(goodsArray: '[]')}]'),
      );
      expect(error.message, contains('«Goods»'));
      expect(error.message, contains('ORD-1'));
      expect(error.message, contains('порожній'));
    });
  });

  group('duplicates', () {
    test('rejects a duplicate OrderID after trimming', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(orderId: '  ORD-1  ')}, ${_order(orderId: 'ORD-1', invoiceNumber: 'ТЕСТ000002')}]',
        ),
      );
      expect(error.message, contains('повторюється'));
      expect(error.message, contains('«OrderID»'));
      expect(error.message, contains('«ORD-1»'));
    });

    test('rejects a duplicate ProductID within one order', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: '[${_good()}, ${_good(product: 'Інший товар')}]')}]',
        ),
      );
      expect(error.message, contains('ORD-1'));
      expect(error.message, contains('товарі 2'));
      expect(error.message, contains('повторюється'));
      expect(error.message, contains('«ProductID»'));
      expect(error.message, contains(bigProductId));
    });

    test('accepts the same ProductID in different orders', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order()}, ${_order(orderId: 'ORD-2', invoiceNumber: 'ТЕСТ000002')}]',
        ),
      );
      expect(
        dataset.orders.map((order) => order.goods.single.productId.literal),
        [bigProductId, bigProductId],
      );
    });

    test('accepts the same OrderNumber on different orders', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(orderNumber: largeOrderNumber)},'
              '${_order(orderId: 'ORD-2', orderNumber: largeOrderNumber, invoiceNumber: 'ТЕСТ000002')}]',
        ),
      );
      expect(dataset.orders, hasLength(2));
      expect(dataset.orders.map((order) => order.orderNumber.literal), [
        largeOrderNumber,
        largeOrderNumber,
      ]);
      expect(dataset.orders.map((order) => order.orderId), ['ORD-1', 'ORD-2']);
    });
  });

  group('quantity', () {
    test('accepts the minimum and the maximum', () {
      final dataset = _parse(
        _dataset(
          stocksArray: '[${_stock(quantity: '999999999')}]',
          ordersArray: '[${_order(goodsArray: '[${_good(quantity: '1')}]')}]',
        ),
      );
      expect(dataset.stocks.single.quantity, 999999999);
      expect(dataset.orders.single.goods.single.quantity, 1);
    });

    for (final literal in [
      '0',
      '-1',
      '1.5',
      '1.0',
      '1e2',
      '1000000000',
      '"2"',
      'true',
    ]) {
      test('rejects goods Quantity $literal', () {
        final error = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(quantity: literal)}]')}]',
          ),
        );
        expect(error.message, contains('«Quantity»'));
        expect(error.message, contains('ORD-1'));
        expect(error.message, contains('1 до 999999999'));
      });
    }

    test('rejects a stock quantity above the maximum', () {
      final error = _invalid(
        _dataset(stocksArray: '[${_stock(quantity: '1000000000')}]'),
      );
      expect(error.message, contains('залишку 1'));
      expect(error.message, contains('«Quantity»'));
    });
  });

  group('money', () {
    int minor(String literal) {
      final good = _parse(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '[${_good(price: literal, amount: literal)}]',
              )}]',
        ),
      ).orders.single.goods.single;
      expect(good.amountMinorUnits, good.priceMinorUnits);
      return good.priceMinorUnits;
    }

    test('converts exact decimal values to kopecks', () {
      expect(minor('324'), 32400);
      expect(minor('324.5'), 32450);
      expect(minor('324.50'), 32450);
      expect(minor('0'), 0);
      expect(minor('0.0'), 0);
      expect(minor('0.00'), 0);
      expect(minor('0.01'), 1);
      expect(minor('0.5'), 50);
      expect(minor('999999999999.99'), 99999999999999);
    });

    test('does not require Amount to equal Price times Quantity', () {
      final good = _parse(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '[${_good(quantity: '3', price: '10', amount: '1.5')} ]',
              )}]',
        ),
      ).orders.single.goods.single;
      expect(good.priceMinorUnits, 1000);
      expect(good.amountMinorUnits, 150);
    });

    for (final literal in [
      '324.500',
      '324.555',
      '10.000',
      '999999999999.999',
      '-0.01',
      '-1',
      '1e2',
      '1E+2',
      '1000000000000',
      '1000000000000.00',
      '"324.50"',
      'true',
    ]) {
      test('rejects Price $literal', () {
        final error = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(price: literal)}]')}]',
          ),
        );
        expect(error.message, contains('«Price»'));
        expect(error.message, contains('двома знаками'));
        expect(error.message, contains('без округлення'));
      });

      test('rejects Amount $literal', () {
        final error = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(amount: literal)}]')}]',
          ),
        );
        expect(error.message, contains('«Amount»'));
        expect(error.message, contains('999999999999.99'));
      });
    }
  });

  group('goods flags and parcel fields', () {
    test('accepts regular, service and parcel goods', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '['
                    '${_good(parcelTtnRaw: '1', meestTtnRaw: _s(''))},'
                    '${_good(product: 'Послуга', productId: bigProductId2, price: '0', amount: '0', isServiceGood: '1', parcelTtnRaw: _s('IGNORED'))},'
                    '${_good(product: 'Посилка', productId: '555', isParcel: '1', parcelTtnRaw: _s('  TTN-1  '), meestTtnRaw: _s('  ME-1  '))}'
                    ']',
              )}]',
        ),
      );
      final goods = dataset.orders.single.goods;

      expect(goods[0].isServiceGood, isFalse);
      expect(goods[0].isParcel, isFalse);
      expect(goods[0].parcelTtn, isNull);
      expect(goods[0].meestTtn, isEmpty);

      expect(goods[1].isServiceGood, isTrue);
      expect(goods[1].isParcel, isFalse);
      expect(goods[1].parcelTtn, isNull);
      expect(goods[1].priceMinorUnits, 0);

      expect(goods[2].isServiceGood, isFalse);
      expect(goods[2].isParcel, isTrue);
      expect(goods[2].parcelTtn, 'TTN-1');
      expect(goods[2].meestTtn, '  ME-1  ');
    });

    test('treats a missing or null MeestTTN as absent', () {
      final missing = _parse();
      expect(missing.orders.single.goods.single.meestTtn, isNull);

      final explicitNull = _parse(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: '[${_good(meestTtnRaw: 'null')}]')}]',
        ),
      );
      expect(explicitNull.orders.single.goods.single.meestTtn, isNull);
    });

    test('rejects isServiceGood and isParcel both set', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '[${_good(isServiceGood: '1', isParcel: '1', parcelTtnRaw: _s('TTN-1'))}]',
              )}]',
        ),
      );
      expect(error.message, contains('ORD-1'));
      expect(error.message, contains('товарі 1'));
      expect(error.message, contains('«isServiceGood»'));
      expect(error.message, contains('«isParcel»'));
      expect(error.message, contains('поєднання'));
    });

    for (final literal in ['2', '0.0', '"1"', 'true', '-1']) {
      test('rejects isServiceGood $literal', () {
        final error = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(isServiceGood: literal)}]')}]',
          ),
        );
        expect(error.message, contains('«isServiceGood»'));
        expect(error.message, contains('0 або 1'));
      });
    }

    test('rejects a parcel without ParcelTTN', () {
      final missing = _invalid(
        _dataset(
          ordersArray: '[${_order(goodsArray: '[${_good(isParcel: '1')}]')}]',
        ),
      );
      expect(missing.message, contains('«ParcelTTN»'));
      expect(missing.message, contains('відсутнє'));
      expect(missing.message, contains('ORD-1'));

      final blank = _invalid(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '[${_good(isParcel: '1', parcelTtnRaw: _s('   '))}]',
              )}]',
        ),
      );
      expect(blank.message, contains('«ParcelTTN»'));
      expect(blank.message, contains('не заповнено'));
    });

    test('preserves MeestTTN text exactly', () {
      const whitespace = ' \n\t ';
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(
                goodsArray: '['
                    '${_good(meestTtnRaw: _s(''))},'
                    '${_good(product: 'Пробіл', productId: '2', meestTtnRaw: _s(whitespace))},'
                    '${_good(product: 'Текст', productId: '3', meestTtnRaw: _s('  ME-1  '))}'
                    ']',
              )}]',
        ),
      );
      final goods = dataset.orders.single.goods;
      expect(goods[0].meestTtn, '');
      expect(goods[1].meestTtn, whitespace);
      expect(goods[1].meestTtn, hasLength(whitespace.length));
      expect(goods[2].meestTtn, '  ME-1  ');
    });

    for (final literal in ['15', 'true', '[]', '{"code":1}']) {
      test('rejects MeestTTN $literal', () {
        final error = _invalid(
          _dataset(
            ordersArray:
                '[${_order(goodsArray: '[${_good(meestTtnRaw: literal)}]')}]',
          ),
        );
        expect(error.message, contains('«MeestTTN»'));
        expect(error.message, contains('некоректне'));
        expect(error.message, contains('ORD-1'));
      });
    }
  });

  group('inventory is not a validity rule', () {
    test('accepts an order whose product is absent from stocks', () {
      final dataset = _parse(
        _dataset(
          stocksArray: '[${_stock(productId: '777')}]',
          ordersArray:
              '[${_order(goodsArray: '[${_good(productId: '555')}]')}]',
        ),
      );
      expect(dataset.stocks.single.productId.literal, '777');
      expect(dataset.orders.single.goods.single.productId.literal, '555');
    });

    test('preserves duplicate stock rows', () {
      final row = _stock(
        address: 'A-01',
        productId: bigProductId,
        serialNumber: 'SN-0001',
        quantity: '2',
      );
      final dataset = _parse(_dataset(stocksArray: '[$row,$row]'));
      expect(dataset.stocks, hasLength(2));
      expect(dataset.stocks[0], dataset.stocks[1]);
      expect(dataset.stocks[0].productId.literal, bigProductId);
      expect(dataset.stocks[0].quantity, 2);
    });
  });

  group('duplicate object keys', () {
    test('rejects a duplicate root key, including an unknown one', () {
      final known = _syntaxError(
        _dataset().replaceFirst('{', '{"storeName":"Інший",'),
      );
      expect(known.message, contains('«storeName»'));
      expect(known.message, contains('повторюється поле'));
      expect(known.message, contains('рядок'));
      expect(known.line, 1);

      final unknown = _syntaxError(_dataset(extra: '"comment":1,"comment":2'));
      expect(unknown.message, contains('«comment»'));
    });

    test('rejects a duplicate key written with an equivalent escape', () {
      final error = _syntaxError('{"storeName":"А","store\\u004Eame":"Б"}');
      expect(error.message, contains('«storeName»'));
      expect(error.message, contains('позиція'));
    });

    test('rejects a duplicate key inside an order and inside goods', () {
      final order = '{"OrderID":"X",${_order().substring(1)}';
      final orderError = _syntaxError(_dataset(ordersArray: '[$order]'));
      expect(orderError.message, contains('«OrderID»'));

      final good = '{"Product":"X",${_good().substring(1)}';
      final goodError = _syntaxError(
        _dataset(ordersArray: '[${_order(goodsArray: '[$good]')}]'),
      );
      expect(goodError.message, contains('«Product»'));
    });

    test('rejects a duplicate key inside an unknown nested object', () {
      final error = _syntaxError(_dataset(extra: '"meta":{"note":1,"note":2}'));
      expect(error.message, contains('«note»'));
    });

    test('allows the same property name in different objects', () {
      final dataset = _parse(
        _dataset(
          stocksArray:
              '[${_stock()}, ${_stock(address: 'B-02', serialNumber: 'SN-0002', productId: bigProductId2)}]',
          ordersArray:
              '[${_order(
                goodsArray: '['
                    '${_good()},'
                    '${_good(product: 'Інший', productId: bigProductId2)}'
                    ']',
              )}]',
        ),
      );
      expect(dataset.stocks, hasLength(2));
      expect(dataset.orders.single.goods, hasLength(2));
      expect(dataset.orders.single.totalMinorUnits, 64900);
    });
  });

  group('UTF-8 BOM', () {
    test('accepts one leading BOM', () {
      final dataset = _parse('\uFEFF${_dataset()}');
      expect(dataset.storeName, 'Магазин Тест');
      expect(dataset.orders.single.orderNumber.literal, '900000001');
    });

    test('keeps a BOM that is part of a string', () {
      final dataset = _parse(_dataset(storeName: 'A\uFEFFB'));
      expect(dataset.storeName, 'A\uFEFFB');
    });

    test('rejects a repeated or misplaced BOM', () {
      expect(
        () => _parse('\uFEFF\uFEFF${_dataset()}'),
        throwsA(isA<JsonSyntaxException>()),
      );
      final body = _dataset();
      expect(
        () => _parse('${body[0]}\uFEFF${body.substring(1)}'),
        throwsA(isA<JsonSyntaxException>()),
      );
      expect(
        () => _parse(' \uFEFF${_dataset()}'),
        throwsA(isA<JsonSyntaxException>()),
      );
    });
  });

  group('order total', () {
    const maxAmount = '999999999999.99';
    const exactRemainder = '71992547410.81';
    const overRemainder = '71992547410.82';

    List<String> limitAmounts(String remainder) => [
      for (var i = 0; i < 90; i++) maxAmount,
      remainder,
    ];

    test('stores a normal total and does not derive it from price', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: _goodsWithAmounts(['324.50', '10']))}]',
        ),
      );
      expect(dataset.orders.single.totalMinorUnits, 33450);
      expect(dataset.orders.single.goods[1].priceMinorUnits, 0);
      expect(dataset.orders.single.goods[1].amountMinorUnits, 1000);
    });

    test('accepts an order total equal to the safe integer limit', () {
      final dataset = _parse(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: _goodsWithAmounts(limitAmounts(exactRemainder)))}]',
        ),
      );
      expect(
        dataset.orders.single.totalMinorUnits,
        DatasetLimits.maxSafeMinorUnits,
      );
    });

    test('rejects an order total one kopeck above the safe integer limit', () {
      final error = _invalid(
        _dataset(
          ordersArray:
              '[${_order(goodsArray: _goodsWithAmounts(limitAmounts(overRemainder)))}]',
        ),
      );
      expect(error.message, contains('У замовленні «ORD-1»'));
      expect(error.message, contains('«Amount»'));
      expect(error.message, contains('9007199254740991'));
    });
  });

  group('Ukrainian validation errors', () {
    test('names the field and the stock or order location', () {
      final datasetError = _invalid(_dataset(storeName: null));
      expect(datasetError.message, contains('У наборі даних'));
      expect(datasetError.message, contains('«storeName»'));
      expect(
        RegExp(r'[А-Яа-яІіЇїЄєҐґ]').hasMatch(datasetError.message),
        isTrue,
      );

      final stockError = _invalid(
        _dataset(stocksArray: '[${_stock(address: null)}]'),
      );
      expect(stockError.message, contains('У залишку 1'));
      expect(stockError.message, contains('«Address»'));
      expect(stockError.message, contains('відсутнє обов’язкове поле'));

      final orderError = _invalid(
        _dataset(ordersArray: '[${_order(customer: '  ')}]'),
      );
      expect(orderError.message, contains('У замовленні «ORD-1»'));
      expect(orderError.message, contains('«Customer»'));
      expect(orderError.message, contains('не заповнено значення'));
    });

    test('rejects a JSON array root as a dataset', () {
      final error = _invalid('[]');
      expect(error.message, 'Набір даних має бути JSON-об’єктом.');
    });
  });
}
