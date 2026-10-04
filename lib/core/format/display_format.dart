/// Formats domain values for the UI without changing the stored data.
///
/// Money stays in integer minor units. These helpers only build display text.
abstract final class DisplayFormat {
  /// Formats [minorUnits] as `whole,fraction` with two fraction digits.
  ///
  /// `32900` becomes `329,00`. Uses integer arithmetic only, so the displayed
  /// amount is the stored value rather than a recalculated price × quantity.
  static String formatMoney(int minorUnits) {
    final sign = minorUnits < 0 ? '-' : '';
    final absolute = minorUnits.abs();
    final whole = absolute ~/ 100;
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    return '$sign$whole,$fraction';
  }

  /// Formats [date] as `dd.MM.yyyy HH:mm` from its local calendar fields.
  ///
  /// Seconds remain on [date] and are omitted from the label.
  static String formatInvoiceDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
