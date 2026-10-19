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

  static final RegExp _phoneNoise = RegExp(r'[+\s()\-]');

  /// Formats a Ukrainian mobile number as `(0XX) XXX-XX-XX`.
  ///
  /// Accepts a 10-digit national number starting with `0`, or the same
  /// number with country code `380`. Spaces, brackets, hyphens and a
  /// leading `+` are ignored only while recognizing the number. Any other
  /// value is returned unchanged, including its leading zeros.
  static final RegExp _digits = RegExp(r'^\d+$');

  static String formatPhone(String value) {
    final compact = value.replaceAll(_phoneNoise, '');
    if (!_digits.hasMatch(compact)) return value;
    if (compact.length == 10 && compact.startsWith('0')) {
      return _nationalPhone(compact);
    }
    if (compact.length == 12 && compact.startsWith('380')) {
      return _nationalPhone('0${compact.substring(3)}');
    }
    return value;
  }

  static String _nationalPhone(String national) {
    return '(${national.substring(0, 3)}) '
        '${national.substring(3, 6)}-'
        '${national.substring(6, 8)}-'
        '${national.substring(8)}';
  }
}
