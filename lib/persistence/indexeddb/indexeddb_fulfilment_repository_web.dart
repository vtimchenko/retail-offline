import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart';

import '../../domain/fulfilment/fulfilment_session.dart';
import '../../domain/fulfilment/session_snapshot.dart';
import '../../models/retail_dataset.dart';
import '../../services/json/cumulative_json_export.dart';
import '../dataset_fingerprint.dart';
import '../export_consistency.dart';
import '../fulfilment_repository.dart';
import '../session_snapshot_codec.dart';
import 'indexeddb_fulfilment_schema.dart';
import 'indexeddb_records.dart';

@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject object);

/// IndexedDB implementation of [FulfilmentRepository].
///
/// Parsing, hashing, and candidate checks finish before a write transaction
/// is opened. Inside that transaction the revision is checked and the puts
/// are queued with no further Dart `await`. A commit counts as finished only
/// when the transaction fires `complete`.
class IndexedDbFulfilmentRepository implements FulfilmentRepository {
  /// Opens [databaseName] in IndexedDB.
  ///
  /// The production name is [IndexedDbFulfilmentSchema.productionDatabaseName].
  /// Tests pass a different name so they do not touch that database.
  IndexedDbFulfilmentRepository({
    this.databaseName = IndexedDbFulfilmentSchema.productionDatabaseName,
    DatasetByteRestore? datasets,
    SessionSnapshotCodec? snapshots,
  }) : _datasets = datasets ?? const DatasetByteRestore(),
       _snapshots = snapshots ?? const SessionSnapshotCodec();

  /// IndexedDB database name.
  final String databaseName;

  final DatasetByteRestore _datasets;
  final SessionSnapshotCodec _snapshots;

  /// When set, the next write queues its puts and then aborts the transaction.
  ///
  /// The records are rolled back. Tests use this to prove a failed commit
  /// does not become visible.
  @visibleForTesting
  bool abortNextTransaction = false;

  Future<void> _tail = Future<void>.value();

  @override
  Future<LoadResult> load() {
    return _serialized(() async {
      final read = await _read();
      if (read is _ReadFailed) return read.loadResult;
      final rows = read as _ReadRows;
      return interpretIndexedDbRecords(
        dataset: rows.dataset,
        session: rows.session,
        export: rows.export,
        metadata: rows.metadata,
        datasets: _datasets,
        snapshots: _snapshots,
      );
    });
  }

  @override
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    final storedBytes = Uint8List.fromList(bytes);
    return _serialized(() async {
      final read = await _read();
      final blocked = _commitFailure(read);
      if (blocked != null) return blocked;
      final rows = read as _ReadRows;
      final loaded = _interpret(rows);
      if (loaded is LoadUnsupportedVersion) {
        return const CommitUnsupportedVersion();
      }
      if (loaded is LoadCorrupted) return const CommitCorrupted();
      if (loaded is! LoadEmpty) return const CommitRevisionConflict();
      final prepared = _prepare(
        datasetBytes: storedBytes,
        fingerprint: fingerprint,
        snapshot: snapshot,
        previous: null,
        export: null,
        rule: _ExportRule.empty,
      );
      if (prepared is CommitResult) return prepared;
      final candidate = prepared as _Candidate;
      return _write(
        rows: rows,
        importing: true,
        nextRevision: StorageRevision.initial,
        candidate: candidate,
        writeDataset: true,
        writeExport: false,
        deleteExport: false,
      );
    });
  }

  @override
  Future<CommitResult> replaceDataset({
    required int expectedRevision,
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    return _change(
      expectedRevision: expectedRevision,
      datasetBytes: Uint8List.fromList(bytes),
      fingerprint: fingerprint,
      snapshot: snapshot,
      export: null,
      useCurrentExport: false,
      rule: _ExportRule.empty,
      writeDataset: true,
      writeExport: false,
      deleteExport: true,
    );
  }

  @override
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  }) {
    return _change(
      expectedRevision: expectedRevision,
      snapshot: snapshot,
      export: null,
      useCurrentExport: true,
      rule: _ExportRule.unchanged,
      writeDataset: false,
      writeExport: false,
      deleteExport: false,
    );
  }

  @override
  Future<CommitResult> commitExport({
    required int expectedRevision,
    required SessionSnapshot snapshot,
    required ExportDocument document,
  }) {
    return _change(
      expectedRevision: expectedRevision,
      snapshot: snapshot,
      export: document,
      useCurrentExport: false,
      rule: _ExportRule.superset,
      writeDataset: false,
      writeExport: true,
      deleteExport: false,
    );
  }

  Future<CommitResult> _change({
    required int expectedRevision,
    Uint8List? datasetBytes,
    String? fingerprint,
    required SessionSnapshot snapshot,
    required ExportDocument? export,
    required bool useCurrentExport,
    required _ExportRule rule,
    required bool writeDataset,
    required bool writeExport,
    required bool deleteExport,
  }) {
    return _serialized(() async {
      final read = await _read();
      final blocked = _commitFailure(read);
      if (blocked != null) return blocked;
      final rows = read as _ReadRows;
      final loaded = _interpret(rows);
      final gate = _gate(loaded, expectedRevision);
      if (gate != null) return gate;
      final current = (loaded as LoadReady).state;
      final prepared = _prepare(
        datasetBytes: datasetBytes ?? _unusedBytes,
        fingerprint: fingerprint ?? current.fingerprint,
        snapshot: snapshot,
        previous: current,
        export: useCurrentExport ? current.export : export,
        rule: rule,
        datasetOverride: writeDataset ? null : current.dataset,
      );
      if (prepared is CommitResult) return prepared;
      return _write(
        rows: rows,
        importing: false,
        nextRevision: expectedRevision + 1,
        candidate: prepared as _Candidate,
        writeDataset: writeDataset,
        writeExport: writeExport,
        deleteExport: deleteExport,
      );
    });
  }

  LoadResult _interpret(_ReadRows rows) {
    return interpretIndexedDbRecords(
      dataset: rows.dataset,
      session: rows.session,
      export: rows.export,
      metadata: rows.metadata,
      datasets: _datasets,
      snapshots: _snapshots,
    );
  }

  CommitResult? _gate(LoadResult loaded, int expectedRevision) {
    return switch (loaded) {
      LoadEmpty() => const CommitRevisionConflict(),
      LoadUnsupportedVersion() => const CommitUnsupportedVersion(),
      LoadCorrupted() => const CommitCorrupted(),
      LoadStorageUnavailable() => const CommitStorageUnavailable(),
      LoadStorageFailed() => const CommitStorageFailed(),
      LoadReady(:final state) when state.revision != expectedRevision =>
        const CommitRevisionConflict(),
      LoadReady(:final state) when state.revision == StorageRevision.maximum =>
        const CommitRevisionOverflow(),
      LoadReady() => null,
    };
  }

  Object _prepare({
    required Uint8List datasetBytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
    required PersistedFulfilment? previous,
    required ExportDocument? export,
    required _ExportRule rule,
    RetailDataset? datasetOverride,
  }) {
    final encoded = _snapshots.encode(snapshot);
    final decoded = _snapshots.decode(encoded);
    if (decoded is! SnapshotDecoded || decoded.snapshot != snapshot) {
      return const CommitRejected(CommitRejection.invalidCandidate);
    }
    if (rule == _ExportRule.empty && !_emptyOverlay(snapshot)) {
      return const CommitRejected(CommitRejection.invalidCandidate);
    }
    if (rule == _ExportRule.unchanged &&
        !_sameIds(_exportedIds(previous!), snapshot.exportedOrderIds)) {
      return const CommitRejected(CommitRejection.exportedSetChanged);
    }
    if (rule == _ExportRule.superset &&
        !_strictSuperset(snapshot.exportedOrderIds, _exportedIds(previous!))) {
      return const CommitRejected(CommitRejection.exportNotSuperset);
    }

    final RetailDataset dataset;
    if (datasetOverride != null) {
      dataset = datasetOverride;
    } else {
      final restored = _datasets.restore(
        bytes: datasetBytes,
        expectedFingerprint: fingerprint,
      );
      if (restored is! DatasetRestored || restored.fingerprint != fingerprint) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      dataset = restored.dataset;
    }
    final session = FulfilmentSession.restore(
      dataset: dataset,
      snapshot: decoded.snapshot,
      expectedFingerprint: fingerprint,
    );
    if (session is! SessionRestored) {
      return const CommitRejected(CommitRejection.invalidCandidate);
    }
    final digest = export == null ? null : DatasetFingerprint.of(export.bytes);
    if (!ExportConsistency.matches(
      dataset: dataset,
      fingerprint: fingerprint,
      snapshot: decoded.snapshot,
      document: export,
      digest: digest,
    )) {
      return const CommitRejected(CommitRejection.invalidCandidate);
    }
    return _Candidate(
      bytes: datasetBytes,
      fingerprint: fingerprint,
      snapshotJson: encoded,
      export: export,
      digest: digest,
    );
  }

  List<String> _exportedIds(PersistedFulfilment state) {
    return state.session
        .capture(datasetFingerprint: state.fingerprint)
        .exportedOrderIds;
  }

  Future<_ReadResult> _read() {
    final opened = _open();
    return opened.then((result) {
      if (result is _DbFailed) return Future<_ReadResult>.value(result.asRead);
      final db = (result as _DbReady).database;
      return _readStores(db);
    });
  }

  Future<CommitResult> _write({
    required _ReadRows rows,
    required bool importing,
    required int nextRevision,
    required _Candidate candidate,
    required bool writeDataset,
    required bool writeExport,
    required bool deleteExport,
  }) {
    final opened = _open();
    return opened.then((result) async {
      if (result is _DbFailed) return result.asCommit;
      final db = (result as _DbReady).database;
      return _writeTransaction(
        database: db,
        expected: rows.identity,
        importing: importing,
        nextRevision: nextRevision,
        candidate: candidate,
        writeDataset: writeDataset,
        writeExport: writeExport,
        deleteExport: deleteExport,
      );
    });
  }

  Future<_DbResult> _open() {
    final completer = Completer<_DbResult>();
    final retained = <JSFunction>[];
    JSFunction keep(void Function(Event event) listener) {
      final function = listener.toJS;
      retained.add(function);
      return function;
    }

    final IDBFactory factory;
    try {
      factory = window.indexedDB;
    } catch (_) {
      return Future<_DbResult>.value(const _DbFailed(_Failure.unavailable));
    }

    final request = factory.open(
      databaseName,
      IndexedDbFulfilmentSchema.databaseVersion,
    );
    var settled = false;
    void finish(_DbResult result) {
      if (settled) return;
      settled = true;
      retained.length;
      completer.complete(result);
    }

    request.onupgradeneeded = keep((Event _) {
      final database = request.result as IDBDatabase;
      try {
        for (final name in IndexedDbFulfilmentSchema.stores) {
          if (!database.objectStoreNames.contains(name)) {
            database.createObjectStore(name);
          }
        }
      } catch (_) {
        request.transaction?.abort();
      }
    });
    request.onsuccess = keep((Event _) {
      final database = request.result as IDBDatabase;
      if (settled) {
        database.close();
        return;
      }
      finish(_DbReady(database));
    });
    request.onblocked = keep((Event _) {
      finish(const _DbFailed(_Failure.unavailable));
    });
    request.onerror = keep((Event _) {
      final name = request.error?.name;
      finish(
        _DbFailed(
          name == 'VersionError' ? _Failure.unsupported : _Failure.unavailable,
        ),
      );
    });
    return completer.future;
  }

  Future<_ReadResult> _readStores(IDBDatabase database) {
    final completer = Completer<_ReadResult>();
    final retained = <JSFunction>[];
    JSFunction keep(void Function(Event event) listener) {
      final function = listener.toJS;
      retained.add(function);
      return function;
    }

    final transaction = database.transaction(_storeNames, 'readonly');
    final records = <String, IndexedDbRecord?>{};
    var settled = false;

    void close() {
      database.close();
    }

    void finish(_ReadResult result) {
      if (settled) return;
      settled = true;
      retained.length;
      close();
      completer.complete(result);
    }

    transaction.oncomplete = keep((Event _) {
      if (records.length != IndexedDbFulfilmentSchema.stores.length) {
        finish(const _ReadFailed(_Failure.failed));
        return;
      }
      finish(_rowsFrom(records));
    });
    transaction.onabort = keep((Event _) {
      finish(const _ReadFailed(_Failure.failed));
    });
    transaction.onerror = keep((Event _) {
      finish(const _ReadFailed(_Failure.failed));
    });

    for (final store in IndexedDbFulfilmentSchema.stores) {
      final request = transaction.objectStore(store).get(_currentKey);
      request.onsuccess = keep((Event _) {
        if (settled) return;
        try {
          records[store] = _copyRecord(request.result, _expectedFields(store));
        } catch (_) {
          finish(const _ReadFailed(_Failure.failed));
        }
      });
    }
    return completer.future;
  }

  /// Queues the revision check and the puts inside one write transaction.
  ///
  /// The callback does not `await`. Safari commits an IndexedDB transaction
  /// when control returns to the event loop, so hashing and parsing happen
  /// before this method. A request `success` event is not a commit: the
  /// result is [CommitSucceeded] only from the transaction `complete` event.
  Future<CommitResult> _writeTransaction({
    required IDBDatabase database,
    required _Identity expected,
    required bool importing,
    required int nextRevision,
    required _Candidate candidate,
    required bool writeDataset,
    required bool writeExport,
    required bool deleteExport,
  }) {
    final completer = Completer<CommitResult>();
    final retained = <JSFunction>[];
    JSFunction keep(void Function(Event event) listener) {
      final function = listener.toJS;
      retained.add(function);
      return function;
    }

    final transaction = database.transaction(_storeNames, 'readwrite');
    final records = <String, IndexedDbRecord?>{};
    var remaining = IndexedDbFulfilmentSchema.stores.length;
    var settled = false;
    var wrote = false;
    CommitResult? outcome;

    void close() {
      database.close();
    }

    void finish(CommitResult result) {
      if (settled) return;
      settled = true;
      outcome = result;
      retained.length;
      close();
      completer.complete(result);
    }

    transaction.oncomplete = keep((Event _) {
      finish(
        outcome ??
            (wrote
                ? CommitSucceeded(nextRevision)
                : const CommitStorageFailed()),
      );
    });
    transaction.onabort = keep((Event _) {
      finish(outcome ?? const CommitStorageFailed());
    });
    transaction.onerror = keep((Event _) {
      finish(outcome ?? const CommitStorageFailed());
    });

    void reject(CommitResult result) {
      outcome = result;
      try {
        transaction.abort();
      } catch (_) {
        finish(result);
      }
    }

    void publish() {
      _putRecords(
        transaction,
        candidate: candidate,
        nextRevision: nextRevision,
        writeDataset: writeDataset,
        writeExport: writeExport,
        deleteExport: deleteExport,
      );
      wrote = true;
      if (abortNextTransaction) {
        abortNextTransaction = false;
        reject(const CommitStorageFailed());
      }
    }

    for (final store in IndexedDbFulfilmentSchema.stores) {
      final request = transaction.objectStore(store).get(_currentKey);
      request.onsuccess = keep((Event _) {
        if (settled) return;
        try {
          records[store] = _copyRecord(request.result, _expectedFields(store));
          remaining--;
          if (remaining != 0) return;
          final live = _rowsFrom(records).identity;
          if (importing) {
            if (!live.isEmpty) {
              reject(const CommitRevisionConflict());
              return;
            }
            publish();
            return;
          }
          if (!live.sameAs(expected)) {
            reject(
              live.revision == expected.revision
                  ? const CommitCorrupted()
                  : const CommitRevisionConflict(),
            );
            return;
          }
          publish();
        } catch (_) {
          reject(const CommitStorageFailed());
        }
      });
    }
    return completer.future;
  }

  void _putRecords(
    IDBTransaction transaction, {
    required _Candidate candidate,
    required int nextRevision,
    required bool writeDataset,
    required bool writeExport,
    required bool deleteExport,
  }) {
    final schema = '${FulfilmentStorageSchema.current}';
    final key = _currentKey;
    if (writeDataset) {
      transaction
          .objectStore(IndexedDbFulfilmentSchema.dataset)
          .put(
            _DatasetRecord(
              schemaVersion: schema,
              bytes: candidate.bytes.toJS,
              fingerprint: candidate.fingerprint,
            ),
            key,
          );
    }
    transaction
        .objectStore(IndexedDbFulfilmentSchema.session)
        .put(
          _SessionRecord(
            schemaVersion: schema,
            snapshot: candidate.snapshotJson,
          ),
          key,
        );
    if (deleteExport) {
      transaction.objectStore(IndexedDbFulfilmentSchema.exports).delete(key);
    } else if (writeExport && candidate.export != null) {
      transaction
          .objectStore(IndexedDbFulfilmentSchema.exports)
          .put(
            _ExportRecord(
              schemaVersion: schema,
              filename: candidate.export!.filename,
              dateCreate: candidate.export!.dateCreate,
              bytes: candidate.export!.bytes.toJS,
              digest: candidate.digest!,
            ),
            key,
          );
    }
    transaction
        .objectStore(IndexedDbFulfilmentSchema.metadata)
        .put(
          _MetadataRecord(
            schemaVersion: schema,
            revision: IndexedDbFulfilmentSchema.revisionText(nextRevision),
            fingerprint: candidate.fingerprint,
          ),
          key,
        );
  }

  CommitResult? _commitFailure(_ReadResult read) {
    if (read is! _ReadFailed) return null;
    return switch (read.failure) {
      _Failure.unavailable => const CommitStorageUnavailable(),
      _Failure.unsupported => const CommitUnsupportedVersion(),
      _Failure.failed => const CommitStorageFailed(),
    };
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        done.complete();
      }
    });
  }
}

enum _Failure { unavailable, unsupported, failed }

enum _ExportRule { empty, unchanged, superset }

class _Candidate {
  const _Candidate({
    required this.bytes,
    required this.fingerprint,
    required this.snapshotJson,
    required this.export,
    required this.digest,
  });

  final Uint8List bytes;
  final String fingerprint;
  final String snapshotJson;
  final ExportDocument? export;
  final String? digest;
}

class _Identity {
  const _Identity({
    required this.datasetPresent,
    required this.sessionPresent,
    required this.exportPresent,
    required this.metadataPresent,
    required this.schemaVersion,
    required this.revision,
    required this.fingerprint,
    required this.snapshot,
    required this.exportDigest,
  });

  final bool datasetPresent;
  final bool sessionPresent;
  final bool exportPresent;
  final bool metadataPresent;
  final String? schemaVersion;
  final String? revision;
  final String? fingerprint;
  final String? snapshot;
  final String? exportDigest;

  bool get isEmpty =>
      !datasetPresent && !sessionPresent && !exportPresent && !metadataPresent;

  bool sameAs(_Identity other) {
    return datasetPresent == other.datasetPresent &&
        sessionPresent == other.sessionPresent &&
        exportPresent == other.exportPresent &&
        metadataPresent == other.metadataPresent &&
        schemaVersion == other.schemaVersion &&
        revision == other.revision &&
        fingerprint == other.fingerprint &&
        snapshot == other.snapshot &&
        exportDigest == other.exportDigest;
  }
}

sealed class _DbResult {
  const _DbResult();
}

class _DbReady extends _DbResult {
  const _DbReady(this.database);

  final IDBDatabase database;
}

class _DbFailed extends _DbResult {
  const _DbFailed(this.failure);

  final _Failure failure;

  _ReadFailed get asRead => _ReadFailed(failure);

  CommitResult get asCommit => switch (failure) {
    _Failure.unavailable => const CommitStorageUnavailable(),
    _Failure.unsupported => const CommitUnsupportedVersion(),
    _Failure.failed => const CommitStorageFailed(),
  };
}

sealed class _ReadResult {
  const _ReadResult();
}

class _ReadFailed extends _ReadResult {
  const _ReadFailed(this.failure);

  final _Failure failure;

  LoadResult get loadResult => switch (failure) {
    _Failure.unavailable => const LoadStorageUnavailable(),
    _Failure.unsupported => const LoadUnsupportedVersion(),
    _Failure.failed => const LoadStorageFailed(),
  };
}

class _ReadRows extends _ReadResult {
  const _ReadRows({
    required this.dataset,
    required this.session,
    required this.export,
    required this.metadata,
    required this.identity,
  });

  final IndexedDbRecord? dataset;
  final IndexedDbRecord? session;
  final IndexedDbRecord? export;
  final IndexedDbRecord? metadata;
  final _Identity identity;
}

_ReadRows _rowsFrom(Map<String, IndexedDbRecord?> records) {
  final dataset = records[IndexedDbFulfilmentSchema.dataset];
  final session = records[IndexedDbFulfilmentSchema.session];
  final export = records[IndexedDbFulfilmentSchema.exports];
  final metadata = records[IndexedDbFulfilmentSchema.metadata];
  return _ReadRows(
    dataset: dataset,
    session: session,
    export: export,
    metadata: metadata,
    identity: _Identity(
      datasetPresent: dataset != null,
      sessionPresent: session != null,
      exportPresent: export != null,
      metadataPresent: metadata != null,
      schemaVersion: _fieldText(
        metadata,
        IndexedDbFulfilmentSchema.schemaVersionField,
      ),
      revision: _fieldText(metadata, IndexedDbFulfilmentSchema.revisionField),
      fingerprint: _fieldText(
        metadata,
        IndexedDbFulfilmentSchema.fingerprintField,
      ),
      snapshot: _fieldText(session, IndexedDbFulfilmentSchema.snapshotField),
      exportDigest: _fieldText(export, IndexedDbFulfilmentSchema.digestField),
    ),
  );
}

String? _fieldText(IndexedDbRecord? record, String name) {
  final field = record?.fields[name];
  if (field == null || field.unexpected) return null;
  return field.text;
}

JSArray<JSString> get _storeNames => [
  IndexedDbFulfilmentSchema.dataset.toJS,
  IndexedDbFulfilmentSchema.session.toJS,
  IndexedDbFulfilmentSchema.exports.toJS,
  IndexedDbFulfilmentSchema.metadata.toJS,
].toJS;

JSString get _currentKey => IndexedDbFulfilmentSchema.currentKey.toJS;

final Uint8List _unusedBytes = Uint8List(0);

Set<String> _expectedFields(String store) {
  return switch (store) {
    IndexedDbFulfilmentSchema.dataset =>
      IndexedDbFulfilmentSchema.datasetFields,
    IndexedDbFulfilmentSchema.session =>
      IndexedDbFulfilmentSchema.sessionFields,
    IndexedDbFulfilmentSchema.exports => IndexedDbFulfilmentSchema.exportFields,
    IndexedDbFulfilmentSchema.metadata =>
      IndexedDbFulfilmentSchema.metadataFields,
    _ => const {},
  };
}

IndexedDbRecord? _copyRecord(JSAny? result, Set<String> expected) {
  if (_missing(result)) return null;
  if (!_isPlainObject(result!)) {
    return const IndexedDbRecord(fields: {}, unexpectedKeys: true);
  }
  final object = result as JSObject;
  final keys = {for (final key in _objectKeys(object).toDart) key.toDart};
  final fields = <String, IndexedDbField>{};
  for (final name in expected) {
    if (!keys.contains(name)) continue;
    fields[name] = _copyField(object.getProperty<JSAny?>(name.toJS));
  }
  final unexpected =
      keys.length != expected.length || !expected.containsAll(keys);
  return IndexedDbRecord(fields: fields, unexpectedKeys: unexpected);
}

IndexedDbField _copyField(JSAny? value) {
  if (_missing(value)) return const IndexedDbField.unexpected();
  if (value.isA<JSString>()) {
    return IndexedDbField.text((value as JSString).toDart);
  }
  if (value.isA<JSUint8Array>()) {
    return IndexedDbField.bytes(
      Uint8List.fromList((value as JSUint8Array).toDart),
    );
  }
  return const IndexedDbField.unexpected();
}

bool _missing(JSAny? value) {
  if (value == null) return true;
  return value.isNull || value.isUndefined;
}

bool _isPlainObject(JSAny value) {
  if (value.isA<JSString>() ||
      value.isA<JSUint8Array>() ||
      value.isA<JSArray>() ||
      value.isA<JSNumber>()) {
    return false;
  }
  return value.isA<JSObject>();
}

bool _emptyOverlay(SessionSnapshot snapshot) {
  return snapshot.reservations.isEmpty &&
      snapshot.issuedOrderIds.isEmpty &&
      snapshot.exportedOrderIds.isEmpty;
}

bool _sameIds(List<String> left, List<String> right) {
  final leftIds = _unique(left);
  final rightIds = _unique(right);
  if (leftIds == null || rightIds == null) return false;
  return leftIds.length == rightIds.length && leftIds.containsAll(rightIds);
}

bool _strictSuperset(List<String> next, List<String> previous) {
  final nextIds = _unique(next);
  final previousIds = _unique(previous);
  if (nextIds == null || previousIds == null) return false;
  return nextIds.containsAll(previousIds) &&
      nextIds.length > previousIds.length;
}

Set<String>? _unique(List<String> ids) {
  final unique = <String>{};
  for (final id in ids) {
    if (!unique.add(id)) return null;
  }
  return unique;
}

extension type _DatasetRecord._(JSObject _) implements JSObject {
  external factory _DatasetRecord({
    String schemaVersion,
    JSUint8Array bytes,
    String fingerprint,
  });
}

extension type _SessionRecord._(JSObject _) implements JSObject {
  external factory _SessionRecord({String schemaVersion, String snapshot});
}

extension type _ExportRecord._(JSObject _) implements JSObject {
  external factory _ExportRecord({
    String schemaVersion,
    String filename,
    String dateCreate,
    JSUint8Array bytes,
    String digest,
  });
}

extension type _MetadataRecord._(JSObject _) implements JSObject {
  external factory _MetadataRecord({
    String schemaVersion,
    String revision,
    String fingerprint,
  });
}
