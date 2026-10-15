import '../fulfilment_repository.dart';

/// Names of the production IndexedDB database and its four stores.
///
/// Tests must pass their own [databaseName]. They must not open or delete
/// [productionDatabaseName].
abstract final class IndexedDbFulfilmentSchema {
  /// Database opened by the production repository.
  static const String productionDatabaseName = 'retail-offline';

  /// IndexedDB database version. Record schema is stored separately.
  static const int databaseVersion = 1;

  /// Out-of-line key used by every store.
  static const String currentKey = 'current';

  static const String dataset = 'dataset';
  static const String session = 'session';
  static const String exports = 'exports';
  static const String metadata = 'metadata';

  static const List<String> stores = [dataset, session, exports, metadata];

  static const String schemaVersionField = 'schemaVersion';
  static const String bytesField = 'bytes';
  static const String fingerprintField = 'fingerprint';
  static const String snapshotField = 'snapshot';
  static const String filenameField = 'filename';
  static const String dateCreateField = 'dateCreate';
  static const String digestField = 'digest';
  static const String revisionField = 'revision';

  static const Set<String> datasetFields = {
    schemaVersionField,
    bytesField,
    fingerprintField,
  };
  static const Set<String> sessionFields = {schemaVersionField, snapshotField};
  static const Set<String> exportFields = {
    schemaVersionField,
    filenameField,
    dateCreateField,
    bytesField,
    digestField,
  };
  static const Set<String> metadataFields = {
    schemaVersionField,
    revisionField,
    fingerprintField,
  };

  /// Canonical decimal text for a safe revision.
  ///
  /// The text is what IndexedDB stores. It is never a JavaScript number.
  static String revisionText(int revision) {
    if (!StorageRevision.isSafe(revision)) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Outside the safe range.',
      );
    }
    return revision.toString();
  }

  /// Reads a stored revision.
  ///
  /// Leading zeros, zero, and values above [StorageRevision.maximum] are
  /// rejected. The text is not parsed until its length shows it is safe.
  static int? tryParseRevision(String? text) {
    if (text == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(text)) return null;
    const maximum = '9007199254740991';
    if (text.length > maximum.length) return null;
    if (text.length == maximum.length && text.compareTo(maximum) > 0) {
      return null;
    }
    return int.parse(text);
  }

  /// Classifies a stored schema version.
  ///
  /// A canonical integer other than [FulfilmentStorageSchema.current] is
  /// unsupported. Any other token is malformed.
  static IndexedDbSchemaKind schemaKind(String? text) {
    if (text == null || !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(text)) {
      return IndexedDbSchemaKind.malformed;
    }
    if (text == '${FulfilmentStorageSchema.current}') {
      return IndexedDbSchemaKind.current;
    }
    return IndexedDbSchemaKind.unsupported;
  }
}

/// How a stored schema version token should be treated.
enum IndexedDbSchemaKind { current, unsupported, malformed }
