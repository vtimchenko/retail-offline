import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import 'raw_sheet.dart';

/// Reads the first worksheet of an `.xlsx` workbook into a [RawSheet].
///
/// This is the ONLY place that knows about the XLSX container (ZIP + XML).
/// Everything else works with [RawSheet].
///
/// Why a custom reader: cell values are exposed as verbatim text. Numeric
/// cells are never converted through `int`/`double` here, so large
/// identifiers (19-digit product ids) cannot lose precision, including in
/// JavaScript where all numbers are 64-bit floats.
///
/// Supported: shared strings (also rich text), inline strings, numbers,
/// booleans, errors, cached formula results, ISO date cells, a missing
/// `styles.xml`, and worksheet lookup through the package relationships.
/// Not supported (not needed): writing, styles, dates as serial numbers.
class ExcelImportService {
  const ExcelImportService();

  static const String _defaultWorkbookPath = 'xl/workbook.xml';

  /// Cheap structural check used right after a file is chosen: the bytes are
  /// a ZIP package with a workbook part. Throws [ImportException] otherwise.
  void verifyWorkbook(Uint8List bytes) {
    final archive = _openArchive(bytes);
    _workbookPath(archive); // throws if there is no workbook
  }

  /// Reads the first worksheet. The sheet name is irrelevant. Throws
  /// [ImportException] with a user-facing message for any structural problem.
  RawSheet readFirstSheet(Uint8List bytes) {
    final archive = _openArchive(bytes);
    try {
      final workbookPath = _workbookPath(archive);
      final sheetPath = _firstWorksheetPath(archive, workbookPath);
      final shared = _readSharedStrings(archive, workbookPath);
      return _readSheet(archive, sheetPath, shared);
    } on ImportException {
      rethrow;
    } on Object catch (e, st) {
      debugPrint('XLSX read failed: $e\n$st');
      throw ImportException(
        ImportMessages.worksheetCorrupted,
        technical: 'Unexpected error while reading XLSX',
        cause: e,
      );
    }
  }

  // ---- Package ----------------------------------------------------------

  Archive _openArchive(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const ImportException(
        ImportMessages.notXlsxContent,
        technical: 'No ZIP signature',
      );
    }
    try {
      return ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      debugPrint('ZIP decode failed: $e');
      throw ImportException(
        ImportMessages.workbookUnreadable,
        technical: 'ZIP decode failed',
        cause: e,
      );
    }
  }

  /// Path of the main workbook part, from the package relationships with a
  /// fallback to the conventional location.
  String _workbookPath(Archive archive) {
    final relsFile = archive.findFile('_rels/.rels');
    if (relsFile != null) {
      for (final rel in _relationships(_parse(relsFile))) {
        if (rel.type.endsWith('/officeDocument')) {
          final path = _resolve('', rel.target);
          if (archive.findFile(path) != null) return path;
        }
      }
    }
    if (archive.findFile(_defaultWorkbookPath) != null) {
      return _defaultWorkbookPath;
    }
    throw const ImportException(
      ImportMessages.workbookMissing,
      technical: 'No workbook part',
    );
  }

  String _firstWorksheetPath(Archive archive, String workbookPath) {
    final workbook = _parse(archive.findFile(workbookPath)!);
    final sheetsElement = _child(workbook.rootElement, 'sheets');
    final sheets = sheetsElement == null
        ? const <XmlElement>[]
        : _children(sheetsElement, 'sheet').toList();
    if (sheets.isEmpty) {
      throw const ImportException(ImportMessages.workbookNoSheets);
    }

    final dir = _directory(workbookPath);
    final relsFile = archive.findFile(
      '${dir.isEmpty ? '' : '$dir/'}_rels/${_fileName(workbookPath)}.rels',
    );
    final rels = relsFile == null
        ? const <_Relationship>[]
        : _relationships(_parse(relsFile));

    for (final sheet in sheets) {
      final rid = _attributeByLocalName(sheet, 'id');
      if (rid == null) continue;
      for (final rel in rels) {
        if (rel.id == rid && rel.type.endsWith('/worksheet')) {
          final path = _resolve(dir, rel.target);
          if (archive.findFile(path) != null) return path;
        }
      }
    }
    throw const ImportException(
      ImportMessages.worksheetMissing,
      technical: 'No worksheet relationship resolved',
    );
  }

  // ---- Shared strings ---------------------------------------------------

  List<String> _readSharedStrings(Archive archive, String workbookPath) {
    final dir = _directory(workbookPath);
    final relsFile = archive.findFile(
      '${dir.isEmpty ? '' : '$dir/'}_rels/${_fileName(workbookPath)}.rels',
    );
    String? path;
    if (relsFile != null) {
      for (final rel in _relationships(_parse(relsFile))) {
        if (rel.type.endsWith('/sharedStrings')) {
          path = _resolve(dir, rel.target);
          break;
        }
      }
    }
    path ??= '${dir.isEmpty ? '' : '$dir/'}sharedStrings.xml';
    final file = archive.findFile(path);
    if (file == null) return const <String>[];

    final result = <String>[];
    for (final si in _children(_parse(file).rootElement, 'si')) {
      result.add(_richText(si));
    }
    return result;
  }

  /// Concatenates every `<t>` of an `<si>`/`<is>` element (plain text and
  /// rich-text runs) and ignores phonetic hints (`<rPh>`).
  String _richText(XmlElement element) {
    final buffer = StringBuffer();
    void walk(XmlElement e) {
      for (final child in e.childElements) {
        switch (child.name.local) {
          case 't':
            buffer.write(child.innerText);
          case 'r':
            walk(child);
          // rPh (phonetic) and others are intentionally skipped.
        }
      }
    }

    walk(element);
    return buffer.toString();
  }

  // ---- Worksheet --------------------------------------------------------

  RawSheet _readSheet(Archive archive, String path, List<String> shared) {
    final root = _parse(archive.findFile(path)!).rootElement;
    final sheetData = _child(root, 'sheetData');
    final rows = <RawRow>[];
    if (sheetData == null) return RawSheet(rows);

    var previousRowNumber = 0;
    for (final rowElement in _children(sheetData, 'row')) {
      final rowNumber =
          int.tryParse(rowElement.getAttribute('r') ?? '') ??
          previousRowNumber + 1;
      previousRowNumber = rowNumber;

      final cells = <int, RawCell>{};
      var previousColumn = -1;
      for (final c in _children(rowElement, 'c')) {
        final column = _columnIndex(c.getAttribute('r')) ?? previousColumn + 1;
        previousColumn = column;
        final cell = _readCell(c, shared, rowNumber);
        if (cell != null) cells[column] = cell;
      }
      if (cells.isNotEmpty) rows.add(RawRow(rowNumber, cells));
    }
    return RawSheet(rows);
  }

  RawCell? _readCell(XmlElement c, List<String> shared, int rowNumber) {
    final type = c.getAttribute('t');
    if (type == 'inlineStr') {
      final inline = _child(c, 'is');
      if (inline == null) return null;
      final text = _richText(inline);
      return text.isEmpty ? null : RawCell.text(text);
    }

    final v = _child(c, 'v');
    if (v == null) return null; // blank, or a formula without cached result
    final raw = v.innerText;

    switch (type) {
      case 's':
        final index = int.tryParse(raw.trim());
        if (index == null || index < 0 || index >= shared.length) {
          throw ImportException(
            ImportMessages.worksheetCorrupted,
            technical: 'Bad shared string index "$raw" in row $rowNumber',
          );
        }
        final text = shared[index];
        return text.isEmpty ? null : RawCell.text(text);
      case 'str':
      case 'd':
        return raw.isEmpty ? null : RawCell.text(raw);
      case 'b':
        return RawCell(
          RawCellType.boolean,
          raw.trim() == '1' ? 'true' : 'false',
        );
      case 'e':
        return RawCell(RawCellType.error, raw);
      case null:
      case 'n':
        final number = raw.trim();
        return number.isEmpty ? null : RawCell.number(number);
      default:
        throw ImportException(
          ImportMessages.worksheetCorrupted,
          technical: 'Unknown cell type "$type" in row $rowNumber',
        );
    }
  }

  // ---- Helpers ----------------------------------------------------------

  XmlDocument _parse(ArchiveFile file) {
    var text = utf8.decode(
      file.readBytes() ?? Uint8List(0),
      allowMalformed: true,
    );
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // BOM
    }
    try {
      return XmlDocument.parse(text);
    } on XmlException catch (e) {
      throw ImportException(
        ImportMessages.worksheetCorrupted,
        technical: 'Invalid XML in ${file.name}',
        cause: e,
      );
    }
  }

  Iterable<XmlElement> _children(XmlElement parent, String localName) =>
      parent.childElements.where((e) => e.name.local == localName);

  XmlElement? _child(XmlElement parent, String localName) {
    for (final e in parent.childElements) {
      if (e.name.local == localName) return e;
    }
    return null;
  }

  String? _attributeByLocalName(XmlElement e, String localName) {
    for (final a in e.attributes) {
      if (a.name.local == localName) return a.value;
    }
    return null;
  }

  Iterable<_Relationship> _relationships(XmlDocument doc) sync* {
    for (final rel in _children(doc.rootElement, 'Relationship')) {
      final id = rel.getAttribute('Id');
      final type = rel.getAttribute('Type');
      final target = rel.getAttribute('Target');
      if (id != null && type != null && target != null) {
        yield _Relationship(id, type, target);
      }
    }
  }

  /// `A` → 0, `B` → 1, `AA` → 26 from a reference such as `AB12`.
  int? _columnIndex(String? reference) {
    if (reference == null) return null;
    var index = 0;
    var letters = 0;
    for (final unit in reference.codeUnits) {
      if (unit >= 65 && unit <= 90) {
        index = index * 26 + (unit - 64);
        letters++;
      } else if (unit >= 97 && unit <= 122) {
        index = index * 26 + (unit - 96);
        letters++;
      } else {
        break;
      }
    }
    return letters == 0 ? null : index - 1;
  }

  String _directory(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  String _fileName(String path) => path.substring(path.lastIndexOf('/') + 1);

  /// Resolves a relationship [target] relative to [baseDir] inside the ZIP.
  String _resolve(String baseDir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = <String>[if (baseDir.isNotEmpty) ...baseDir.split('/')];
    for (final segment in target.split('/')) {
      if (segment == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (segment.isNotEmpty && segment != '.') {
        parts.add(segment);
      }
    }
    return parts.join('/');
  }
}

class _Relationship {
  const _Relationship(this.id, this.type, this.target);

  final String id;
  final String type;
  final String target;
}
