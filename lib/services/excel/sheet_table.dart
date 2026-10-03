import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import 'raw_sheet.dart';

/// A [RawSheet] viewed as a table: the first non-blank row is the header row
/// and columns are located by header name, so column order does not matter.
class SheetTable {
  SheetTable._(this.fileLabel, this._columns, this.dataRows);

  /// Builds the table, checking that every header in [requiredHeaders] exists
  /// (case-insensitive, surrounding whitespace ignored) and that at least one
  /// data row follows. Blank rows are ignored.
  ///
  /// Throws [ImportException] with a user-facing message.
  factory SheetTable.from(
    RawSheet sheet, {
    required String fileLabel,
    required List<String> requiredHeaders,
  }) {
    final nonBlank = sheet.rows.where((r) => !r.isBlank).toList();
    if (nonBlank.isEmpty) {
      throw ImportException(ImportMessages.emptySheet(fileLabel));
    }

    final headerRow = nonBlank.first;
    final columns = <String, int>{};
    headerRow.cells.forEach((index, cell) {
      final name = cell.value.trim().toLowerCase();
      if (name.isNotEmpty) columns.putIfAbsent(name, () => index);
    });

    final missing = [
      for (final h in requiredHeaders)
        if (!columns.containsKey(h.toLowerCase())) h,
    ];
    if (missing.isNotEmpty) {
      throw ImportException(
        ImportMessages.missingHeaders(fileLabel, missing),
        technical: 'Found headers: ${columns.keys.join(', ')}',
      );
    }

    final dataRows = nonBlank.skip(1).toList();
    if (dataRows.isEmpty) {
      throw ImportException(ImportMessages.noDataRows(fileLabel));
    }
    return SheetTable._(fileLabel, columns, dataRows);
  }

  final String fileLabel;
  final Map<String, int> _columns;

  /// Data rows (everything after the header, blank rows removed).
  final List<RawRow> dataRows;

  /// Reader of typed values for one [row].
  RowReader reader(RawRow row) => RowReader._(this, row);
}

/// Strict, typed access to the cells of one row. Every method throws
/// [ImportException] naming the file, the Excel row and the field.
class RowReader {
  RowReader._(this._table, this._row);

  final SheetTable _table;
  final RawRow _row;

  int get rowNumber => _row.number;

  String get _label => _table.fileLabel;

  RawCell? _cell(String field) {
    final column = _table._columns[field.toLowerCase()]!;
    return _row.cells[column];
  }

  /// Required free text, trimmed.
  String text(String field) {
    final cell = _cell(field);
    final value = cell == null ? '' : _plain(cell, field).trim();
    if (value.isEmpty) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    return value;
  }

  /// Required identifier (ProductID, OrderNumber, SerialNumber …) as a
  /// String with its exact digits.
  ///
  /// * text cell → trimmed text;
  /// * numeric cell → accepted only if it is a plain integer (`43848`, or
  ///   `43848.0` which normalizes to `43848`). Exponent notation or a
  ///   fraction means the exact original digits cannot be guaranteed, so the
  ///   value is rejected instead of guessed.
  String identifier(String field) {
    final cell = _cell(field);
    if (cell == null) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    final value = switch (cell.type) {
      RawCellType.text => cell.value.trim(),
      RawCellType.number => _exactIntegerText(cell.value, field),
      _ => throw ImportException(
        ImportMessages.invalidValue(_label, rowNumber, field),
      ),
    };
    if (value.isEmpty) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    return value;
  }

  /// Required phone number. Must be a text cell: a numeric cell would already
  /// have lost leading zeroes.
  String phone(String field) {
    final cell = _cell(field);
    if (cell != null && cell.type == RawCellType.number) {
      throw ImportException(
        ImportMessages.numericPhone(_label, rowNumber, field),
      );
    }
    return identifier(field);
  }

  /// Non-negative whole number.
  int quantity(String field, {bool allowZero = true}) {
    final cell = _cell(field);
    if (cell == null) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    final raw = switch (cell.type) {
      RawCellType.text || RawCellType.number => cell.value.trim(),
      _ => '',
    };
    final match = RegExp(r'^(\d{1,9})(?:\.0*)?$').firstMatch(raw);
    final value = match == null ? null : int.parse(match.group(1)!);
    if (value == null || (!allowZero && value == 0)) {
      throw ImportException(
        ImportMessages.invalidQuantity(_label, rowNumber, field),
      );
    }
    return value;
  }

  /// Money as integer minor units: `329.00` → `32900`, `329,5` → `32950`.
  /// Works on the text of the value, never on `double`. More than two
  /// decimals are rejected (trailing zeros such as `329.000` are fine).
  int money(String field) {
    final cell = _cell(field);
    if (cell == null) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    final raw = switch (cell.type) {
      RawCellType.text || RawCellType.number => cell.value.trim(),
      _ => '',
    };
    final match = RegExp(r'^(\d{1,12})(?:[.,](\d+))?$').firstMatch(raw);
    if (match == null) {
      throw ImportException(
        ImportMessages.invalidMoney(_label, rowNumber, field),
      );
    }
    final fraction = match.group(2) ?? '';
    if (fraction.length > 2 &&
        fraction.substring(2).replaceAll('0', '') != '') {
      throw ImportException(
        ImportMessages.invalidMoney(_label, rowNumber, field),
      );
    }
    final cents = int.parse(fraction.padRight(2, '0').substring(0, 2));
    return int.parse(match.group(1)!) * 100 + cents;
  }

  /// Date-time stored as `yyyyMMddHHmmss` (also `yyyyMMdd` or ISO-8601 text).
  DateTime dateTime(String field) {
    final cell = _cell(field);
    if (cell == null) {
      throw ImportException(
        ImportMessages.missingValue(_label, rowNumber, field),
      );
    }
    final raw = switch (cell.type) {
      RawCellType.text || RawCellType.number => cell.value.trim(),
      _ => '',
    };
    final result = _parseDate(raw);
    if (result == null) {
      throw ImportException(
        ImportMessages.invalidDate(_label, rowNumber, field),
      );
    }
    return result;
  }

  // ---- internals --------------------------------------------------------

  String _plain(RawCell cell, String field) => switch (cell.type) {
    RawCellType.text || RawCellType.number => cell.value,
    _ => throw ImportException(
      ImportMessages.invalidValue(_label, rowNumber, field),
    ),
  };

  String _exactIntegerText(String raw, String field) {
    final value = raw.trim();
    final match = RegExp(r'^(\d+)(?:\.0*)?$').firstMatch(value);
    if (match == null) {
      throw ImportException(
        ImportMessages.unsafeIdentifier(_label, rowNumber, field),
        technical: 'Numeric identifier "$value" is not a plain integer',
      );
    }
    return match.group(1)!;
  }

  static DateTime? _parseDate(String raw) {
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:(\d{2})(\d{2})(\d{2}))?$')
        .firstMatch(raw);
    if (compact != null) {
      int g(int i) => int.parse(compact.group(i) ?? '0');
      final y = g(1), mo = g(2), d = g(3), h = g(4), mi = g(5), s = g(6);
      final date = DateTime(y, mo, d, h, mi, s);
      final valid =
          date.year == y &&
          date.month == mo &&
          date.day == d &&
          date.hour == h &&
          date.minute == mi &&
          date.second == s;
      return valid ? date : null;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
