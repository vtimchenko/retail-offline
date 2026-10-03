import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A numeric cell with its VERBATIM text (`<v>` content), e.g.
/// `XlsxNumber('1.29E+18')`.
class XlsxNumber {
  const XlsxNumber(this.raw);
  final String raw;
}

/// A cell stored as an inline string (`t="inlineStr"`).
class XlsxInline {
  const XlsxInline(this.text);
  final String text;
}

/// A shared string made of several rich-text runs, plus a phonetic hint that
/// must be ignored.
class XlsxRich {
  const XlsxRich(this.runs);
  final List<String> runs;
}

/// A formula cell with a cached string result.
class XlsxFormulaText {
  const XlsxFormulaText(this.cached);
  final String cached;
}

/// A formula cell with a cached numeric result.
class XlsxFormulaNumber {
  const XlsxFormulaNumber(this.cached);
  final String cached;
}

/// Builds a minimal `.xlsx` in memory. Cell values:
///
/// * `String` → shared string;
/// * [XlsxNumber], [XlsxInline], [XlsxRich], [XlsxFormulaText],
///   [XlsxFormulaNumber];
/// * `bool` → boolean cell;
/// * `null` → blank (no cell written).
///
/// Used instead of binary fixtures so the repository contains no real data.
Uint8List buildXlsx(
  List<List<Object?>> rows, {
  String sheetName = 'Аркуш1',
  bool includeStyles = true,
  bool includeSharedStringsPart = true,

  /// Put these rows into extra sheets listed AFTER the first one. The first
  /// sheet is stored in `sheet2.xml` to prove it is resolved through
  /// relationships and not by file name.
  List<List<List<Object?>>> extraSheets = const [],

  /// Explicit Excel row numbers (to emulate skipped rows).
  List<int>? rowNumbers,
}) {
  final shared = <String>[];
  final sharedIndex = <String, int>{};
  int sharedOf(String xmlItem) => sharedIndex.putIfAbsent(xmlItem, () {
    shared.add(xmlItem);
    return shared.length - 1;
  });

  String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String t(String s) => '<t xml:space="preserve">${escape(s)}</t>';

  String sheetXml(List<List<Object?>> data, {List<int>? numbers}) {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>',
    );
    for (var r = 0; r < data.length; r++) {
      final rowNumber = numbers != null ? numbers[r] : r + 1;
      b.write('<row r="$rowNumber">');
      for (var c = 0; c < data[r].length; c++) {
        final v = data[r][c];
        if (v == null) continue;
        final ref = '${_columnName(c)}$rowNumber';
        switch (v) {
          case String():
            b.write(
              '<c r="$ref" t="s"><v>${sharedOf('<si>${t(v)}</si>')}</v></c>',
            );
          case XlsxNumber():
            b.write('<c r="$ref"><v>${v.raw}</v></c>');
          case XlsxInline():
            b.write('<c r="$ref" t="inlineStr"><is>${t(v.text)}</is></c>');
          case XlsxRich():
            final si =
                '<si>${v.runs.map((x) => '<r><rPr><b/></rPr>${t(x)}</r>').join()}'
                '<rPh sb="0" eb="1"><t>ignored-phonetic</t></rPh></si>';
            b.write('<c r="$ref" t="s"><v>${sharedOf(si)}</v></c>');
          case XlsxFormulaText():
            b.write(
              '<c r="$ref" t="str"><f>A1</f><v>${escape(v.cached)}</v></c>',
            );
          case XlsxFormulaNumber():
            b.write('<c r="$ref"><f>1+1</f><v>${v.cached}</v></c>');
          case bool():
            b.write('<c r="$ref" t="b"><v>${v ? 1 : 0}</v></c>');
          default:
            throw ArgumentError('Unsupported cell value: $v');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  final archive = Archive();
  void add(String name, String content) =>
      archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));

  // First sheet is stored in sheet2.xml when there are extra sheets or not -
  // always, to exercise relationship resolution.
  final firstSheetXml = sheetXml(rows, numbers: rowNumbers);
  final extraXml = [for (final s in extraSheets) sheetXml(s)];

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );

  final sheetsXml = StringBuffer(
    '<sheet name="${escape(sheetName)}" sheetId="1" r:id="rId1"/>',
  );
  final rels = StringBuffer(
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>',
  );
  for (var i = 0; i < extraXml.length; i++) {
    final id = 'rId${10 + i}';
    sheetsXml.write(
      '<sheet name="Extra${i + 1}" sheetId="${i + 2}" r:id="$id"/>',
    );
    rels.write(
      '<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 3}.xml"/>',
    );
  }
  if (includeStyles) {
    rels.write(
      '<Relationship Id="rId90" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
  }
  if (includeSharedStringsPart) {
    rels.write(
      '<Relationship Id="rId91" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>',
    );
  }

  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheetsXml</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>',
  );
  add('xl/worksheets/sheet2.xml', firstSheetXml);
  for (var i = 0; i < extraXml.length; i++) {
    add('xl/worksheets/sheet${i + 3}.xml', extraXml[i]);
  }
  if (includeStyles) {
    add(
      'xl/styles.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<fonts count="1"><font><sz val="11"/></font></fonts>'
          '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
          '<borders count="1"><border/></borders>'
          '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
          '<cellXfs count="1"><xf/></cellXfs></styleSheet>',
    );
  }
  if (includeSharedStringsPart) {
    add(
      'xl/sharedStrings.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'count="${shared.length}" uniqueCount="${shared.length}">${shared.join()}</sst>',
    );
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A workbook that has the ZIP structure but no workbook part.
Uint8List buildZipWithoutWorkbook() {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('hello')));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _columnName(int index) {
  var n = index + 1;
  final out = StringBuffer();
  final letters = <String>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters.add(String.fromCharCode(65 + rem));
    n = (n - 1) ~/ 26;
  }
  out.writeAll(letters.reversed);
  return out.toString();
}
