import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/fulfilment/fulfilment_session.dart';
import '../persistence/fulfilment_repository.dart';
import '../services/json/cumulative_json_export.dart';
import 'fulfilment_application.dart';
import 'fulfilment_tab_coordinator.dart';
import 'page_visibility.dart';

/// What the UI may show and which commands it may send.
enum FulfilmentUiPhase {
  /// The first storage read has not finished.
  loading,

  /// Storage was read and no session is stored.
  empty,

  /// A session is active and mutations are allowed.
  ready,

  /// A persistence block or an unverified failure suspends mutations.
  blocked,
}

/// Presents one [FulfilmentTabCoordinator] to widgets.
///
/// The phase is derived from the live [FulfilmentApplication] after each
/// installed reload. This controller does not keep a session, and it does
/// not decide whether a reservation, issuance, or dataset is valid.
final class FulfilmentUiController extends ChangeNotifier {
  /// Opens [coordinator] and starts the first [FulfilmentTabCoordinator.reload].
  ///
  /// The reload callback is connected before this controller is returned.
  /// The first read is scheduled, not awaited, so the phase is
  /// [FulfilmentUiPhase.loading] until that read settles. [repository] and
  /// [databaseName] are forwarded to the coordinator. [transport],
  /// [visibility], and [senderId] replace the browser implementations in
  /// tests.
  factory FulfilmentUiController.open({
    required FulfilmentRepository repository,
    required String databaseName,
    StorageChangeTransport? transport,
    PageVisibility? visibility,
    String? senderId,
  }) {
    late FulfilmentUiController controller;
    final coordinator = FulfilmentTabCoordinator.open(
      repository: repository,
      databaseName: databaseName,
      transport: transport,
      visibility: visibility,
      senderId: senderId,
      onReloaded: (_) {
        controller._onReloaded();
      },
    );
    controller = FulfilmentUiController._(coordinator);
    controller._kickoff();
    return controller;
  }

  FulfilmentUiController._(this.coordinator);

  /// Coordinator created for this controller.
  ///
  /// The controller closes it on [dispose]. The repository stays open.
  final FulfilmentTabCoordinator coordinator;

  var _disposed = false;
  var _settled = false;
  var _commandInFlight = false;
  var _refreshInFlight = false;
  Object? _operationError;

  /// Active session, or `null` when the application has none.
  ///
  /// This is [FulfilmentApplication.session]. It is not a copy.
  FulfilmentSession? get session => coordinator.application.session;

  /// Persistence block on the application, or `null` when none is set.
  PersistenceBlock? get block => coordinator.application.block;

  /// Revision of [session], or `null` when no session is active.
  int? get revision => coordinator.application.revision;

  /// Fingerprint of the active dataset, or `null` when no session is active.
  String? get fingerprint => coordinator.application.fingerprint;

  /// Last export restored with [session], or `null` when there is none.
  ExportDocument? get lastExport => coordinator.application.lastExport;

  /// Whether a business command may be dispatched.
  ///
  /// False during [FulfilmentUiPhase.loading], while storage is empty or
  /// blocked, and while [operationError] is set. An in-flight command does
  /// not by itself make this false; [commandInFlight] reports that.
  bool get canMutate =>
      phase == FulfilmentUiPhase.ready && coordinator.application.canMutate;

  /// Phase derived from startup, [operationError], [block], and [session].
  FulfilmentUiPhase get phase {
    if (!_settled) return FulfilmentUiPhase.loading;
    if (_operationError != null || block != null) {
      return FulfilmentUiPhase.blocked;
    }
    if (session != null) return FulfilmentUiPhase.ready;
    return FulfilmentUiPhase.empty;
  }

  /// Whether a UI command has been dispatched and has not finished.
  bool get commandInFlight => _commandInFlight;

  /// Whether an explicit [refresh] has been dispatched and has not finished.
  ///
  /// The startup read and a coordinator reload do not set this.
  bool get refreshInFlight => _refreshInFlight;

  /// Unexpected failure from the startup read, [refresh], or a command.
  ///
  /// A typed application result is not stored here. A later installed reload
  /// clears it. `null` when the last settled read or command did not throw.
  Object? get operationError => _operationError;

  /// Reads storage again when no UI command or refresh is in flight.
  ///
  /// Returns `null` without reading when this controller is disposed, the
  /// startup read has not settled, or a command or refresh is already in
  /// flight. A remote notice and a page resume are not refused here.
  ///
  /// The returned [LoadResult] is the coordinator's result. The phase follows
  /// the application after that read is installed, not this future's value.
  /// A throw is recorded in [operationError], the phase becomes
  /// [FulfilmentUiPhase.blocked], and the error is propagated to the caller.
  Future<LoadResult?> refresh() {
    return _run<LoadResult>(
      allowed: _settled,
      refresh: true,
      action: coordinator.reload,
    );
  }

  /// Imports [bytes] when the phase is [FulfilmentUiPhase.empty].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentImportResult?> importDataset(Uint8List bytes) {
    return _run<FulfilmentImportResult>(
      allowed: phase == FulfilmentUiPhase.empty,
      refresh: false,
      action: () => coordinator.application.importDataset(bytes),
    );
  }

  /// Replaces the dataset when the phase is [FulfilmentUiPhase.ready].
  ///
  /// [confirmedRevision] is forwarded to
  /// [FulfilmentApplication.replaceDataset]. Returns `null` when the command
  /// is not dispatched. Otherwise returns the application's result unchanged.
  Future<FulfilmentReplacementResult?> replaceDataset(
    Uint8List originalBytes, {
    int? confirmedRevision,
  }) {
    return _mutate(
      () => coordinator.application.replaceDataset(
        originalBytes,
        confirmedRevision: confirmedRevision,
      ),
    );
  }

  /// Reserves units when the phase is [FulfilmentUiPhase.ready].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentCommandResult<ReserveResult>?> reserve({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
  }) {
    return _mutate(
      () => coordinator.application.reserve(
        orderId: orderId,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        quantity: quantity,
      ),
    );
  }

  /// Removes reserved units when the phase is [FulfilmentUiPhase.ready].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentCommandResult<RemoveUnitsResult>?> removeUnits({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
  }) {
    return _mutate(
      () => coordinator.application.removeUnits(
        orderId: orderId,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        quantity: quantity,
      ),
    );
  }

  /// Clears one order when the phase is [FulfilmentUiPhase.ready].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentCommandResult<ClearOrderResult>?> clearOrder(
    String orderId,
  ) {
    return _mutate(() => coordinator.application.clearOrder(orderId));
  }

  /// Issues one order when the phase is [FulfilmentUiPhase.ready].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentCommandResult<IssueOrderResult>?> issueOrder(
    String orderId,
  ) {
    return _mutate(() => coordinator.application.issueOrder(orderId));
  }

  /// Cancels one issuance when the phase is [FulfilmentUiPhase.ready].
  ///
  /// Returns `null` when the command is not dispatched. Otherwise returns
  /// the application's result unchanged.
  Future<FulfilmentCommandResult<CancelIssuanceResult>?> cancelIssuance(
    String orderId,
  ) {
    return _mutate(() => coordinator.application.cancelIssuance(orderId));
  }

  /// Commits a cumulative export when the phase is [FulfilmentUiPhase.ready].
  ///
  /// [now] is forwarded to the application. Returns `null` when the command
  /// is not dispatched. Otherwise returns the application's result unchanged.
  Future<FulfilmentExportResult?> commitCumulativeExport({
    DateTime Function()? now,
  }) {
    return _mutate(
      () => coordinator.application.commitCumulativeExport(now: now),
    );
  }

  /// Marks this controller disposed and closes [coordinator].
  ///
  /// A second call does nothing. The repository and its records stay
  /// untouched. A command or reload that is already running may finish,
  /// and that completion does not notify listeners.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
    coordinator.close();
  }

  void _kickoff() {
    unawaited(_startup());
  }

  Future<void> _startup() async {
    try {
      await coordinator.reload();
    } on Object catch (error) {
      // A read installed while this future was waiting is already settled.
      if (_disposed || _settled) return;
      _operationError = error;
      _settled = true;
      _notify();
    }
  }

  // The application already installed this read. Do not reload or command.
  void _onReloaded() {
    if (_disposed) return;
    _operationError = null;
    _settled = true;
    _notify();
  }

  Future<T?> _mutate<T>(Future<T> Function() action) {
    return _run<T>(
      allowed:
          phase == FulfilmentUiPhase.ready && coordinator.application.canMutate,
      refresh: false,
      action: action,
    );
  }

  Future<T?> _run<T>({
    required bool allowed,
    required bool refresh,
    required Future<T> Function() action,
  }) {
    if (_disposed || !allowed || _commandInFlight || _refreshInFlight) {
      return Future<T?>.value(null);
    }
    if (refresh) {
      _refreshInFlight = true;
    } else {
      _commandInFlight = true;
    }
    _notify();
    return _guard(action, refresh);
  }

  Future<T?> _guard<T>(Future<T> Function() action, bool refresh) async {
    try {
      return await action();
    } on Object catch (error) {
      // The throw may follow a read that finished before this attempt.
      // That read does not show whether the attempt reached storage.
      if (!_disposed) {
        _operationError = error;
        _settled = true;
      }
      rethrow;
    } finally {
      if (refresh) {
        _refreshInFlight = false;
      } else {
        _commandInFlight = false;
      }
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
