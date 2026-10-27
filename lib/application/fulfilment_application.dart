import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/fulfilment/fulfilment_session.dart';
import '../persistence/dataset_fingerprint.dart';
import '../persistence/fulfilment_repository.dart';
import '../services/json/cumulative_json_export.dart';

/// Why business mutations are suspended.
enum PersistenceBlock {
  /// A commit saw a revision this instance did not have.
  revisionConflict,

  /// Storage could not be opened.
  storageUnavailable,

  /// A write or a reload did not finish.
  storageFailed,

  /// Stored records failed validation.
  corrupted,

  /// Stored records use an unsupported schema.
  unsupportedVersion,

  /// The next revision would leave the safe integer range.
  revisionOverflow,
}

/// Coordinates fulfilment commands with [FulfilmentRepository].
///
/// Domain checks stay in [FulfilmentSession]. This service persists a
/// candidate and only then makes that candidate the active session.
/// Dataset replacement and cumulative export commits are repository
/// operations; their application workflows are later phases and do not
/// report success from here.
class FulfilmentApplication {
  /// Creates a service that reads and writes through [repository].
  ///
  /// [onCommitted] runs synchronously after a successful commit is this
  /// instance's active state. The arguments are the decimal revision text
  /// and the dataset fingerprint. An exception from [onCommitted] is ignored.
  /// Load and reload do not call it.
  FulfilmentApplication({
    required this.repository,
    DatasetByteRestore? datasets,
    CumulativeJsonExport? exports,
    this.onCommitted,
  }) : _datasets = datasets ?? const DatasetByteRestore(),
       _exports = exports ?? const CumulativeJsonExport();

  /// Persistence port. Tests supply an in-memory implementation.
  final FulfilmentRepository repository;

  /// Called after a successful commit is the active state.
  ///
  /// The first argument is [revision] as decimal text. The second is
  /// [fingerprint]. Null when the caller does not need commit notifications.
  final void Function(String revision, String fingerprint)? onCommitted;

  final DatasetByteRestore _datasets;
  final CumulativeJsonExport _exports;
  Future<void> _tail = Future<void>.value();

  FulfilmentSession? _session;
  int? _revision;
  String? _fingerprint;
  ExportDocument? _export;
  PersistenceBlock? _block;

  /// Active session, or null when nothing has been restored.
  FulfilmentSession? get session => _session;

  /// Revision of [session], or null when no session is active.
  int? get revision => _revision;

  /// Fingerprint of the active dataset bytes, when a session is active.
  String? get fingerprint => _fingerprint;

  /// Last export restored with the active session.
  ExportDocument? get lastExport => _export;

  /// Block applied after a failed commit or a failed reload.
  PersistenceBlock? get block => _block;

  /// Whether a business mutation may run.
  bool get canMutate => _block == null && _session != null;

  /// Reads storage and installs the result.
  Future<LoadResult> load() => _serialized(_applyLoad);

  /// Reads storage again after a failed commit.
  ///
  /// A [LoadReady] or [LoadEmpty] result clears [block]. Any other result
  /// leaves mutations blocked.
  Future<LoadResult> reload() => load();

  /// Imports [bytes] when this instance has no active session.
  ///
  /// The bytes are parsed before the repository is asked to store them.
  /// The opened session becomes active only after the import commit finishes.
  Future<FulfilmentImportResult> importDataset(Uint8List bytes) {
    return _serialized(() async {
      if (_block != null) return FulfilmentImportBlocked(_block!);
      if (_session != null) return const FulfilmentImportOccupied();

      final fingerprint = DatasetFingerprint.of(bytes);
      final restored = _datasets.restore(
        bytes: bytes,
        expectedFingerprint: fingerprint,
      );
      if (restored is! DatasetRestored) {
        return FulfilmentImportRejected(restored as DatasetRestoreRejected);
      }
      switch (FulfilmentSession.open(restored.dataset)) {
        case DatasetRejected(:final problem):
          return FulfilmentDatasetRejected(problem);
        case DatasetOpened(:final session):
          final committed = await repository.importDataset(
            bytes: bytes,
            fingerprint: restored.fingerprint,
            snapshot: session.capture(datasetFingerprint: restored.fingerprint),
          );
          if (committed is! CommitSucceeded) {
            _block = _blockFor(committed);
            return FulfilmentImportFailed(_block!);
          }
          _session = session;
          _revision = committed.revision;
          _fingerprint = restored.fingerprint;
          _export = null;
          _notifyCommitted();
          return FulfilmentImported(
            session: session,
            revision: committed.revision,
            fingerprint: restored.fingerprint,
          );
      }
    });
  }

  /// Reserves units, then persists the candidate session.
  Future<FulfilmentCommandResult<ReserveResult>> reserve({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
    List<String> exciseStamps = const [],
  }) {
    return _mutate((session) {
      final result = session.reserve(
        orderId: orderId,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        quantity: quantity,
        exciseStamps: exciseStamps,
      );
      return (
        result: result,
        candidate: result is ReserveApplied ? result.session : null,
        unchanged: false,
      );
    });
  }

  /// Removes reserved units, then persists the candidate session.
  Future<FulfilmentCommandResult<RemoveUnitsResult>> removeUnits({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
  }) {
    return _mutate((session) {
      final result = session.removeUnits(
        orderId: orderId,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        quantity: quantity,
      );
      return (
        result: result,
        candidate: result is UnitsRemoved ? result.session : null,
        unchanged: false,
      );
    });
  }

  /// Removes one alcohol unit by its stamp, then persists the candidate.
  ///
  /// A rejection, including a stamp that is not on the slot, does not write.
  /// A revision conflict blocks this instance. The caller reloads and retries.
  Future<FulfilmentCommandResult<RemoveUnitsResult>> removeAlcoholUnit({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required String exciseStamp,
  }) {
    return _mutate((session) {
      final result = session.removeAlcoholUnit(
        orderId: orderId,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        exciseStamp: exciseStamp,
      );
      return (
        result: result,
        candidate: result is UnitsRemoved ? result.session : null,
        unchanged: false,
      );
    });
  }

  /// Clears one order's reservations when that changes the session.
  ///
  /// An order that holds nothing is a no-op: storage and the revision stay
  /// as they are.
  Future<FulfilmentCommandResult<ClearOrderResult>> clearOrder(String orderId) {
    return _mutate((session) {
      final result = session.clearOrder(orderId);
      return switch (result) {
        OrderCleared(:final session, :final clearedQuantity)
            when clearedQuantity > 0 =>
          (result: result, candidate: session, unchanged: false),
        OrderCleared() => (result: result, candidate: null, unchanged: true),
        _ => (result: result, candidate: null, unchanged: false),
      };
    });
  }

  /// Issues a ready order, then persists the candidate session.
  Future<FulfilmentCommandResult<IssueOrderResult>> issueOrder(String orderId) {
    return _mutate((session) {
      final result = session.issueOrder(orderId);
      return (
        result: result,
        candidate: result is OrderIssued ? result.session : null,
        unchanged: false,
      );
    });
  }

  /// Cancels an issuance, then persists the candidate session.
  Future<FulfilmentCommandResult<CancelIssuanceResult>> cancelIssuance(
    String orderId,
  ) {
    return _mutate((session) {
      final result = session.cancelIssuance(orderId);
      return (
        result: result,
        candidate: result is IssuanceCancelled ? result.session : null,
        unchanged: false,
      );
    });
  }

  /// Replaces the active dataset when the domain allows it.
  ///
  /// [originalBytes] are hashed and parsed before
  /// [FulfilmentSession.replaceDataset] runs. A parser or domain rejection
  /// does not write and does not block later commands. A new session becomes
  /// active only after the repository commit finishes. That commit replaces
  /// the bytes, fingerprint, and snapshot, removes the previous export, and
  /// increments the revision once.
  ///
  /// [confirmedRevision] is the revision a confirmation displayed. When it
  /// is set and the live revision inside this serialized operation is
  /// different, the result is [FulfilmentReplacementStale]. Nothing is
  /// parsed, written, or blocked, and the call is not repeated. Omitting it
  /// keeps the previous behavior.
  Future<FulfilmentReplacementResult> replaceDataset(
    Uint8List originalBytes, {
    int? confirmedRevision,
  }) {
    return _serialized(() async {
      if (_block != null) return FulfilmentReplacementBlocked(_block!);
      final current = _session;
      final revision = _revision;
      if (current == null || revision == null || _fingerprint == null) {
        return const FulfilmentReplacementNotReady();
      }
      if (confirmedRevision != null && confirmedRevision != revision) {
        return FulfilmentReplacementStale(revision);
      }

      final fingerprint = DatasetFingerprint.of(originalBytes);
      switch (_datasets.restore(
        bytes: originalBytes,
        expectedFingerprint: fingerprint,
      )) {
        case DatasetRestoreRejected() && final failure:
          return FulfilmentReplacementInputRejected(failure);
        case DatasetRestored(:final dataset, :final fingerprint):
          switch (current.replaceDataset(dataset)) {
            case DatasetReplaced(:final session):
              final committed = await repository.replaceDataset(
                expectedRevision: revision,
                bytes: originalBytes,
                fingerprint: fingerprint,
                snapshot: session.capture(datasetFingerprint: fingerprint),
              );
              if (committed is! CommitSucceeded) {
                _block = _blockFor(committed);
                return FulfilmentReplacementFailed(_block!);
              }
              _session = session;
              _revision = committed.revision;
              _fingerprint = fingerprint;
              _export = null;
              _notifyCommitted();
              return FulfilmentReplaced(
                session: session,
                revision: committed.revision,
                fingerprint: fingerprint,
              );
            case final ReplaceDatasetResult rejected:
              return FulfilmentReplacementRejected(rejected);
          }
      }
    });
  }

  /// Persists a cumulative export of every newly issued order.
  ///
  /// [now] supplies the local clock used by [CumulativeJsonExport.prepare].
  /// It is omitted when there is nothing new to export. A prepared export
  /// becomes active only after [FulfilmentRepository.commitExport] finishes.
  /// That commit stores the pending snapshot and the export file together
  /// and increments the revision once. The dataset bytes stay as they are.
  Future<FulfilmentExportResult> commitCumulativeExport({
    DateTime Function()? now,
  }) {
    return _serialized(() async {
      if (_block != null) return FulfilmentExportBlocked(_block!);
      final current = _session;
      final revision = _revision;
      final fingerprint = _fingerprint;
      if (current == null || revision == null || fingerprint == null) {
        return const FulfilmentExportNotReady();
      }

      switch (_exports.prepare(current, now: now)) {
        case CumulativeExportRejected(:final failures):
          return FulfilmentExportRejected(failures);
        case CumulativeExportUnchanged():
          return FulfilmentExportUnchanged(revision: revision);
        case CumulativeExportPrepared(:final pendingSession, :final document):
          final committed = await repository.commitExport(
            expectedRevision: revision,
            snapshot: pendingSession.capture(datasetFingerprint: fingerprint),
            document: document,
          );
          if (committed is! CommitSucceeded) {
            _block = _blockFor(committed);
            return FulfilmentExportFailed(_block!);
          }
          _session = pendingSession;
          _revision = committed.revision;
          _export = document;
          _notifyCommitted();
          return FulfilmentExported(
            session: pendingSession,
            revision: committed.revision,
            document: document,
          );
      }
    });
  }

  Future<FulfilmentCommandResult<T>> _mutate<T>(
    ({T result, FulfilmentSession? candidate, bool unchanged}) Function(
      FulfilmentSession session,
    )
    operation,
  ) {
    return _serialized(() async {
      if (_block != null) return FulfilmentBlocked<T>(_block!);
      final current = _session;
      final revision = _revision;
      final fingerprint = _fingerprint;
      if (current == null || revision == null || fingerprint == null) {
        return FulfilmentNotReady<T>();
      }
      final outcome = operation(current);
      final candidate = outcome.candidate;
      if (candidate == null) {
        if (outcome.unchanged) {
          return FulfilmentUnchanged<T>(outcome.result, revision: revision);
        }
        return FulfilmentDomainRejected<T>(outcome.result);
      }
      final committed = await repository.commitSession(
        expectedRevision: revision,
        snapshot: candidate.capture(datasetFingerprint: fingerprint),
      );
      if (committed is! CommitSucceeded) {
        _block = _blockFor(committed);
        return FulfilmentBlocked<T>(_block!);
      }
      _session = candidate;
      _revision = committed.revision;
      _notifyCommitted();
      return FulfilmentCommitted<T>(
        outcome.result,
        session: candidate,
        revision: committed.revision,
      );
    });
  }

  Future<LoadResult> _applyLoad() async {
    final result = await repository.load();
    switch (result) {
      case LoadEmpty():
        _session = null;
        _revision = null;
        _fingerprint = null;
        _export = null;
        _block = null;
      case LoadReady(:final state):
        _session = state.session;
        _revision = state.revision;
        _fingerprint = state.fingerprint;
        _export = state.export;
        _block = null;
      case LoadStorageUnavailable():
        _block = PersistenceBlock.storageUnavailable;
      case LoadStorageFailed():
        _block = PersistenceBlock.storageFailed;
      case LoadCorrupted():
        _block = PersistenceBlock.corrupted;
      case LoadUnsupportedVersion():
        _block = PersistenceBlock.unsupportedVersion;
    }
    return result;
  }

  /// Notifies [onCommitted] with the revision and fingerprint already stored.
  ///
  /// Runs only after a [CommitSucceeded] assignment. A callback failure cannot
  /// change that assignment or the command result.
  void _notifyCommitted() {
    final notify = onCommitted;
    final revision = _revision;
    final fingerprint = _fingerprint;
    if (notify == null || revision == null || fingerprint == null) {
      return;
    }
    try {
      notify(revision.toString(), fingerprint);
    } catch (_) {
      // The commit already succeeded. The callback cannot undo it.
    }
  }

  PersistenceBlock _blockFor(CommitResult result) {
    return switch (result) {
      CommitSucceeded() => throw StateError(
        'A finished commit is not a block.',
      ),
      CommitRevisionConflict() => PersistenceBlock.revisionConflict,
      CommitStorageUnavailable() => PersistenceBlock.storageUnavailable,
      CommitStorageFailed() => PersistenceBlock.storageFailed,
      CommitCorrupted() => PersistenceBlock.corrupted,
      CommitUnsupportedVersion() => PersistenceBlock.unsupportedVersion,
      CommitRevisionOverflow() => PersistenceBlock.revisionOverflow,
      CommitRejected() => PersistenceBlock.storageFailed,
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

/// Result of [FulfilmentApplication.importDataset].
@immutable
sealed class FulfilmentImportResult {
  const FulfilmentImportResult();
}

/// The imported session is active at [revision].
final class FulfilmentImported extends FulfilmentImportResult {
  /// Creates a successful import result.
  const FulfilmentImported({
    required this.session,
    required this.revision,
    required this.fingerprint,
  });

  /// Empty session opened from the imported dataset.
  final FulfilmentSession session;

  /// Stored revision. The first import is 1.
  final int revision;

  /// SHA-256 hex of the imported bytes.
  final String fingerprint;
}

/// The file could not be restored. Storage was not written.
final class FulfilmentImportRejected extends FulfilmentImportResult {
  /// Creates a rejected-file result.
  const FulfilmentImportRejected(this.failure);

  /// Parser or fingerprint failure for the supplied bytes.
  final DatasetRestoreRejected failure;
}

/// The dataset text parsed and [FulfilmentSession.open] rejected it.
final class FulfilmentDatasetRejected extends FulfilmentImportResult {
  /// Creates a rejected-dataset result.
  const FulfilmentDatasetRejected(this.problem);

  /// Duplicate identity that prevented the dataset from opening.
  final DatasetProblem problem;
}

/// This instance already has an active session, so import did not write.
final class FulfilmentImportOccupied extends FulfilmentImportResult {
  /// Creates an occupied-store result.
  const FulfilmentImportOccupied();
}

/// Import was refused because mutations are blocked.
final class FulfilmentImportBlocked extends FulfilmentImportResult {
  /// Creates a blocked-import result.
  const FulfilmentImportBlocked(this.block);

  /// Reason mutations are suspended.
  final PersistenceBlock block;
}

/// The import commit did not finish, and the candidate is not active.
final class FulfilmentImportFailed extends FulfilmentImportResult {
  /// Creates a failed-import result.
  const FulfilmentImportFailed(this.block);

  /// Reason later mutations stay suspended until a successful reload.
  final PersistenceBlock block;
}

/// Result of [FulfilmentApplication.replaceDataset].
@immutable
sealed class FulfilmentReplacementResult {
  const FulfilmentReplacementResult();
}

/// The replacement commit finished and [session] is now active.
final class FulfilmentReplaced extends FulfilmentReplacementResult {
  /// Creates a successful replacement result.
  const FulfilmentReplaced({
    required this.session,
    required this.revision,
    required this.fingerprint,
  });

  /// Empty session opened from the replacement dataset.
  final FulfilmentSession session;

  /// Revision stored with this replacement.
  final int revision;

  /// SHA-256 hex of the replacement bytes.
  final String fingerprint;
}

/// The replacement file could not be restored. Storage was not written.
final class FulfilmentReplacementInputRejected
    extends FulfilmentReplacementResult {
  /// Creates a rejected-file result.
  const FulfilmentReplacementInputRejected(this.failure);

  /// UTF-8, JSON, or dataset-validation failure for the supplied bytes.
  final DatasetRestoreRejected failure;
}

/// [FulfilmentSession.replaceDataset] refused the dataset.
///
/// Storage was not written and mutations stay available.
final class FulfilmentReplacementRejected extends FulfilmentReplacementResult {
  /// Creates a domain-rejection result.
  const FulfilmentReplacementRejected(this.result);

  /// [ReplacementBlocked] or [ReplacementRejected].
  final ReplaceDatasetResult result;
}

/// No session is active, so the replacement was not evaluated.
final class FulfilmentReplacementNotReady extends FulfilmentReplacementResult {
  /// Creates a not-ready result.
  const FulfilmentReplacementNotReady();
}

/// Replacement was refused because mutations are already blocked.
final class FulfilmentReplacementBlocked extends FulfilmentReplacementResult {
  /// Creates a blocked-replacement result.
  const FulfilmentReplacementBlocked(this.block);

  /// Reason mutations are suspended.
  final PersistenceBlock block;
}

/// The revision captured for a confirmation is no longer the live revision.
///
/// Storage was not written. [block] stays clear, and the call is not
/// repeated. [revision] is the live revision observed inside the serialized
/// operation.
final class FulfilmentReplacementStale extends FulfilmentReplacementResult {
  /// Creates a stale-confirmation result.
  const FulfilmentReplacementStale(this.revision);

  /// Revision that was current when the replacement was refused.
  final int revision;

  @override
  String toString() => 'FulfilmentReplacementStale($revision)';
}

/// The replacement commit did not finish, and the candidate is not active.
final class FulfilmentReplacementFailed extends FulfilmentReplacementResult {
  /// Creates a failed-replacement result.
  const FulfilmentReplacementFailed(this.block);

  /// Reason later mutations stay suspended until a successful reload.
  final PersistenceBlock block;
}

/// Result of [FulfilmentApplication.commitCumulativeExport].
@immutable
sealed class FulfilmentExportResult {
  const FulfilmentExportResult();
}

/// The export commit finished and [session] is now active.
final class FulfilmentExported extends FulfilmentExportResult {
  /// Creates a successful export result.
  const FulfilmentExported({
    required this.session,
    required this.revision,
    required this.document,
  });

  /// Session in which the newly issued orders are exported.
  final FulfilmentSession session;

  /// Revision stored with this export.
  final int revision;

  /// Cumulative file stored with [session].
  final ExportDocument document;
}

/// No newly issued order was found, so the revision was not incremented.
final class FulfilmentExportUnchanged extends FulfilmentExportResult {
  /// Creates an unchanged-export result.
  const FulfilmentExportUnchanged({required this.revision});

  /// Revision that was already stored.
  final int revision;
}

/// [CumulativeJsonExport.prepare] refused the export. Storage was not written.
final class FulfilmentExportRejected extends FulfilmentExportResult {
  /// Creates a rejected-export result.
  const FulfilmentExportRejected(this.failures);

  /// Reasons reported by the export builder, in discovery order.
  final List<CumulativeExportFailure> failures;
}

/// No session is active, so the export was not evaluated.
final class FulfilmentExportNotReady extends FulfilmentExportResult {
  /// Creates a not-ready result.
  const FulfilmentExportNotReady();
}

/// Export was refused because mutations are already blocked.
final class FulfilmentExportBlocked extends FulfilmentExportResult {
  /// Creates a blocked-export result.
  const FulfilmentExportBlocked(this.block);

  /// Reason mutations are suspended.
  final PersistenceBlock block;
}

/// The export commit did not finish, and the pending session is not active.
final class FulfilmentExportFailed extends FulfilmentExportResult {
  /// Creates a failed-export result.
  const FulfilmentExportFailed(this.block);

  /// Reason later mutations stay suspended until a successful reload.
  final PersistenceBlock block;
}

/// Result of a fulfilment command other than import.
@immutable
sealed class FulfilmentCommandResult<T> {
  const FulfilmentCommandResult();
}

/// [result] was persisted and [session] is now active.
final class FulfilmentCommitted<T> extends FulfilmentCommandResult<T> {
  /// Creates a committed-command result.
  const FulfilmentCommitted(
    this.result, {
    required this.session,
    required this.revision,
  });

  /// Domain success value.
  final T result;

  /// Candidate that became active after the commit finished.
  final FulfilmentSession session;

  /// Revision stored with [session].
  final int revision;
}

/// The domain made no change, so the revision was not incremented.
final class FulfilmentUnchanged<T> extends FulfilmentCommandResult<T> {
  /// Creates an unchanged-command result.
  const FulfilmentUnchanged(this.result, {required this.revision});

  /// Domain no-op value.
  final T result;

  /// Revision that was already stored.
  final int revision;
}

/// The domain rejected the command. Storage was not written.
final class FulfilmentDomainRejected<T> extends FulfilmentCommandResult<T> {
  /// Creates a domain-rejection result.
  const FulfilmentDomainRejected(this.result);

  /// Domain failure value.
  final T result;
}

/// No session is active, so the command was not evaluated.
final class FulfilmentNotReady<T> extends FulfilmentCommandResult<T> {
  /// Creates a not-ready result.
  const FulfilmentNotReady();
}

/// Mutations are suspended. The command was not evaluated again.
final class FulfilmentBlocked<T> extends FulfilmentCommandResult<T> {
  /// Creates a blocked-command result.
  const FulfilmentBlocked(this.block);

  /// Reason mutations are suspended.
  final PersistenceBlock block;
}
