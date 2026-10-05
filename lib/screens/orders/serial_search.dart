import '../../models/serial_selection.dart';

/// In-memory filtering of the available serial rows.
///
/// Matching is a partial [String.contains] on the serial text. Stored
/// serials are never modified.
abstract final class SerialSearch {
  /// Returns rows whose serial contains the trimmed [query], in order.
  ///
  /// A blank query does not filter. Comparison is case-sensitive. Address
  /// is not matched.
  static List<AvailableSerial> filter(
    List<AvailableSerial> rows,
    String query,
  ) {
    final serialQuery = query.trim();
    if (serialQuery.isEmpty) return rows;
    return [
      for (final row in rows)
        if (row.serialNumber.contains(serialQuery)) row,
    ];
  }
}
