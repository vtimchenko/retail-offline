import 'package:flutter/foundation.dart';

import '../../domain/fulfilment/fulfilment_session.dart';
import '../../services/json/cumulative_json_export.dart';
import '../dataset_fingerprint.dart';
import '../export_consistency.dart';
import '../fulfilment_repository.dart';
import '../session_snapshot_codec.dart';
import 'indexeddb_fulfilment_schema.dart';

/// One field copied out of an IndexedDB record.
///
/// Text and bytes stay in Dart. A JavaScript number or other value is
/// [IndexedDbField.unexpected] so it is never coerced.
@immutable
class IndexedDbField {
  /// A string field.
  const IndexedDbField.text(this.text) : bytes = null, unexpected = false;

  /// A binary field copied out of a `Uint8Array`.
  const IndexedDbField.bytes(Uint8List value) : this._(bytes: value);

  /// A value this schema does not store, such as a JavaScript number.
  const IndexedDbField.unexpected() : this._(unexpected: true);

  const IndexedDbField._({this.text, this.bytes, this.unexpected = false});

  /// String value, when this field was text.
  final String? text;

  /// Copied bytes, when this field was binary.
  final Uint8List? bytes;

  /// Whether the stored value had an unexpected JavaScript type.
  final bool unexpected;
}

/// One object read from an IndexedDB store.
///
/// A missing key is represented by a null record, not by an empty object.
@immutable
class IndexedDbRecord {
  /// Creates a record.
  ///
  /// [unexpectedKeys] is set when the object has a field this store does
  /// not define, or lacks one it requires. [schemaVersion] is still read
  /// so an unsupported version can be reported before the shape error.
  const IndexedDbRecord({required this.fields, required this.unexpectedKeys});

  /// Fields that had a recognized name.
  final Map<String, IndexedDbField> fields;

  /// Whether the object's keys are not exactly the keys for its store.
  final bool unexpectedKeys;

  /// The `schemaVersion` field, including an unexpected JavaScript type.
  IndexedDbField? get schemaVersion =>
      fields[IndexedDbFulfilmentSchema.schemaVersionField];
}

/// Restores a [LoadResult] from records already copied out of IndexedDB.
///
/// This does not open a database and does not delete records. An unsupported
/// schema version is reported before a shape or content failure.
LoadResult interpretIndexedDbRecords({
  IndexedDbRecord? dataset,
  IndexedDbRecord? session,
  IndexedDbRecord? export,
  IndexedDbRecord? metadata,
  DatasetByteRestore datasets = const DatasetByteRestore(),
  SessionSnapshotCodec snapshots = const SessionSnapshotCodec(),
}) {
  if (dataset == null &&
      session == null &&
      export == null &&
      metadata == null) {
    return const LoadEmpty();
  }
  if (dataset == null || session == null || metadata == null) {
    return const LoadCorrupted();
  }

  final schemas = [
    _schemaKind(dataset),
    _schemaKind(session),
    _schemaKind(metadata),
    if (export != null) _schemaKind(export),
  ];
  if (schemas.contains(IndexedDbSchemaKind.unsupported)) {
    return const LoadUnsupportedVersion();
  }
  if (schemas.contains(IndexedDbSchemaKind.malformed)) {
    return const LoadCorrupted();
  }
  if (dataset.unexpectedKeys ||
      session.unexpectedKeys ||
      metadata.unexpectedKeys ||
      (export?.unexpectedKeys ?? false)) {
    return const LoadCorrupted();
  }

  final bytes = _bytes(dataset, IndexedDbFulfilmentSchema.bytesField);
  final fingerprint = _text(
    dataset,
    IndexedDbFulfilmentSchema.fingerprintField,
  );
  if (bytes == null || fingerprint == null) return const LoadCorrupted();
  final restoredDataset = datasets.restore(
    bytes: bytes,
    expectedFingerprint: fingerprint,
  );
  if (restoredDataset is! DatasetRestored) return const LoadCorrupted();

  final metadataFingerprint = _text(
    metadata,
    IndexedDbFulfilmentSchema.fingerprintField,
  );
  final revision = IndexedDbFulfilmentSchema.tryParseRevision(
    _text(metadata, IndexedDbFulfilmentSchema.revisionField),
  );
  if (metadataFingerprint != fingerprint || revision == null) {
    return const LoadCorrupted();
  }

  final snapshotText = _text(session, IndexedDbFulfilmentSchema.snapshotField);
  if (snapshotText == null) return const LoadCorrupted();
  final decoded = snapshots.decode(snapshotText);
  if (decoded is SnapshotDecodeRejected) {
    return decoded.reason == SnapshotDecodeReason.unsupportedVersion
        ? const LoadUnsupportedVersion()
        : const LoadCorrupted();
  }
  if (decoded is! SnapshotDecoded) return const LoadCorrupted();
  final restoredSession = FulfilmentSession.restore(
    dataset: restoredDataset.dataset,
    snapshot: decoded.snapshot,
    expectedFingerprint: fingerprint,
  );
  if (restoredSession is! SessionRestored) return const LoadCorrupted();

  final storedExport = _export(export);
  if (export != null && storedExport == null) return const LoadCorrupted();
  if (!ExportConsistency.matches(
    dataset: restoredDataset.dataset,
    fingerprint: fingerprint,
    snapshot: decoded.snapshot,
    document: storedExport?.document,
    digest: storedExport?.digest,
  )) {
    return const LoadCorrupted();
  }

  return LoadReady(
    PersistedFulfilment(
      dataset: restoredDataset.dataset,
      session: restoredSession.session,
      revision: revision,
      fingerprint: fingerprint,
      export: storedExport?.document,
    ),
  );
}

IndexedDbSchemaKind _schemaKind(IndexedDbRecord record) {
  final field = record.schemaVersion;
  if (field == null || field.unexpected || field.text == null) {
    return IndexedDbSchemaKind.malformed;
  }
  return IndexedDbFulfilmentSchema.schemaKind(field.text);
}

String? _text(IndexedDbRecord record, String name) {
  final field = record.fields[name];
  if (field == null || field.unexpected) return null;
  return field.text;
}

Uint8List? _bytes(IndexedDbRecord record, String name) {
  final field = record.fields[name];
  if (field == null || field.unexpected) return null;
  return field.bytes;
}

({ExportDocument document, String digest})? _export(IndexedDbRecord? record) {
  if (record == null) return null;
  final bytes = _bytes(record, IndexedDbFulfilmentSchema.bytesField);
  final filename = _text(record, IndexedDbFulfilmentSchema.filenameField);
  final dateCreate = _text(record, IndexedDbFulfilmentSchema.dateCreateField);
  final digest = _text(record, IndexedDbFulfilmentSchema.digestField);
  if (bytes == null ||
      filename == null ||
      dateCreate == null ||
      digest == null) {
    return null;
  }
  return (
    document: ExportDocument(
      filename: filename,
      bytes: bytes,
      dateCreate: dateCreate,
    ),
    digest: digest,
  );
}
