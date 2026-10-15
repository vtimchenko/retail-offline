import 'dart:typed_data';

/// VM stand-in for [IndexedDbProbe]. Browser tests never call it.
class IndexedDbProbe {
  const IndexedDbProbe(this.databaseName);

  final String databaseName;

  Future<void> deleteDatabase() async => _refuse();

  Future<List<String>> storeNames() async => _refuse();

  Future<Map<String, Object>?> read(String store) async => _refuse();

  Future<void> write(String store, Map<String, Object> record) async =>
      _refuse();

  Future<void> deleteRecord(String store) async => _refuse();

  Future<void> createDatabaseVersion(int version) async => _refuse();

  Never _refuse() {
    throw UnsupportedError('IndexedDB is only available in the browser.');
  }
}

/// Guards a name before any browser call.
void requireTestDatabase(String name) {
  if (name == 'retail-offline' || !name.startsWith('retail-offline-test-')) {
    throw StateError('Refusing to touch database "$name".');
  }
}

/// Copies a binary field out of a probe record.
Uint8List probeBytes(Map<String, Object> record, String field) {
  final value = record[field];
  if (value is! Uint8List) {
    throw StateError('$field was ${value.runtimeType}.');
  }
  return value;
}

/// Reads a text field out of a probe record.
String probeText(Map<String, Object> record, String field) {
  final value = record[field];
  if (value is! String) {
    throw StateError('$field was ${value.runtimeType}.');
  }
  return value;
}
