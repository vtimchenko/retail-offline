/// Failure while acquiring, reading or validating an import file.
///
/// [message] is written for a store employee (Ukrainian, no stack traces) and
/// can be shown in the UI as is. [technical] and [cause] are for the debug
/// console only.
class ImportException implements Exception {
  const ImportException(this.message, {this.technical, this.cause});

  final String message;
  final String? technical;
  final Object? cause;

  @override
  String toString() =>
      'ImportException: $message'
      '${technical != null ? ' [$technical]' : ''}'
      '${cause != null ? ' (cause: $cause)' : ''}';
}
