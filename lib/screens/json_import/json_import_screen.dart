import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/fulfilment_application.dart';
import '../../application/fulfilment_scope.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/dataset_messages.dart';
import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../persistence/dataset_fingerprint.dart';
import '../../services/file/json_file_service.dart';
import '../../widgets/centered_content.dart';
import '../json_orders/json_orders_screen.dart';
import 'fulfilment_block_message.dart';

/// Temporary JSON import screen for the fulfilment controller.
///
/// The phase, session, and commands come from [FulfilmentScope]. This screen
/// does not parse JSON, copy the session, or replace a dataset that is
/// already stored. A file the user cancels is ignored.
class JsonImportScreen extends StatefulWidget {
  /// Creates a screen that imports through the ambient fulfilment controller.
  ///
  /// [fileService] replaces the browser chooser in tests.
  const JsonImportScreen({super.key, this.fileService});

  /// Local JSON chooser. Production uses [JsonFileService].
  final JsonFileService? fileService;

  @override
  State<JsonImportScreen> createState() => _JsonImportScreenState();
}

class _JsonImportScreenState extends State<JsonImportScreen> {
  var _picking = false;
  String? _importMessage;

  JsonFileService get _files => widget.fileService ?? const JsonFileService();

  void _import() {
    if (_picking) return;
    final controller = FulfilmentScope.read(context);
    if (controller.phase != FulfilmentUiPhase.empty ||
        controller.commandInFlight ||
        controller.refreshInFlight) {
      return;
    }
    setState(() {
      _picking = true;
      _importMessage = null;
    });
    // The chooser must open before the first await.
    final pending = _files.pickJsonBytes();
    unawaited(_afterPick(pending));
  }

  Future<void> _afterPick(Future<Uint8List?> pending) async {
    Uint8List? bytes;
    Object? pickError;
    try {
      bytes = await pending;
    } on Object catch (error) {
      pickError = error;
    }
    if (!mounted) return;
    if (pickError != null) {
      setState(() {
        _picking = false;
        _importMessage = pickError is ImportException
            ? pickError.message
            : ImportMessages.fileReadFailed;
      });
      return;
    }
    setState(() => _picking = false);
    if (bytes == null) return;

    final controller = FulfilmentScope.read(context);
    if (controller.phase != FulfilmentUiPhase.empty ||
        controller.commandInFlight) {
      return;
    }
    final FulfilmentImportResult? result;
    try {
      result = await controller.importDataset(bytes);
    } on Object {
      // operationError is already recorded. The blocked view explains it.
      return;
    }
    if (!mounted) return;
    final outcome = result;
    if (outcome == null || outcome is FulfilmentImported) return;
    if (outcome is FulfilmentImportFailed ||
        outcome is FulfilmentImportBlocked) {
      return;
    }
    final message = _failureMessage(outcome);
    setState(() => _importMessage = message);
  }

  /// Reloads storage. This does not import again and does not overwrite.
  Future<void> _refresh() async {
    final controller = FulfilmentScope.read(context);
    try {
      await controller.refresh();
    } on Object {
      // The controller records operationError and stays blocked.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.jsonScreenTitle)),
      body: SafeArea(
        child: switch (controller.phase) {
          FulfilmentUiPhase.loading => const _LoadingBody(),
          FulfilmentUiPhase.empty => _EmptyBody(
            busy: _picking || controller.commandInFlight,
            importing: controller.commandInFlight,
            message: _importMessage,
            onImport: _import,
          ),
          FulfilmentUiPhase.ready => _ReadyBody(session: controller.session),
          FulfilmentUiPhase.blocked => _BlockedBody(
            message: fulfilmentBlockedMessage(controller),
            refreshing: controller.refreshInFlight,
            onRetry: controller.commandInFlight || controller.refreshInFlight
                ? null
                : _refresh,
          ),
        },
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        key: Key('json-import-loading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(AppStrings.jsonLoading),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.busy,
    required this.importing,
    required this.message,
    required this.onImport,
  });

  final bool busy;
  final bool importing;
  final String? message;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shown = message;
    return CenteredContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.jsonEmptyTitle,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.jsonEmptyMessage,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('json-import-button'),
            onPressed: busy ? null : onImport,
            child: importing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        key: Key('json-import-progress'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(AppStrings.jsonImporting),
                    ],
                  )
                : const Text(AppStrings.jsonImport),
          ),
          if (shown != null) ...[
            const SizedBox(height: 16),
            Text(
              shown,
              key: const Key('json-import-error'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({required this.session});

  /// Live session from the controller. Not a copy kept by the screen.
  final FulfilmentSession? session;

  @override
  Widget build(BuildContext context) {
    final dataset = session?.dataset;
    if (dataset == null) {
      return const CenteredContent(
        child: Text(AppStrings.jsonReadFailed, textAlign: TextAlign.center),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return CenteredContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.jsonReadyTitle,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MetaLine(
                    label: AppStrings.jsonStoreNameLabel,
                    value: dataset.storeName,
                    valueKey: const Key('json-store-name'),
                  ),
                  _MetaLine(
                    label: AppStrings.jsonDbNameLabel,
                    value: dataset.dbName,
                    valueKey: const Key('json-db-name'),
                  ),
                  _MetaLine(
                    label: AppStrings.jsonDateCreateLabel,
                    value: DisplayFormat.formatInvoiceDate(dataset.dateCreate),
                    valueKey: const Key('json-date-create'),
                  ),
                  _MetaLine(
                    label: AppStrings.jsonOrdersLabel,
                    value: dataset.orders.length.toString(),
                    valueKey: const Key('json-order-count'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('json-view-orders'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JsonOrdersScreen(),
                ),
              );
            },
            child: const Text(AppStrings.viewOrders),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
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

class _BlockedBody extends StatelessWidget {
  const _BlockedBody({
    required this.message,
    required this.refreshing,
    required this.onRetry,
  });

  final String message;
  final bool refreshing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return CenteredContent(
      child: Column(
        key: const Key('json-import-blocked'),
        children: [
          const Icon(Icons.error_outline, size: 56, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            AppStrings.jsonBlockedTitle,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            key: const Key('json-import-blocked-message'),
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('json-import-retry'),
            onPressed: onRetry,
            child: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }
}

String _failureMessage(FulfilmentImportResult result) {
  return switch (result) {
    FulfilmentImported() => AppStrings.jsonImportRejected,
    FulfilmentImportRejected(:final failure) => _restoreMessage(failure),
    FulfilmentDatasetRejected(:final problem) => _problemMessage(problem),
    FulfilmentImportOccupied() => AppStrings.jsonImportOccupied,
    FulfilmentImportBlocked(:final block) => fulfilmentBlockText(block),
    FulfilmentImportFailed(:final block) => fulfilmentBlockText(block),
  };
}

String _restoreMessage(DatasetRestoreRejected failure) {
  final message = failure.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return switch (failure.reason) {
    DatasetRestoreReason.malformedUtf8 => AppStrings.jsonMalformedUtf8,
    DatasetRestoreReason.invalidFingerprint ||
    DatasetRestoreReason.fingerprintMismatch ||
    DatasetRestoreReason.malformedJson ||
    DatasetRestoreReason.invalidDataset => AppStrings.jsonImportRejected,
  };
}

String _problemMessage(DatasetProblem problem) {
  return switch (problem.reason) {
    DatasetProblemReason.duplicateOrder => DatasetMessages.duplicateOrderId(
      problem.orderId ?? '',
    ),
    DatasetProblemReason.duplicateProduct => DatasetMessages.duplicateProductId(
      problem.orderId == null
          ? DatasetMessages.inDataset
          : DatasetMessages.orderId(problem.orderId!),
      problem.productId ?? '',
    ),
    DatasetProblemReason.duplicateStock => AppStrings.jsonDuplicateStock(
      productId: problem.productId,
      address: problem.address,
      serialNumber: problem.serialNumber,
    ),
  };
}
