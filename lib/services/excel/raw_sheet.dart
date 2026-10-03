import 'package:flutter/foundation.dart';

/// Kind of value stored in a [RawCell].
enum RawCellType {
  /// Text (shared string, inline string, string formula result, ISO date).
  text,

  /// Number. [RawCell.value] is the VERBATIM text from the XLSX file; it has
  /// not been converted through `int` or `double`.
  number,

  /// Boolean (`true` / `false` in [RawCell.value]).
  boolean,

  /// Excel error such as `#N/A`.
  error,
}

/// A non-empty cell as stored in the file. This is the only cell abstraction
/// the parsers see; it does not expose any XLSX/XML details.
@immutable
class RawCell {
  const RawCell(this.type, this.value);

  const RawCell.text(String value) : this(RawCellType.text, value);

  const RawCell.number(String value) : this(RawCellType.number, value);

  final RawCellType type;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is RawCell && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'RawCell(${type.name}, $value)';
}

/// A worksheet row. Blank cells are absent from [cells].
class RawRow {
  RawRow(this.number, this.cells);

  /// Excel row number (1-based), as the user sees it in Excel.
  final int number;

  /// Zero-based column index → cell.
  final Map<int, RawCell> cells;

  /// True if every cell is missing or whitespace-only text.
  bool get isBlank => cells.values.every(
    (c) => c.type == RawCellType.text && c.value.trim().isEmpty,
  );
}

/// Contents of one worksheet.
class RawSheet {
  RawSheet(this.rows);

  /// Rows in file order. Rows without any cells are not included.
  final List<RawRow> rows;
}
