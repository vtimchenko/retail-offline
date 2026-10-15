import 'package:flutter/foundation.dart';

import '../domain/fulfilment/fulfilment_session.dart';
import '../domain/fulfilment/session_snapshot.dart';
import '../models/retail_dataset.dart';
import '../services/json/cumulative_json_export.dart';

/// Bounds for the persisted fulfilment revision.
///
/// The value is a JavaScript safe integer so a web build can store it
/// without rounding. Revision 1 is the first successful import.
abstract final class StorageRevision {
  /// Revision written by the first successful import.
  static const int initial = 1;

  /// Largest revision that can be incremented without leaving the safe range.
  ///
  /// This is `Number.MAX_SAFE_INTEGER` (2^53 − 1). A commit that would store
  /// a larger value is rejected.
  static const int maximum = 9007199254740991;

  /// Whether [revision] is inside the safe integer range.
  ///
  /// [maximum] itself is representable. Incrementing it is rejected separately.
  static bool isSafe(int revision) =>
      revision >= initial && revision <= maximum;
}

/// Schema version of the four persisted records.
///
/// A different version is unsupported. This phase does not migrate it.
abstract final class FulfilmentStorageSchema {
  /// Version written by this phase.
  static const int current = 1;
}

/// One active dataset, its session, and the last committed export.
@immutable
class PersistedFulfilment {
  /// Creates the state read from storage.
  const PersistedFulfilment({
    required this.dataset,
    required this.session,
    required this.revision,
    required this.fingerprint,
    this.export,
  });

  /// Dataset restored from the original bytes.
  final RetailDataset dataset;

  /// Session restored from the stored snapshot.
  final FulfilmentSession session;

  /// Monotonic revision of this state. The first import is 1.
  final int revision;

  /// SHA-256 hex of the original dataset bytes.
  final String fingerprint;

  /// Last successfully committed export, when one is stored.
  final ExportDocument? export;
}

/// Result of reading the persisted fulfilment records.
@immutable
sealed class LoadResult {
  const LoadResult();
}

/// No dataset, session, export, or revision is stored.
final class LoadEmpty extends LoadResult {
  /// Creates an empty-storage result.
  const LoadEmpty();
}

/// Storage held a consistent dataset and session.
final class LoadReady extends LoadResult {
  /// Creates a successful load result.
  const LoadReady(this.state);

  /// Restored records.
  final PersistedFulfilment state;
}

/// The browser storage implementation cannot be opened.
final class LoadStorageUnavailable extends LoadResult {
  /// Creates an unavailable-storage result.
  const LoadStorageUnavailable();
}

/// The read did not finish.
final class LoadStorageFailed extends LoadResult {
  /// Creates a failed-read result.
  const LoadStorageFailed();
}

/// Stored records are present and failed validation.
///
/// The records are left in place.
final class LoadCorrupted extends LoadResult {
  /// Creates a corrupted-storage result.
  const LoadCorrupted();
}

/// Stored records use a schema this version does not read.
final class LoadUnsupportedVersion extends LoadResult {
  /// Creates an unsupported-schema result.
  const LoadUnsupportedVersion();
}

/// Result of a write that changes persisted fulfilment state.
@immutable
sealed class CommitResult {
  const CommitResult();
}

/// The write finished and [revision] is the stored revision.
final class CommitSucceeded extends CommitResult {
  /// Creates a successful commit result.
  const CommitSucceeded(this.revision);

  /// Revision stored by this commit.
  final int revision;
}

/// [expectedRevision] did not match the stored revision.
///
/// Nothing was written.
final class CommitRevisionConflict extends CommitResult {
  /// Creates a revision-conflict result.
  const CommitRevisionConflict();
}

/// Storage could not be opened.
final class CommitStorageUnavailable extends CommitResult {
  /// Creates an unavailable-storage result.
  const CommitStorageUnavailable();
}

/// The write did not finish.
///
/// The caller must not treat the candidate as stored.
final class CommitStorageFailed extends CommitResult {
  /// Creates a failed-write result.
  const CommitStorageFailed();
}

/// The current records failed validation, so nothing was written.
final class CommitCorrupted extends CommitResult {
  /// Creates a corrupted-storage result.
  const CommitCorrupted();
}

/// The stored schema is not [FulfilmentStorageSchema.current].
final class CommitUnsupportedVersion extends CommitResult {
  /// Creates an unsupported-schema result.
  const CommitUnsupportedVersion();
}

/// The next revision would exceed [StorageRevision.maximum].
///
/// The stored revision is unchanged.
final class CommitRevisionOverflow extends CommitResult {
  /// Creates an overflow result.
  const CommitRevisionOverflow();
}

/// The candidate itself cannot be stored.
///
/// Nothing was written. This is not a conflict and not a storage failure.
final class CommitRejected extends CommitResult {
  /// Creates a rejected-candidate result.
  const CommitRejected(this.reason);

  /// Why the candidate was rejected.
  final CommitRejection reason;
}

/// Why a candidate was rejected before a write.
enum CommitRejection {
  /// The snapshot, bytes, or fingerprint do not restore.
  invalidCandidate,

  /// A session commit tried to change the exported order ids.
  exportedSetChanged,

  /// An export commit did not add exported orders to the previous set.
  exportNotSuperset,
}

/// Persistence port for one active fulfilment dataset.
///
/// Implementations keep the dataset bytes, session snapshot, last export,
/// and revision consistent. A [CommitSucceeded] result means the write has
/// finished, not merely that it was requested. The memory implementation is
/// a test double. Production storage is the IndexedDB adapter.
abstract interface class FulfilmentRepository {
  /// Reads the current records.
  Future<LoadResult> load();

  /// Stores the first dataset at revision [StorageRevision.initial].
  ///
  /// Succeeds only when storage has no fulfilment records. The snapshot must
  /// restore against [bytes] and contain no reservations or order flags.
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  });

  /// Replaces the dataset, session, and export together.
  ///
  /// The previous records stay in place unless the whole write finishes.
  /// [snapshot] must be an empty overlay for [bytes]. A stored export is
  /// removed in the same commit.
  Future<CommitResult> replaceDataset({
    required int expectedRevision,
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  });

  /// Stores [snapshot] when its exported order ids are unchanged.
  ///
  /// The revision check and the write are one commit. A snapshot whose
  /// exported ids differ from the stored snapshot is rejected.
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  });

  /// Stores [snapshot] and [document] together.
  ///
  /// The snapshot's exported ids must be a strict superset of the stored
  /// exported ids. The document must be the Phase 3 cumulative JSON file
  /// for those ids and for the stored dataset. Its SHA-256 is stored with
  /// the bytes. The dataset bytes and fingerprint stay as they are. The
  /// previous session and document stay unless the whole write finishes.
  Future<CommitResult> commitExport({
    required int expectedRevision,
    required SessionSnapshot snapshot,
    required ExportDocument document,
  });
}
