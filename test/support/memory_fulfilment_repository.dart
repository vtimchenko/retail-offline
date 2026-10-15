import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/export_consistency.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/persistence/session_snapshot_codec.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';

/// Gate a test uses to finish one commit only when it says so.
class CommitHold {
  final Completer<void> _started = Completer<void>();
  final Completer<void> _released = Completer<void>();

  /// Completes when the repository is inside the held commit, before it
  /// writes.
  Future<void> get started => _started.future;

  /// Lets the held commit continue.
  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  void _markStarted() {
    if (!_started.isCompleted) _started.complete();
  }
}

/// In-memory [FulfilmentRepository] for tests.
///
/// Several application services can share one instance. Revision checks and
/// record writes happen together, and a commit result is returned only after
/// that work has finished or been refused. This type is not a production
/// fallback.
class MemoryFulfilmentRepository implements FulfilmentRepository {
  MemoryFulfilmentRepository({
    DatasetByteRestore? datasets,
    SessionSnapshotCodec? snapshots,
  }) : _datasets = datasets ?? const DatasetByteRestore(),
       _snapshots = snapshots ?? const SessionSnapshotCodec();

  final DatasetByteRestore _datasets;
  final SessionSnapshotCodec _snapshots;
  final _Record _record = _Record();

  Future<void> _tail = Future<void>.value();
  CommitHold? _nextHold;
  bool _failNext = false;
  bool _unavailable = false;
  int _commitAttempts = 0;

  /// How many mutating calls have entered the repository.
  int get commitAttempts => _commitAttempts;

  /// Stored revision, including a value planted by a test.
  int? get debugRevision => _record.revision;

  set debugRevision(int? value) => _record.revision = value;

  /// Stored schema version.
  int get debugSchemaVersion => _record.schemaVersion;

  set debugSchemaVersion(int value) => _record.schemaVersion = value;

  /// Replaces the stored fingerprint without rewriting the bytes.
  set debugFingerprint(String? value) => _record.fingerprint = value;

  /// Makes later reads and writes return storage-unavailable.
  void debugStorageUnavailable(bool unavailable) {
    _unavailable = unavailable;
  }

  /// The next mutating call fails before it changes records.
  void failNextCommit() {
    _failNext = true;
  }

  /// Holds the next mutating call after it has started and before it writes.
  CommitHold holdNextCommit() {
    final hold = CommitHold();
    _nextHold = hold;
    return hold;
  }

  /// Replaces fields of the stored export without validating them.
  ///
  /// [rehash] stores the SHA-256 of the bytes that remain after the change.
  /// A supplied [digest] is stored as given. Otherwise the previous digest
  /// stays, so a test can separate a byte change from a digest change.
  void debugAlterExport({
    Uint8List? bytes,
    String? filename,
    String? dateCreate,
    String? digest,
    bool rehash = false,
  }) {
    final current = _record.export;
    if (current == null) {
      throw StateError('No export is stored.');
    }
    final nextBytes = bytes ?? current.bytes;
    _record.export = ExportDocument(
      filename: filename ?? current.filename,
      bytes: nextBytes,
      dateCreate: dateCreate ?? current.dateCreate,
    );
    if (digest != null) {
      _record.exportDigest = digest;
    } else if (rehash) {
      _record.exportDigest = DatasetFingerprint.of(nextBytes);
    }
  }

  @override
  Future<LoadResult> load() {
    return _serialized(() async {
      if (_unavailable) return const LoadStorageUnavailable();
      return _interpret(_record);
    });
  }

  @override
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    return _change(() {
      if (!_record.isEmpty) return const CommitRevisionConflict();
      final encoded = _encode(snapshot);
      if (encoded == null || !_emptyOverlay(snapshot)) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      final ready = _readyState(
        bytes: bytes,
        fingerprint: fingerprint,
        snapshotJson: encoded,
        export: null,
        exportDigest: null,
        revision: StorageRevision.initial,
      );
      if (ready is! LoadReady) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      _record
        ..bytes = Uint8List.fromList(bytes)
        ..fingerprint = fingerprint
        ..snapshotJson = encoded
        ..export = null
        ..exportDigest = null
        ..revision = StorageRevision.initial;
      return const CommitSucceeded(StorageRevision.initial);
    });
  }

  @override
  Future<CommitResult> replaceDataset({
    required int expectedRevision,
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    return _change(() {
      final gate = _gate(expectedRevision);
      if (gate != null) return gate;
      final encoded = _encode(snapshot);
      if (encoded == null || !_emptyOverlay(snapshot)) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      final ready = _readyState(
        bytes: bytes,
        fingerprint: fingerprint,
        snapshotJson: encoded,
        export: null,
        exportDigest: null,
        revision: expectedRevision + 1,
      );
      if (ready is! LoadReady) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      _record
        ..bytes = Uint8List.fromList(bytes)
        ..fingerprint = fingerprint
        ..snapshotJson = encoded
        ..export = null
        ..exportDigest = null
        ..revision = expectedRevision + 1;
      return CommitSucceeded(expectedRevision + 1);
    });
  }

  @override
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  }) {
    return _change(() {
      final gate = _gate(expectedRevision);
      if (gate != null) return gate;
      final current = _decoded(_record.snapshotJson);
      if (current == null) return const CommitCorrupted();
      if (!_sameIds(current.exportedOrderIds, snapshot.exportedOrderIds)) {
        return const CommitRejected(CommitRejection.exportedSetChanged);
      }
      final encoded = _encode(snapshot);
      if (encoded == null) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      final ready = _readyState(
        bytes: _record.bytes!,
        fingerprint: _record.fingerprint!,
        snapshotJson: encoded,
        export: _record.export,
        exportDigest: _record.exportDigest,
        revision: expectedRevision + 1,
      );
      if (ready is! LoadReady) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      _record
        ..snapshotJson = encoded
        ..revision = expectedRevision + 1;
      return CommitSucceeded(expectedRevision + 1);
    });
  }

  @override
  Future<CommitResult> commitExport({
    required int expectedRevision,
    required SessionSnapshot snapshot,
    required ExportDocument document,
  }) {
    return _change(() {
      final gate = _gate(expectedRevision);
      if (gate != null) return gate;
      final current = _decoded(_record.snapshotJson);
      if (current == null) return const CommitCorrupted();
      if (!_strictSuperset(
        snapshot.exportedOrderIds,
        current.exportedOrderIds,
      )) {
        return const CommitRejected(CommitRejection.exportNotSuperset);
      }
      final encoded = _encode(snapshot);
      if (encoded == null) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      final storedDocument = ExportDocument(
        filename: document.filename,
        bytes: document.bytes,
        dateCreate: document.dateCreate,
      );
      final digest = DatasetFingerprint.of(storedDocument.bytes);
      final ready = _readyState(
        bytes: _record.bytes!,
        fingerprint: _record.fingerprint!,
        snapshotJson: encoded,
        export: storedDocument,
        exportDigest: digest,
        revision: expectedRevision + 1,
      );
      if (ready is! LoadReady) {
        return const CommitRejected(CommitRejection.invalidCandidate);
      }
      _record
        ..snapshotJson = encoded
        ..export = storedDocument
        ..exportDigest = digest
        ..revision = expectedRevision + 1;
      return CommitSucceeded(expectedRevision + 1);
    });
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

  Future<CommitResult> _change(CommitResult Function() apply) {
    return _serialized(() async {
      _commitAttempts++;
      final hold = _nextHold;
      _nextHold = null;
      if (hold != null) {
        hold._markStarted();
        await hold._released.future;
      }
      if (_unavailable) return const CommitStorageUnavailable();
      if (_record.schemaVersion != FulfilmentStorageSchema.current) {
        return const CommitUnsupportedVersion();
      }
      if (_failNext) {
        _failNext = false;
        return const CommitStorageFailed();
      }
      return apply();
    });
  }

  CommitResult? _gate(int expectedRevision) {
    if (_record.isEmpty) return const CommitRevisionConflict();
    if (_record.bytes == null ||
        _record.fingerprint == null ||
        _record.snapshotJson == null ||
        _record.revision == null ||
        !StorageRevision.isSafe(_record.revision!)) {
      return const CommitCorrupted();
    }
    if (_record.revision != expectedRevision) {
      return const CommitRevisionConflict();
    }
    if (expectedRevision == StorageRevision.maximum) {
      return const CommitRevisionOverflow();
    }
    return null;
  }

  String? _encode(SessionSnapshot snapshot) {
    final encoded = _snapshots.encode(snapshot);
    final decoded = _snapshots.decode(encoded);
    if (decoded is! SnapshotDecoded) return null;
    return encoded;
  }

  SessionSnapshot? _decoded(String? source) {
    if (source == null) return null;
    final decoded = _snapshots.decode(source);
    if (decoded is! SnapshotDecoded) return null;
    return decoded.snapshot;
  }

  LoadResult _interpret(_Record record) {
    if (record.schemaVersion != FulfilmentStorageSchema.current) {
      return const LoadUnsupportedVersion();
    }
    if (record.isEmpty) return const LoadEmpty();
    if (record.bytes == null ||
        record.fingerprint == null ||
        record.snapshotJson == null ||
        record.revision == null ||
        !StorageRevision.isSafe(record.revision!)) {
      return const LoadCorrupted();
    }
    return _readyState(
      bytes: record.bytes!,
      fingerprint: record.fingerprint!,
      snapshotJson: record.snapshotJson!,
      export: record.export,
      exportDigest: record.exportDigest,
      revision: record.revision!,
    );
  }

  LoadResult _readyState({
    required Uint8List bytes,
    required String fingerprint,
    required String snapshotJson,
    required ExportDocument? export,
    required String? exportDigest,
    required int revision,
  }) {
    if (!StorageRevision.isSafe(revision)) return const LoadCorrupted();
    final dataset = _datasets.restore(
      bytes: bytes,
      expectedFingerprint: fingerprint,
    );
    if (dataset is! DatasetRestored) return const LoadCorrupted();
    final decoded = _snapshots.decode(snapshotJson);
    if (decoded is! SnapshotDecoded) return const LoadCorrupted();
    final restored = FulfilmentSession.restore(
      dataset: dataset.dataset,
      snapshot: decoded.snapshot,
      expectedFingerprint: fingerprint,
    );
    if (restored is! SessionRestored) return const LoadCorrupted();
    if (!ExportConsistency.matches(
      dataset: dataset.dataset,
      fingerprint: fingerprint,
      snapshot: decoded.snapshot,
      document: export,
      digest: exportDigest,
    )) {
      return const LoadCorrupted();
    }
    return LoadReady(
      PersistedFulfilment(
        dataset: dataset.dataset,
        session: restored.session,
        revision: revision,
        fingerprint: fingerprint,
        export: export,
      ),
    );
  }

  bool _emptyOverlay(SessionSnapshot snapshot) =>
      snapshot.reservations.isEmpty &&
      snapshot.issuedOrderIds.isEmpty &&
      snapshot.exportedOrderIds.isEmpty;

  bool _sameIds(List<String> left, List<String> right) {
    final leftIds = _uniqueIds(left);
    final rightIds = _uniqueIds(right);
    if (leftIds == null || rightIds == null) return false;
    return leftIds.length == rightIds.length && leftIds.containsAll(rightIds);
  }

  Set<String>? _uniqueIds(List<String> ids) {
    final unique = <String>{};
    for (final id in ids) {
      if (!unique.add(id)) return null;
    }
    return unique;
  }

  bool _strictSuperset(List<String> next, List<String> previous) {
    final nextIds = <String>{};
    for (final id in next) {
      if (!nextIds.add(id)) return false;
    }
    final previousIds = <String>{};
    for (final id in previous) {
      if (!previousIds.add(id)) return false;
    }
    return nextIds.containsAll(previousIds) &&
        nextIds.length > previousIds.length;
  }
}

class _Record {
  int schemaVersion = FulfilmentStorageSchema.current;
  Uint8List? bytes;
  String? fingerprint;
  String? snapshotJson;
  ExportDocument? export;
  String? exportDigest;
  int? revision;

  bool get isEmpty =>
      bytes == null &&
      fingerprint == null &&
      snapshotJson == null &&
      export == null &&
      exportDigest == null &&
      revision == null;
}
