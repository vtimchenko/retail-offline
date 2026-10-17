import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/fulfilment_application.dart';
import '../../application/fulfilment_scope.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../models/retail_dataset.dart';
import '../../persistence/dataset_fingerprint.dart';
import '../../services/file/json_file_service.dart';
import 'json_dataset_messages.dart';

/// Whether [session] has an issued order that has not been exported.
///
/// This is the same rule as [FulfilmentSession.replaceDataset]. The domain
/// check at commit time remains the authority.
bool sessionHasUnexportedIssued(FulfilmentSession session) {
  for (final order in session.dataset.orders) {
    if (session.statusOf(order.orderId) == OrderStatus.issued) return true;
  }
  return false;
}

/// **Завантажити новий JSON** for a ready fulfilment session.
///
/// The button opens a local JSON file. Parsing the preview does not write.
/// Confirmation passes the revision captured with the dialog to
/// [FulfilmentUiController.replaceDataset]. A reload that changes that
/// revision or fingerprint closes the dialog without replacing.
class DatasetReplacementAction extends StatefulWidget {
  /// Creates the replacement action.
  ///
  /// [fileService] replaces the browser chooser in tests. Production uses
  /// [JsonFileService].
  const DatasetReplacementAction({super.key, this.fileService});

  /// Local JSON chooser.
  final JsonFileService? fileService;

  @override
  State<DatasetReplacementAction> createState() =>
      _DatasetReplacementActionState();
}

class _DatasetReplacementActionState extends State<DatasetReplacementAction> {
  var _busy = false;
  String? _message;

  JsonFileService get _files => widget.fileService ?? const JsonFileService();

  void _start() {
    if (_busy) return;
    final controller = FulfilmentScope.read(context);
    if (!_canStart(controller)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    // The chooser must open before the first await.
    final pending = _files.pickJsonBytes();
    unawaited(_afterPick(pending));
  }

  Future<void> _afterPick(Future<Uint8List?> pending) async {
    try {
      await _replaceFrom(pending);
    } on Object catch (error, stackTrace) {
      debugPrint('Dataset replacement failed: $error\n$stackTrace');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replaceFrom(Future<Uint8List?> pending) async {
    Uint8List? bytes;
    Object? pickError;
    try {
      bytes = await pending;
    } on Object catch (error) {
      pickError = error;
    }
    if (!mounted) return;
    if (pickError != null) {
      final message = pickError is ImportException
          ? pickError.message
          : ImportMessages.fileReadFailed;
      setState(() => _message = message);
      return;
    }
    if (bytes == null) return;

    final preview = _preview(bytes);
    if (!mounted) return;
    if (preview is _PreviewRejected) {
      setState(() => _message = preview.message);
      return;
    }
    final opened = preview as _PreviewReady;

    final controller = FulfilmentScope.read(context);
    final session = controller.session;
    if (session == null ||
        controller.phase != FulfilmentUiPhase.ready ||
        !controller.canMutate) {
      return;
    }
    if (sessionHasUnexportedIssued(session)) {
      setState(() => _message = AppStrings.jsonReplaceExportFirst);
      return;
    }
    final revision = controller.revision;
    final fingerprint = controller.fingerprint;
    if (revision == null || fingerprint == null) return;

    final decision = await showDialog<_ReplacementDecision>(
      context: context,
      builder: (dialogContext) {
        return _DatasetReplacementDialog(
          controller: controller,
          capturedRevision: revision,
          capturedFingerprint: fingerprint,
          currentStoreName: session.dataset.storeName,
          currentDbName: session.dataset.dbName,
          nextStoreName: opened.dataset.storeName,
          nextDbName: opened.dataset.dbName,
        );
      },
    );
    if (!mounted) return;
    switch (decision) {
      case null:
      case _ReplacementDecision.cancelled:
        return;
      case _ReplacementDecision.stale:
        setState(() => _message = AppStrings.jsonReplaceStale);
        return;
      case _ReplacementDecision.confirmed:
        break;
    }

    final FulfilmentReplacementResult? result;
    try {
      result = await controller.replaceDataset(
        bytes,
        confirmedRevision: revision,
      );
    } on Object {
      // operationError is already recorded. The blocked view explains it.
      return;
    }
    if (!mounted) return;
    _accept(result);
  }

  void _accept(FulfilmentReplacementResult? result) {
    switch (result) {
      case null:
      case FulfilmentReplacementNotReady():
      case FulfilmentReplaced():
        setState(() => _message = null);
      case FulfilmentReplacementInputRejected(:final failure):
        setState(() => _message = jsonDatasetRestoreMessage(failure));
      case FulfilmentReplacementRejected(:final result):
        setState(() => _message = _rejectionMessage(result));
      case FulfilmentReplacementStale():
        setState(() => _message = AppStrings.jsonReplaceStale);
      case FulfilmentReplacementBlocked():
      case FulfilmentReplacementFailed():
        if (FulfilmentScope.read(context).phase == FulfilmentUiPhase.ready) {
          setState(() => _message = null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    final session = controller.session;
    final issued = session != null && sessionHasUnexportedIssued(session);
    final message = _message;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issued)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              AppStrings.jsonReplaceExportFirst,
              key: const Key('json-replace-blocked'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        OutlinedButton(
          key: const Key('json-replace-dataset'),
          onPressed: _canStart(controller) ? _start : null,
          child: _busy
              ? const SizedBox(
                  key: Key('json-replace-progress'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  AppStrings.jsonReplaceDataset,
                  textAlign: TextAlign.center,
                ),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message,
            key: const Key('json-replace-error'),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  bool _canStart(FulfilmentUiController controller) {
    if (_busy) return false;
    if (controller.phase != FulfilmentUiPhase.ready || !controller.canMutate) {
      return false;
    }
    if (controller.commandInFlight || controller.refreshInFlight) return false;
    final session = controller.session;
    if (session == null || sessionHasUnexportedIssued(session)) return false;
    return true;
  }
}

_Preview _preview(Uint8List bytes) {
  final restored = const DatasetByteRestore().restore(
    bytes: bytes,
    expectedFingerprint: DatasetFingerprint.of(bytes),
  );
  if (restored is! DatasetRestored) {
    return _PreviewRejected(
      jsonDatasetRestoreMessage(restored as DatasetRestoreRejected),
    );
  }
  return switch (FulfilmentSession.open(restored.dataset)) {
    DatasetRejected(:final problem) => _PreviewRejected(
      jsonDatasetProblemMessage(problem),
    ),
    DatasetOpened(:final session) => _PreviewReady(session.dataset),
  };
}

String _rejectionMessage(ReplaceDatasetResult result) {
  return switch (result) {
    DatasetReplaced() => AppStrings.jsonReplaceExportFirst,
    ReplacementBlocked() => AppStrings.jsonReplaceExportFirst,
    ReplacementRejected(:final problem) => jsonDatasetProblemMessage(problem),
  };
}

sealed class _Preview {
  const _Preview();
}

final class _PreviewReady extends _Preview {
  const _PreviewReady(this.dataset);

  final RetailDataset dataset;
}

final class _PreviewRejected extends _Preview {
  const _PreviewRejected(this.message);

  final String message;
}

enum _ReplacementDecision { confirmed, cancelled, stale }

/// Confirmation bound to the revision and fingerprint it displayed.
///
/// A later controller notification that changes either value closes this
/// dialog. The labels stay on the values captured when it opened.
class _DatasetReplacementDialog extends StatefulWidget {
  const _DatasetReplacementDialog({
    required this.controller,
    required this.capturedRevision,
    required this.capturedFingerprint,
    required this.currentStoreName,
    required this.currentDbName,
    required this.nextStoreName,
    required this.nextDbName,
  });

  final FulfilmentUiController controller;
  final int capturedRevision;
  final String capturedFingerprint;
  final String currentStoreName;
  final String currentDbName;
  final String nextStoreName;
  final String nextDbName;

  @override
  State<_DatasetReplacementDialog> createState() =>
      _DatasetReplacementDialogState();
}

class _DatasetReplacementDialogState extends State<_DatasetReplacementDialog> {
  var _closed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (_closed || !mounted) return;
    if (widget.controller.revision == widget.capturedRevision &&
        widget.controller.fingerprint == widget.capturedFingerprint) {
      return;
    }
    _finish(_ReplacementDecision.stale);
  }

  void _finish(_ReplacementDecision decision) {
    if (_closed) return;
    _closed = true;
    widget.controller.removeListener(_onController);
    Navigator.of(context).pop(decision);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final heading = textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return AlertDialog(
      key: const Key('json-replace-dialog'),
      title: const Text(AppStrings.jsonReplaceTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.jsonReplaceWarning),
            const SizedBox(height: 16),
            Text(AppStrings.jsonReplaceCurrent, style: heading),
            const SizedBox(height: 8),
            _ComparedLine(
              label: AppStrings.jsonStoreNameLabel,
              value: widget.currentStoreName,
              valueKey: const Key('json-replace-current-store'),
            ),
            _ComparedLine(
              label: AppStrings.jsonDbNameLabel,
              value: widget.currentDbName,
              valueKey: const Key('json-replace-current-db'),
            ),
            const SizedBox(height: 16),
            Text(AppStrings.jsonReplaceIncoming, style: heading),
            const SizedBox(height: 8),
            _ComparedLine(
              label: AppStrings.jsonStoreNameLabel,
              value: widget.nextStoreName,
              valueKey: const Key('json-replace-new-store'),
            ),
            _ComparedLine(
              label: AppStrings.jsonDbNameLabel,
              value: widget.nextDbName,
              valueKey: const Key('json-replace-new-db'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('json-replace-cancel'),
          onPressed: () => _finish(_ReplacementDecision.cancelled),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('json-replace-confirm'),
          onPressed: () => _finish(_ReplacementDecision.confirmed),
          child: const Text(AppStrings.jsonReplaceConfirm),
        ),
      ],
    );
  }
}

class _ComparedLine extends StatelessWidget {
  const _ComparedLine({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
