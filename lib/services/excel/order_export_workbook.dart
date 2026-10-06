import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/order.dart';
import '../../models/order_export.dart';
import '../../models/serial_selection.dart';
import '../../repositories/serial_selection_repository.dart';

/// Thrown when a fulfilment workbook cannot be written.
class OrderExportException implements Exception {
  const OrderExportException(this.message);

  final String message;

  @override
  String toString() => 'OrderExportException: $message';
}

/// Download name `{idStore}_{InvoiceNumber}_{OrderNumber}.xlsx`.
///
/// Each component replaces `\` `/` `:` `*` `?` `"` `<` `>` `|` and ASCII
/// controls (`U+0000`–`U+001F` and `U+007F`) with `_`. Letters, digits,
/// spaces and existing underscores stay. The strings written into the
/// workbook are not passed through this function.
String orderExportFileName({
  required String idStore,
  required String invoiceNumber,
  required String orderNumber,
}) {
  return '${_sanitizeFileComponent(idStore)}_'
      '${_sanitizeFileComponent(invoiceNumber)}_'
      '${_sanitizeFileComponent(orderNumber)}.xlsx';
}

/// Writes one order's fulfilment workbook as `.xlsx` bytes.
abstract final class OrderExportWorkbook {
  static const List<String> columns = [
    'idStore',
    'InvoiceNumber',
    'OrderNumber',
    'ProductID',
    'Address',
    'SerialNumber',
    'Quantity',
  ];

  /// Builds the workbook for [order] from reservations in [selections].
  ///
  /// Identifiers are inline strings copied from the Dart [String] values.
  /// [SelectedSerial.quantity] is one integer cell. One selected slot is one
  /// row, in [Order.items] order and then
  /// [SerialSelectionRepository.selectedFor] order. [idStore] is the selected
  /// store id.
  static OrderExport build({
    required String idStore,
    required Order order,
    required SerialSelectionRepository selections,
  }) {
    final rows = <List<Object>>[
      columns,
      for (final item in order.items)
        for (final slot in selections.selectedFor(
          orderNumber: order.orderNumber,
          productId: item.productId,
        ))
          [
            idStore,
            order.invoiceNumber,
            order.orderNumber,
            item.productId,
            slot.address,
            slot.serialNumber,
            slot.quantity,
          ],
    ];
    return OrderExport(
      orderNumber: order.orderNumber,
      filename: orderExportFileName(
        idStore: idStore,
        invoiceNumber: order.invoiceNumber,
        orderNumber: order.orderNumber,
      ),
      bytes: _package(_sheetXml(rows)),
    );
  }
}

const String _spreadsheetNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

String _sheetXml(List<List<Object>> rows) {
  final buffer = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="$_spreadsheetNs"><sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    final rowNumber = r + 1;
    buffer.write('<row r="$rowNumber">');
    for (var c = 0; c < rows[r].length; c++) {
      final ref = '${_columnName(c)}$rowNumber';
      final value = rows[r][c];
      if (value is int) {
        buffer.write('<c r="$ref"><v>$value</v></c>');
      } else {
        buffer.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
          '${_xmlText(value as String)}</t></is></c>',
        );
      }
    }
    buffer.write('</row>');
  }
  buffer.write('</sheetData></worksheet>');
  final xml = buffer.toString();
  XmlDocument.parse(xml);
  return xml;
}

Uint8List _package(String sheetXml) {
  final archive = Archive();
  void add(String name, String content) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="$_spreadsheetNs" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>',
  );
  add('xl/worksheets/sheet1.xml', sheetXml);
  return ZipEncoder().encodeBytes(archive);
}

String _columnName(int index) {
  var n = index + 1;
  final letters = <String>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters.add(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  return letters.reversed.join();
}

String _xmlText(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (_illegalXml(rune)) {
      throw const OrderExportException(
        'An identifier contains a character that cannot be stored in Excel.',
      );
    }
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3C:
        buffer.write('&lt;');
      case 0x3E:
        buffer.write('&gt;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

bool _illegalXml(int rune) {
  if (rune <= 0x08) return true;
  if (rune == 0x0B || rune == 0x0C) return true;
  if (rune >= 0x0E && rune <= 0x1F) return true;
  if (rune >= 0xD800 && rune <= 0xDFFF) return true;
  if (rune == 0xFFFE || rune == 0xFFFF) return true;
  return false;
}

String _sanitizeFileComponent(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    buffer.write(_unsafeInFileName(rune) ? '_' : String.fromCharCode(rune));
  }
  return buffer.toString();
}

bool _unsafeInFileName(int rune) {
  if (rune <= 0x1F || rune == 0x7F) return true;
  return const [
    0x5C, // \
    0x2F, // /
    0x3A, // :
    0x2A, // *
    0x3F, // ?
    0x22, // "
    0x3C, // <
    0x3E, // >
    0x7C, // |
  ].contains(rune);
}
