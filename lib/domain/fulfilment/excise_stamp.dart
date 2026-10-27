/// Canonical excise stamp `AAAA999999`.
///
/// The first four characters are Latin letters `A`–`Z`. The last six are
/// digits. Lowercase Latin letters are accepted by [normalize] and stored
/// in uppercase. Cyrillic letters, spaces, and any other length are rejected.
abstract final class ExciseStamp {
  static final RegExp _pattern = RegExp(r'^[A-Z]{4}[0-9]{6}$');

  /// Whether [value] is already a canonical stamp.
  ///
  /// Lowercase input is not canonical. Call [normalize] first.
  static bool isValid(String value) => _pattern.hasMatch(value);

  /// Returns the canonical stamp, or `null` when [value] cannot be one.
  ///
  /// Only ASCII `a`–`z` are uppercased. The length must stay 10 characters,
  /// so a character whose uppercase form grows is rejected. Surrounding
  /// spaces are not removed.
  static String? normalize(String value) {
    if (value.length != 10) return null;
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if (code >= 0x61 && code <= 0x7A) {
        buffer.writeCharCode(code - 0x20);
      } else {
        buffer.writeCharCode(code);
      }
    }
    final canonical = buffer.toString();
    if (canonical.length != 10 || !_pattern.hasMatch(canonical)) return null;
    return canonical;
  }
}
