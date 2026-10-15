import 'package:flutter/foundation.dart';

import '../../domain/fulfilment/session_snapshot.dart';
import '../../services/json/cumulative_json_export.dart';
import '../dataset_fingerprint.dart';
import '../fulfilment_repository.dart';
import '../session_snapshot_codec.dart';
import 'indexeddb_fulfilment_schema.dart';

/// Non-browser [IndexedDbFulfilmentRepository].
///
/// VM tests and other non-web builds compile this instead of `package:web`.
/// It never stores data and it is not a memory fallback.
class IndexedDbFulfilmentRepository implements FulfilmentRepository {
  /// Creates a repository that reports storage as unavailable.
  IndexedDbFulfilmentRepository({
    this.databaseName = IndexedDbFulfilmentSchema.productionDatabaseName,
    DatasetByteRestore? datasets,
    SessionSnapshotCodec? snapshots,
  });

  /// Database name this repository would open in the browser.
  final String databaseName;

  /// Ignored. The browser implementation aborts one write when this is set.
  bool abortNextTransaction = false;

  @override
  Future<LoadResult> load() async => const LoadStorageUnavailable();

  @override
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) async {
    return const CommitStorageUnavailable();
  }

  @override
  Future<CommitResult> replaceDataset({
    required int expectedRevision,
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) async {
    return const CommitStorageUnavailable();
  }

  @override
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  }) async {
    return const CommitStorageUnavailable();
  }

  @override
  Future<CommitResult> commitExport({
    required int expectedRevision,
    required SessionSnapshot snapshot,
    required ExportDocument document,
  }) async {
    return const CommitStorageUnavailable();
  }
}
