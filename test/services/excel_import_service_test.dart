import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/services/excel/excel_import_service.dart';
import 'package:retail_offline/services/excel/raw_sheet.dart';

import '../support/xlsx_builder.dart';

const _service = ExcelImportService();

RawCell? _cell(RawSheet s, int rowIndex, int col) =>
    s.rows[rowIndex].cells[col];

void main() {
  group('ExcelImportService.readFirstSheet', () {
    test('reads the first worksheet whatever its name or file is', () {
      final bytes = buildXlsx(
        [
          ['A', 'B'],
          ['x', 'y'],
        ],
        sheetName: 'testqqq',
        extraSheets: [
          [
            ['other sheet'],
          ],
        ],
      );
      final sheet = _service.readFirstSheet(bytes);
      expect(sheet.rows, hasLength(2));
      expect(_cell(sheet, 0, 0), const RawCell.text('A'));
      expect(_cell(sheet, 1, 1), const RawCell.text('y'));
    });

    test('keeps numeric cells as verbatim text (no int/double conversion)', () {
      final bytes = buildXlsx([
        [
          const XlsxNumber('1290564103789190763'),
          const XlsxNumber('43848'),
          const XlsxNumber('1.29056410378919E+18'),
          const XlsxNumber('9007199254740993'),
          const XlsxNumber('329.10'),
        ],
      ]);
      final row = _service.readFirstSheet(bytes).rows.single;
      expect(row.cells[0], const RawCell.number('1290564103789190763'));
      expect(row.cells[1], const RawCell.number('43848'));
      expect(row.cells[2], const RawCell.number('1.29056410378919E+18'));
      expect(row.cells[3], const RawCell.number('9007199254740993'));
      // Trailing zero survives too: it is text, not a double.
      expect(row.cells[4], const RawCell.number('329.10'));
    });

    test('shared strings keep leading zeroes and surrounding spaces', () {
      final bytes = buildXlsx([
        ['0501112233', '\$\$AGVI             '],
      ]);
      final row = _service.readFirstSheet(bytes).rows.single;
      expect(row.cells[0], const RawCell.text('0501112233'));
      expect(row.cells[1]!.value, '\$\$AGVI             ');
    });

    test('rich-text shared strings are concatenated, phonetics ignored', () {
      final bytes = buildXlsx([
        [
          const XlsxRich(['Част', 'ина 1']),
        ],
      ]);
      expect(
        _service.readFirstSheet(bytes).rows.single.cells[0],
        const RawCell.text('Частина 1'),
      );
    });

    test('inline strings, booleans and cached formula results', () {
      final bytes = buildXlsx([
        [
          const XlsxInline('inline'),
          true,
          const XlsxFormulaText('0007'),
          const XlsxFormulaNumber('2'),
        ],
      ]);
      final cells = _service.readFirstSheet(bytes).rows.single.cells;
      expect(cells[0], const RawCell.text('inline'));
      expect(cells[1], const RawCell(RawCellType.boolean, 'true'));
      expect(cells[2], const RawCell.text('0007'));
      expect(cells[3], const RawCell.number('2'));
    });

    test('works without styles.xml and without sharedStrings.xml', () {
      final bytes = buildXlsx(
        [
          [const XlsxInline('h'), const XlsxNumber('1')],
        ],
        includeStyles: false,
        includeSharedStringsPart: false,
      );
      final cells = _service.readFirstSheet(bytes).rows.single.cells;
      expect(cells[0], const RawCell.text('h'));
      expect(cells[1], const RawCell.number('1'));
    });

    test('blank cells keep column positions; blank rows are dropped', () {
      final bytes = buildXlsx(
        [
          ['a', null, 'c'],
          [null, null],
          ['d'],
        ],
        rowNumbers: [1, 2, 5],
      );
      final sheet = _service.readFirstSheet(bytes);
      expect(sheet.rows.map((r) => r.number), [1, 5]);
      expect(sheet.rows.first.cells.keys, [0, 2]);
    });

    test('an empty worksheet yields no rows', () {
      expect(_service.readFirstSheet(buildXlsx(const [])).rows, isEmpty);
    });

    test('column references beyond Z are mapped correctly', () {
      final row = List<Object?>.filled(28, null);
      row[26] = 'AA'; // column AA
      row[27] = 'AB';
      final cells = _service.readFirstSheet(buildXlsx([row])).rows.single.cells;
      expect(cells[26], const RawCell.text('AA'));
      expect(cells[27], const RawCell.text('AB'));
    });
  });

  group('ExcelImportService errors', () {
    ImportException failure(Uint8List bytes) {
      try {
        _service.readFirstSheet(bytes);
      } on ImportException catch (e) {
        return e;
      }
      fail('Expected ImportException');
    }

    test('rejects content that is not a ZIP', () {
      final html = Uint8List.fromList('<!DOCTYPE html><html></html>'.codeUnits);
      expect(failure(html).message, contains('Excel'));
      expect(failure(Uint8List(0)).message, isNotEmpty);
    });

    test('rejects a corrupted ZIP', () {
      final good = buildXlsx([
        ['a'],
      ]);
      final corrupted = Uint8List.fromList(good.sublist(0, good.length ~/ 2));
      expect(failure(corrupted).message, contains('Excel'));
    });

    test('rejects a ZIP without a workbook', () {
      expect(failure(buildZipWithoutWorkbook()).message, contains('книгу'));
    });

    test('verifyWorkbook accepts xlsx and rejects other ZIPs', () {
      _service.verifyWorkbook(
        buildXlsx([
          ['a'],
        ]),
      );
      expect(
        () => _service.verifyWorkbook(buildZipWithoutWorkbook()),
        throwsA(isA<ImportException>()),
      );
    });
  });
}
