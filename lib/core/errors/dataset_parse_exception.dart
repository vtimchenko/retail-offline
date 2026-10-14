/// Failure while reading or validating a JSON retail dataset.
///
/// [message] is written for a store employee (Ukrainian, no stack traces).
/// [technical] is for the debug console only.
sealed class DatasetParseException implements Exception {
  const DatasetParseException(this.message, {this.technical});

  final String message;
  final String? technical;

  @override
  String toString() =>
      '$runtimeType: $message'
      '${technical != null ? ' [$technical]' : ''}';
}

/// The text is not valid JSON.
final class JsonSyntaxException extends DatasetParseException {
  const JsonSyntaxException(
    super.message, {
    super.technical,
    required this.offset,
    required this.line,
    required this.column,
  });

  /// Zero-based index in the source string.
  final int offset;

  /// One-based line of [offset].
  final int line;

  /// One-based column of [offset].
  final int column;
}

/// The JSON is well formed, but the dataset rules reject it.
final class DatasetValidationException extends DatasetParseException {
  const DatasetValidationException(super.message, {super.technical});
}
