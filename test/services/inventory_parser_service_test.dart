import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/services/excel/excel_import_service.dart';
import 'package:retail_offline/services/excel/inventory_parser_service.dart';

import '../support/fixtures.dart';
import '../support/xlsx_builder.dart';

List<InventoryBalance> _parse(Uint8List bytes) => const InventoryParserService()
    .parse(const ExcelImportService().readFirstSheet(bytes));

List<InventoryBalance> _parseRows(
  List<Map<String, Object?>> rows, {
  List<String>? headers,
}) => _parse(inventoryXlsx(rows, headers: headers));

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
  group('InventoryParserService', () {
    test('parses a valid file', () {
      final items = _parseRows(sampleInventoryRows());
      expect(items, hasLength(4));
      expect(items.first.address, r'$$AGVI');
      expect(items.first.productId, bigProductId);
      expect(items.first.serialNumber, 'SN-0001');
      expect(items.first.quantity, 1);
    });

    test('trims Address', () {
      final item = _parseRows([
        inventoryRow(address: '   \$\$AGVI             '),
      ]).single;
      expect(item.address, r'$$AGVI');
    });

    test('keeps a 19-digit text ProductID exactly', () {
      expect(
        _parseRows([inventoryRow(productId: bigProductId)]).single.productId,
        bigProductId,
      );
    });

    test('numeric ProductID becomes a plain String', () {
      expect(
        _parseRows([inventoryRow(productId: const XlsxNumber('43848'))])
            .single
            .productId,
        '43848',
      );
    });

    test('rejects an exponent-form numeric ProductID', () {
      final e = _failure([
        inventoryRow(productId: const XlsxNumber('1.29056410378919E+18')),
      ]);
      expect(e.message, contains('ProductID'));
      expect(e.message, contains('рядку 2'));
      expect(e.message, contains('точність'));
    });

    test('text SerialNumber', () {
      expect(
        _parseRows([inventoryRow(serialNumber: r'$OS415248')])
            .single
            .serialNumber,
        r'$OS415248',
      );
    });

    test('numeric SerialNumber becomes a String without ".0"', () {
      expect(
        _parseRows([
          inventoryRow(serialNumber: const XlsxNumber('2251313016465')),
        ]).single.serialNumber,
        '2251313016465',
      );
    });

    test('SerialNumber with a leading zero is preserved', () {
      final items = _parseRows([
        inventoryRow(serialNumber: '0MSH3HJL900062'),
        inventoryRow(serialNumber: '00554244106062000627'),
      ]);
      expect(items[0].serialNumber, '0MSH3HJL900062');
      expect(items[1].serialNumber, '00554244106062000627');
    });

    test('Quantity may be greater than 1 (not assumed to be 1)', () {
      expect(_parseRows([inventoryRow(quantity: '8')]).single.quantity, 8);
    });

    test('rejects invalid Quantity', () {
      for (final bad in ['x', '-1', '1.5']) {
        expect(
          _failure([inventoryRow(quantity: bad)]).message,
          contains('Quantity'),
        );
      }
    });

    test('the same SerialNumber may appear several times', () {
      final items = _parseRows([
        inventoryRow(serialNumber: 'DUP'),
        inventoryRow(serialNumber: 'DUP', productId: '555'),
      ]);
      expect(items, hasLength(2));
    });

    test('headers are matched by name regardless of column order', () {
      final items = _parseRows(
        [inventoryRow(serialNumber: 'SN-9', quantity: '3')],
        headers: ['Quantity', 'SerialNumber', 'ProductID', 'Address'],
      );
      expect(items.single.serialNumber, 'SN-9');
      expect(items.single.quantity, 3);
      expect(items.single.address, r'$$TEST01');
    });

    test('missing required header', () {
      final e = _failure(
        [inventoryRow()],
        headers: ['Address', 'ProductID', 'Quantity'],
      );
      expect(e.message, contains('SerialNumber'));
    });

    test('empty worksheet and zero data rows are rejected', () {
      expect(
        () => _parse(buildXlsx(const [])),
        throwsA(isA<ImportException>()),
      );
      expect(() => _parseRows(const []), throwsA(isA<ImportException>()));
    });

    group('SerialNumber business rule: required on every row', () {
      Map<String, Object?> withSerial(Object? serial) => {
        ...inventoryRow(),
        InventoryParserService.serialNumber: serial,
      };

      void expectRowError(Object? serial, {required int row}) {
        final e = _failure([inventoryRow(), withSerial(serial)]);
        expect(e.message, contains('SerialNumber'));
        expect(e.message, contains('рядку $row'));
        expect(e.message, isNot(contains('Exception')));
      }

      test('absent cell (no value at all) fails with the Excel row', () {
        expectRowError(null, row: 3);
      });

      test('whitespace-only text fails with the Excel row', () {
        expectRowError('   ', row: 3);
        expectRowError('\u00A0', row: 3); // non-breaking space is trimmed too
      });

      test('empty text and empty inline string fail with the Excel row', () {
        expectRowError('', row: 3);
        expectRowError(const XlsxInline(''), row: 3);
      });

      test('one bad row fails the WHOLE import, rows are never skipped', () {
        final rows = [
          inventoryRow(serialNumber: 'SN-1'),
          inventoryRow(serialNumber: 'SN-2'),
          withSerial(null),
          inventoryRow(serialNumber: 'SN-4'),
        ];
        final e = _failure(rows);
        expect(e.message, contains('рядку 4'));
        expect(() => _parseRows(rows), throwsA(isA<ImportException>()));
      });

      test(
        'exponent / fractional numeric serials are rejected, not guessed',
        () {
          for (final unsafe in ['2.25131301646E+12', '1E+5', '12.5']) {
            final e = _failure([
              inventoryRow(serialNumber: XlsxNumber(unsafe)),
            ]);
            expect(e.message, contains('SerialNumber'), reason: unsafe);
            expect(e.message, contains('рядку 2'), reason: unsafe);
            expect(e.message, contains('точність'), reason: unsafe);
          }
        },
      );

      test('safe numeric serial is accepted as its exact integer text', () {
        final items = _parseRows([
          inventoryRow(serialNumber: const XlsxNumber('2251313016465')),
          inventoryRow(serialNumber: const XlsxNumber('2251313016465.0')),
        ]);
        expect(items.map((b) => b.serialNumber), [
          '2251313016465',
          '2251313016465',
        ]);
      });

      test('no uniqueness rule: identical serials are both kept', () {
        final items = _parseRows([
          inventoryRow(serialNumber: 'SAME', productId: '111'),
          inventoryRow(serialNumber: 'SAME', productId: '222'),
        ]);
        expect(items, hasLength(2));
        expect(items.map((b) => b.serialNumber), ['SAME', 'SAME']);
      });
    });

    test('missing SerialNumber value names the Excel row', () {
      final e = _failure([inventoryRow(), inventoryRow(serialNumber: '  ')]);
      expect(e.message, contains('SerialNumber'));
      expect(e.message, contains('рядку 3'));
    });
  });
}
