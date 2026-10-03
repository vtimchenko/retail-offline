import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/services/excel/excel_import_service.dart';
import 'package:retail_offline/services/excel/orders_parser_service.dart';

import '../support/fixtures.dart';
import '../support/xlsx_builder.dart';

List<Order> _parse(Uint8List bytes) {
  const excel = ExcelImportService();
  const parser = OrdersParserService();
  return parser.parse(excel.readFirstSheet(bytes));
}

List<Order> _parseRows(
  List<Map<String, Object?>> rows, {
  List<String>? headers,
}) => _parse(ordersXlsx(rows, headers: headers));

ImportException _failure(
  List<Map<String, Object?>> rows, {
  List<String>? headers,
}) {
  try {
    _parseRows(rows, headers: headers);
  } on ImportException catch (e) {
    return e;
  }
  fail('Expected ImportException');
}

void main() {
  group('OrdersParserService – values', () {
    test('parses a one-row order', () {
      final orders = _parseRows([orderRow()]);

      expect(orders, hasLength(1));
      final order = orders.single;
      expect(order.invoiceDate, DateTime(2026, 10, 3, 11, 46, 18));
      expect(order.invoiceNumber, 'ТЕСТ000001');
      expect(order.orderNumber, '900000001');
      expect(order.customer, 'Тестовий Клієнт А');
      expect(order.customerPhone, '0501112233');
      expect(order.items, hasLength(1));
      final item = order.items.single;
      expect(item.product, 'Тестовий товар 1');
      expect(item.quantity, 1);
      expect(item.priceMinorUnits, 32900);
      expect(item.amountMinorUnits, 32900);
    });

    test('keeps a 19-digit text ProductID exactly', () {
      final item = _parseRows([orderRow(productId: bigProductId)])
          .single
          .items
          .single;
      expect(item.productId, bigProductId);
      expect(item.productId.length, 19);
    });

    test('converts a safe numeric ProductID to a plain String', () {
      final item = _parseRows([orderRow(productId: const XlsxNumber('43848'))])
          .single
          .items
          .single;
      expect(item.productId, '43848');
    });

    test('normalizes an exact-integer numeric ProductID such as 43848.00', () {
      final item = _parseRows([
        orderRow(productId: const XlsxNumber('43848.00')),
      ]).single.items.single;
      expect(item.productId, '43848');
    });

    test('rejects a numeric ProductID in exponent form (precision lost)', () {
      final e = _failure([
        orderRow(),
        orderRow(
          orderNumber: const XlsxNumber('900000002'),
          productId: const XlsxNumber('1.29056410378919E+18'),
        ),
      ]);
      expect(e.message, contains('ProductID'));
      expect(e.message, contains('рядку 3'));
      expect(e.message, contains('точність'));
    });

    test('rejects a fractional numeric identifier', () {
      final e = _failure([orderRow(productId: const XlsxNumber('12.5'))]);
      expect(e.message, contains('ProductID'));
      expect(e.message, contains('рядку 2'));
    });

    test('keeps the leading zero of CustomerPhone', () {
      final order = _parseRows([orderRow(customerPhone: '0964481255')]).single;
      expect(order.customerPhone, '0964481255');
    });

    test('rejects a numeric CustomerPhone (leading zeroes may be lost)', () {
      final rows = [orderRow()];
      final bytes = buildXlsx([
        OrdersParserService.requiredHeaders,
        [
          for (final h in OrdersParserService.requiredHeaders)
            h == OrdersParserService.customerPhone
                ? const XlsxNumber('501112233')
                : rows.single[h],
        ],
      ]);
      expect(
        () => _parse(bytes),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('CustomerPhone'),
          ),
        ),
      );
    });

    test(
      'OrderNumber and InvoiceNumber are Strings (numeric or text cell)',
      () {
        final orders = _parseRows([
          orderRow(orderNumber: const XlsxNumber('907703574')),
          orderRow(orderNumber: 'ABC-1', invoiceNumber: 'РОЗ628244039'),
        ]);
        expect(orders.map((o) => o.orderNumber), ['907703574', 'ABC-1']);
        expect(orders.last.invoiceNumber, 'РОЗ628244039');
      },
    );

    test('headers are matched by name, independent of column order', () {
      final reversed = OrdersParserService.requiredHeaders.reversed.toList();
      final orders = _parseRows([orderRow()], headers: reversed);
      expect(orders.single.orderNumber, '900000001');
      expect(orders.single.items.single.productId, bigProductId);
    });

    test('extra columns and header case/whitespace are tolerated', () {
      final headers = [
        ...OrdersParserService.requiredHeaders.map(
          (h) => ' ${h.toLowerCase()} ',
        ),
        'Коментар',
      ];
      final row = orderRow();
      final bytes = buildXlsx([
        headers,
        [
          for (final h in OrdersParserService.requiredHeaders) row[h],
          'не потрібно',
        ],
      ]);
      expect(_parse(bytes), hasLength(1));
    });

    test('reads the first sheet even if it has an arbitrary name', () {
      final orders = _parse(ordersXlsx([orderRow()], sheetName: 'testqqq'));
      expect(orders, hasLength(1));
    });

    test('skips blank rows', () {
      final h = OrdersParserService.requiredHeaders;
      final r = orderRow();
      final bytes = buildXlsx([
        h,
        [for (final n in h) r[n]],
        List<Object?>.filled(h.length, null),
        [for (final n in h) r[n]],
      ]);
      expect(_parse(bytes).single.items, hasLength(2));
    });
  });

  group('OrdersParserService – money', () {
    int amountOf(String price) =>
        _parseRows([orderRow(price: price, amount: price)])
            .single
            .items
            .single
            .priceMinorUnits;

    test('integer', () => expect(amountOf('329'), 32900));
    test('two decimals', () => expect(amountOf('329.00'), 32900));
    test('one decimal', () => expect(amountOf('329.5'), 32950));
    test('cents', () => expect(amountOf('0.07'), 7));
    test('comma separator', () => expect(amountOf('1234,56'), 123456));
    test(
      'extra zero decimals are allowed',
      () => expect(amountOf('9.500'), 950),
    );
    test(
      'large value stays exact',
      () => expect(amountOf('59999.99'), 5999999),
    );

    test('numeric cell is parsed from its text', () {
      final bytes = buildXlsx([
        OrdersParserService.requiredHeaders,
        [
          for (final h in OrdersParserService.requiredHeaders)
            if (h == OrdersParserService.price)
              const XlsxNumber('19.99')
            else
              orderRow()[h],
        ],
      ]);
      expect(_parse(bytes).single.items.single.priceMinorUnits, 1999);
    });

    test('rejects more than two decimal places', () {
      final e = _failure([orderRow(price: '10.005')]);
      expect(e.message, contains('Price'));
      expect(e.message, contains('рядку 2'));
    });

    for (final bad in ['abc', '-5.00', '1e3', '10.5.1', '1 000.00', '']) {
      test('rejects invalid money "$bad"', () {
        expect(
          () => _parseRows([orderRow(amount: bad)]),
          throwsA(isA<ImportException>()),
        );
      });
    }

    test('does NOT require Amount == Price × Quantity', () {
      final item = _parseRows([
        orderRow(quantity: '2', price: '185.00', amount: '300.00'),
      ]).single.items.single;
      expect(item.priceMinorUnits, 18500);
      expect(item.amountMinorUnits, 30000);
    });
  });

  group('OrdersParserService – quantity', () {
    test('accepts whole numbers', () {
      expect(
        _parseRows([orderRow(quantity: '9')]).single.items.single.quantity,
        9,
      );
    });

    for (final bad in ['0', '1.5', '-1', 'abc']) {
      test('rejects quantity "$bad"', () {
        final e = _failure([orderRow(quantity: bad)]);
        expect(e.message, contains('Quantity'));
      });
    }
  });

  group('OrdersParserService – grouping', () {
    test('one order with several Excel rows becomes ONE Order with items', () {
      final orders = _parseRows([
        orderRow(orderNumber: const XlsxNumber('900000001')),
        orderRow(
          orderNumber: const XlsxNumber('900000002'),
          customerPhone: '0671112233',
          invoiceNumber: 'ТЕСТ000002',
          product: 'B1',
          productId: bigProductId2,
        ),
        orderRow(
          orderNumber: const XlsxNumber('900000002'),
          customerPhone: '0671112233',
          invoiceNumber: 'ТЕСТ000002',
          product: 'B2',
          productId: bigProductId3,
        ),
        orderRow(
          orderNumber: const XlsxNumber('900000002'),
          customerPhone: '0671112233',
          invoiceNumber: 'ТЕСТ000002',
          product: 'B3',
          productId: '43848',
        ),
      ]);

      // 4 Excel rows → 2 orders, not 4.
      expect(orders, hasLength(2));
      expect(orders[0].items, hasLength(1));
      expect(orders[1].orderNumber, '900000002');
      expect(orders[1].items, hasLength(3));
      expect(orders[1].items.map((i) => i.product), ['B1', 'B2', 'B3']);
      expect(orders[1].items.map((i) => i.productId), [
        bigProductId2,
        bigProductId3,
        '43848',
      ]);
    });

    test('groups non-adjacent rows and keeps first-appearance order', () {
      final orders = _parseRows(sampleOrderRows());

      expect(orders.map((o) => o.orderNumber), [
        '900000001',
        '900000002',
        '900000003',
      ]);
      // Order 900000002 appears in Excel rows 3, 5 and 6 (C is in between).
      final b = orders[1];
      expect(b.items.map((i) => i.product), [
        'Товар B1',
        'Товар B2',
        'Товар B3',
      ]);
    });

    test('counts: Orders vs OrderItems', () {
      final orders = _parseRows(sampleOrderRows());
      final itemCount = orders.fold<int>(0, (sum, o) => sum + o.items.length);
      expect(orders.length, 3);
      expect(itemCount, 5);
    });

    test('the same ProductID twice in one order stays two items', () {
      final orders = _parseRows([
        orderRow(productId: bigProductId),
        orderRow(productId: bigProductId, quantity: '2'),
      ]);
      expect(orders.single.items, hasLength(2));
    });

    for (final field in [
      (OrdersParserService.invoiceNumber, {'invoiceNumber': 'ІНША'}),
      (OrdersParserService.customer, {'customer': 'Інший Клієнт'}),
      (OrdersParserService.customerPhone, {'customerPhone': '0990000000'}),
      (OrdersParserService.invoiceDate, {'invoiceDate': '20261004000000'}),
    ]) {
      test(
        'conflicting ${field.$1} for one OrderNumber fails with the row',
        () {
          final changed = field.$2;
          final second = orderRow(
            invoiceNumber: changed['invoiceNumber'] ?? 'ТЕСТ000001',
            customer: changed['customer'] ?? 'Тестовий Клієнт А',
            customerPhone: changed['customerPhone'] ?? '0501112233',
            invoiceDate: changed['invoiceDate'] ?? '20261003114618',
            productId: bigProductId2,
          );
          final e = _failure([
            orderRow(),
            orderRow(
              orderNumber: const XlsxNumber('900000009'),
              productId: bigProductId3,
            ),
            second,
          ]);
          expect(e.message, contains(field.$1));
          expect(e.message, contains('900000001'));
          expect(e.message, contains('рядках 2 і 4'));
        },
      );
    }
  });

  group('OrdersParserService – structure errors', () {
    test('missing required header lists it', () {
      final headers = OrdersParserService.requiredHeaders
          .where((h) => h != OrdersParserService.productId)
          .toList();
      final e = _failure([orderRow()], headers: headers);
      expect(e.message, contains('ProductID'));
      expect(e.message, contains('стовпці'));
    });

    test('several missing headers are all listed', () {
      final e = _failure(
        [orderRow()],
        headers: [OrdersParserService.orderNumber],
      );
      expect(e.message, contains('InvoiceDate'));
      expect(e.message, contains('Amount'));
    });

    test('an empty worksheet is rejected', () {
      expect(
        () => _parse(buildXlsx(const [])),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('порожній'),
          ),
        ),
      );
    });

    test('headers only (zero data rows) is rejected', () {
      expect(
        () => _parse(ordersXlsx(const [])),
        throwsA(
          isA<ImportException>().having(
            (e) => e.message,
            'message',
            contains('немає жодного рядка'),
          ),
        ),
      );
    });

    test('a missing value names the field and the Excel row', () {
      final e = _failure([orderRow(), orderRow(customer: '   ')]);
      expect(e.message, contains('Customer'));
      expect(e.message, contains('рядку 3'));
    });

    test('an invalid date is rejected', () {
      final e = _failure([orderRow(invoiceDate: '20261345000000')]);
      expect(e.message, contains('InvoiceDate'));
    });

    test('the first invalid row fails the entire file', () {
      final e = _failure([
        orderRow(),
        orderRow(orderNumber: const XlsxNumber('900000005'), quantity: 'x'),
        orderRow(orderNumber: const XlsxNumber('900000006')),
      ]);
      expect(e.message, contains('рядку 3'));
    });

    test('error messages never contain Dart type names or stack traces', () {
      final e = _failure([orderRow(price: 'abc')]);
      expect(e.message, isNot(contains('Exception')));
      expect(e.message, isNot(contains('#0')));
    });
  });
}
