import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/fulfilment_application.dart';
import '../../application/fulfilment_scope.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../models/retail_dataset.dart';
import '../../services/file/cumulative_export_share.dart';
import '../../services/file/export_share.dart';
import '../../services/json/cumulative_json_export.dart';
import '../../widgets/status_message.dart';
import '../json_import/fulfilment_block_message.dart';
import 'dataset_order_search.dart';
import 'json_order_details_screen.dart';

/// Lists orders from the current JSON [FulfilmentSession].
///
/// The session is read from [FulfilmentScope] on every build. This screen
/// does not keep a session, an order list, or export bytes of its own. A row
/// opens [JsonOrderDetailsScreen] with that row's [DatasetOrder.orderId] only.
///
/// **Сформувати JSON-файл** calls [FulfilmentUiController.commitCumulativeExport].
/// **Поширити файл** shares [FulfilmentUiController.lastExport] through
/// [share]. The two actions are separate gestures. Share does not wait for
/// a commit or a storage read.
class JsonOrdersScreen extends StatefulWidget {
  /// Creates a list bound to the ambient fulfilment controller.
  ///
  /// [share] replaces the production [CumulativeExportShare] in tests.
  const JsonOrdersScreen({super.key, this.share});

  /// Shares the last committed export. Production uses the browser adapter.
  final CumulativeExportShare? share;

  @override
  State<JsonOrdersScreen> createState() => _JsonOrdersScreenState();
}

class _JsonOrdersScreenState extends State<JsonOrdersScreen> {
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _orderNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) => setState(() {});

  CumulativeExportShare get _share =>
      widget.share ?? const CumulativeExportShare();

  /// Reloads storage once. A build does not call this.
  Future<void> _retry() async {
    final controller = FulfilmentScope.read(context);
    try {
      await controller.refresh();
    } on Object {
      // operationError is already recorded. The blocked view explains it.
    }
  }

  /// Commits a cumulative export when the current session still has an
  /// issued order.
  ///
  /// Statuses and [FulfilmentUiController.lastExport] change only after
  /// [FulfilmentExported]. This does not share the file.
  Future<void> _export() async {
    final controller = FulfilmentScope.read(context);
    if (!_canExport(controller)) return;
    try {
      final result = await controller.commitCumulativeExport();
      if (!mounted) return;
      _acceptExport(result);
    } on Object {
      // operationError is already recorded. The blocked view explains it.
    }
  }

  /// Names every export result and leaves the controller session in place.
  ///
  /// [FulfilmentScope] has already rebuilt from that session. A blocked
  /// result observed after a reload restored [FulfilmentUiPhase.ready] does
  /// not paint a second conflict message.
  void _acceptExport(FulfilmentExportResult? result) {
    final phase = FulfilmentScope.read(context).phase;
    switch (result) {
      case null:
      case FulfilmentExportNotReady():
      case FulfilmentExported():
        return;
      case FulfilmentExportUnchanged():
        _showNotice(
          AppStrings.jsonExportUnchanged,
          key: const Key('json-export-unchanged'),
        );
      case FulfilmentExportRejected(:final failures):
        _showNotice(
          _exportRejectedMessage(failures),
          key: const Key('json-export-rejected'),
        );
      case FulfilmentExportBlocked() when phase == FulfilmentUiPhase.ready:
      case FulfilmentExportFailed() when phase == FulfilmentUiPhase.ready:
        return;
      case FulfilmentExportBlocked():
      case FulfilmentExportFailed():
        return;
    }
  }

  /// Shares the document already stored on the controller.
  ///
  /// [CumulativeExportShare.share] runs before this method suspends. There
  /// is no commit, refresh, or IndexedDB read before that call.
  void _shareExport() {
    final document = FulfilmentScope.read(context).lastExport;
    if (document == null) return;
    final pending = _share.share(document);
    unawaited(
      pending.then<void>(
        (result) {
          if (!mounted) return;
          _acceptShare(result);
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Share failed: $error\n$stack');
          if (!mounted) return;
          _showNotice(
            AppStrings.excelShareFailed,
            key: const Key('json-share-failed'),
          );
        },
      ),
    );
  }

  void _acceptShare(ExportShareResult result) {
    switch (result) {
      case ExportShareHandedOff():
      case ExportShareDownloadStarted():
      case ExportShareCancelled():
      case ExportShareUnavailable():
        return;
      case ExportShareFailed():
        _showNotice(
          AppStrings.excelShareFailed,
          key: const Key('json-share-failed'),
        );
    }
  }

  void _showNotice(String message, {required Key key}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: key,
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('json-export-notice-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.dialogOk),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    final session = controller.session;
    final title = controller.phase == FulfilmentUiPhase.ready && session != null
        ? AppStrings.ordersWithStore(session.dataset.storeName)
        : AppStrings.ordersScreenTitle;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: switch (controller.phase) {
          FulfilmentUiPhase.loading => const _LoadingBody(),
          FulfilmentUiPhase.empty => _MessageBody(
            onRetry: controller.refreshInFlight ? null : _retry,
            refreshing: controller.refreshInFlight,
            child: const StatusMessage(
              key: Key('json-orders-empty'),
              icon: Icons.receipt_long_outlined,
              title: AppStrings.jsonEmptyTitle,
              message: AppStrings.jsonEmptyMessage,
            ),
          ),
          FulfilmentUiPhase.blocked => _BlockedBody(
            message: fulfilmentBlockedMessage(controller),
            refreshing: controller.refreshInFlight,
            onRetry: controller.commandInFlight || controller.refreshInFlight
                ? null
                : _retry,
          ),
          FulfilmentUiPhase.ready =>
            session == null
                ? _MessageBody(
                    onRetry: controller.refreshInFlight ? null : _retry,
                    refreshing: controller.refreshInFlight,
                    child: const StatusMessage(
                      key: Key('json-orders-empty'),
                      icon: Icons.receipt_long_outlined,
                      title: AppStrings.jsonEmptyTitle,
                      message: AppStrings.jsonEmptyMessage,
                    ),
                  )
                : _ReadyOrders(
                    session: session,
                    orderNumberController: _orderNumberController,
                    phoneController: _phoneController,
                    onChanged: _onSearchChanged,
                    onExport: () => unawaited(_export()),
                    onShare: _shareExport,
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
        key: Key('json-orders-loading'),
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

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.child,
    required this.onRetry,
    required this.refreshing,
  });

  final Widget child;
  final VoidCallback? onRetry;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-orders-retry'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('json-orders-blocked'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              AppStrings.jsonBlockedTitle,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              key: const Key('json-orders-blocked-message'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-orders-retry'),
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
      ),
    );
  }
}

class _ReadyOrders extends StatelessWidget {
  const _ReadyOrders({
    required this.session,
    required this.orderNumberController,
    required this.phoneController,
    required this.onChanged,
    required this.onExport,
    required this.onShare,
  });

  /// Session installed on the controller for this build.
  final FulfilmentSession session;
  final TextEditingController orderNumberController;
  final TextEditingController phoneController;
  final ValueChanged<String> onChanged;
  final VoidCallback onExport;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final orders = session.dataset.orders;
    final filtered = DatasetOrderSearch.filter(
      orders,
      orderNumberQuery: orderNumberController.text,
      phoneQuery: phoneController.text,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > AppConstants.ordersMaxWidth
            ? AppConstants.ordersMaxWidth
            : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: LayoutBuilder(
                builder: (context, content) {
                  final wide =
                      content.maxWidth >= AppConstants.wideLayoutBreakpoint;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ExportActions(
                        wide: wide,
                        onExport: onExport,
                        onShare: onShare,
                      ),
                      const SizedBox(height: 16),
                      _SearchFields(
                        wide: wide,
                        orderNumberController: orderNumberController,
                        phoneController: phoneController,
                        onChanged: onChanged,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _OrdersBody(
                          session: session,
                          orders: filtered,
                          wide: wide,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Whether a cumulative export may be sent.
///
/// Readiness is an issued [FulfilmentSession.statusOf]. This does not count
/// reserved units again.
bool _canExport(FulfilmentUiController controller) {
  final session = controller.session;
  if (session == null) return false;
  if (controller.phase != FulfilmentUiPhase.ready || !controller.canMutate) {
    return false;
  }
  if (controller.commandInFlight || controller.refreshInFlight) return false;
  for (final order in session.dataset.orders) {
    if (session.statusOf(order.orderId) == OrderStatus.issued) return true;
  }
  return false;
}

class _ExportActions extends StatelessWidget {
  const _ExportActions({
    required this.wide,
    required this.onExport,
    required this.onShare,
  });

  final bool wide;
  final VoidCallback onExport;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    final document = controller.lastExport;
    final busy = controller.commandInFlight;
    final exportButton = FilledButton(
      key: const Key('json-create-export'),
      onPressed: _canExport(controller) ? onExport : null,
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              AppStrings.jsonCreateExport,
              textAlign: TextAlign.center,
            ),
    );
    final shareButton = document == null
        ? null
        : OutlinedButton(
            key: const Key('json-share-export'),
            onPressed: onShare,
            child: const Text(
              AppStrings.shareFile,
              textAlign: TextAlign.center,
            ),
          );
    final filename = document == null
        ? null
        : Text(
            '${AppStrings.jsonLastSavedExport} ${document.filename}',
            key: const Key('json-last-export-file'),
          );
    final buttons = <Widget>[exportButton, ?shareButton];
    final stacked = <Widget>[
      for (var index = 0; index < buttons.length; index++) ...[
        if (index > 0) const SizedBox(height: 12),
        buttons[index],
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Wrap(spacing: 12, runSpacing: 12, children: buttons)
        else
          ...stacked,
        if (filename != null) ...[const SizedBox(height: 12), filename],
      ],
    );
  }
}

class _SearchFields extends StatelessWidget {
  const _SearchFields({
    required this.wide,
    required this.orderNumberController,
    required this.phoneController,
    required this.onChanged,
  });

  final bool wide;
  final TextEditingController orderNumberController;
  final TextEditingController phoneController;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final orderField = TextField(
      key: const Key('json-order-number-search'),
      controller: orderNumberController,
      onChanged: onChanged,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: AppStrings.orderNumberSearchLabel,
        hintText: AppStrings.orderNumberSearchHint,
        prefixIcon: Icon(Icons.tag),
      ),
    );
    final phoneField = TextField(
      key: const Key('json-customer-phone-search'),
      controller: phoneController,
      onChanged: onChanged,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        labelText: AppStrings.phoneSearchLabel,
        hintText: AppStrings.phoneSearchHint,
        prefixIcon: Icon(Icons.phone_outlined),
      ),
    );

    if (!wide) {
      return Column(
        children: [orderField, const SizedBox(height: 12), phoneField],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: orderField),
        const SizedBox(width: 16),
        Expanded(child: phoneField),
      ],
    );
  }
}

class _OrdersBody extends StatelessWidget {
  const _OrdersBody({
    required this.session,
    required this.orders,
    required this.wide,
  });

  final FulfilmentSession session;
  final List<DatasetOrder> orders;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: StatusMessage(
          key: Key('json-orders-no-match'),
          icon: Icons.search_off,
          title: AppStrings.ordersNoMatchTitle,
          message: AppStrings.ordersNoMatchMessage,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          const _OrdersTableHeader(key: Key('json-orders-table-header')),
          const Divider(height: 1, color: AppColors.border),
        ],
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final status = session.statusOf(order.orderId);
              if (wide) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OrderTableRow(
                      key: ValueKey(order.orderId),
                      order: order,
                      status: status,
                    ),
                    if (index < orders.length - 1)
                      const Divider(height: 1, color: AppColors.border),
                  ],
                );
              }
              return Padding(
                key: ValueKey(order.orderId),
                padding: const EdgeInsets.only(bottom: 12),
                child: _OrderCard(order: order, status: status),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrdersTableHeader extends StatelessWidget {
  const _OrdersTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _OrderColumns(
        date: AppStrings.invoiceDateLabel,
        invoiceNumber: AppStrings.invoiceNumberLabel,
        orderNumber: AppStrings.orderNumberLabel,
        customer: AppStrings.customerLabel,
        phone: AppStrings.customerPhoneLabel,
        status: Text(
          AppStrings.orderStatusLabel,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        style: style,
        maxLines: 2,
      ),
    );
  }
}

void _openJsonOrder(BuildContext context, String orderId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JsonOrderDetailsScreen(orderId: orderId),
    ),
  );
}

class _OrderTableRow extends StatelessWidget {
  const _OrderTableRow({super.key, required this.order, required this.status});

  final DatasetOrder order;
  final OrderStatus? status;

  @override
  Widget build(BuildContext context) {
    final visual = status == null ? null : _statusStyle(status!);
    return Material(
      color: visual?.background ?? AppColors.background,
      child: InkWell(
        onTap: () => _openJsonOrder(context, order.orderId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: _OrderColumns(
            date: DisplayFormat.formatInvoiceDate(order.invoiceDate),
            invoiceNumber: order.invoiceNumber,
            orderNumber: order.orderNumber.literal,
            customer: order.customer,
            phone: DisplayFormat.formatPhone(order.customerPhone),
            status: _OrderStatusBadge(status: status),
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
          ),
        ),
      ),
    );
  }
}

class _OrderColumns extends StatelessWidget {
  const _OrderColumns({
    required this.date,
    required this.invoiceNumber,
    required this.orderNumber,
    required this.customer,
    required this.phone,
    required this.status,
    required this.style,
    this.maxLines = 1,
  });

  final String date;
  final String invoiceNumber;
  final String orderNumber;
  final String customer;
  final String phone;
  final Widget status;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, int flex) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: AppConstants.tableColumnGap),
        child: Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell(date, 3),
        cell(invoiceNumber, 3),
        cell(orderNumber, 3),
        cell(customer, 4),
        cell(phone, 3),
        Expanded(flex: 3, child: status),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.status});

  final DatasetOrder order;
  final OrderStatus? status;

  @override
  Widget build(BuildContext context) {
    final visual = status == null ? null : _statusStyle(status!);
    return Card(
      color: visual?.background,
      child: InkWell(
        onTap: () => _openJsonOrder(context, order.orderId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrderStatusBadge(status: status),
              const SizedBox(height: 8),
              Text(
                order.orderNumber.literal,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.accountLine(
                  order.invoiceNumber,
                  DisplayFormat.formatInvoiceDate(order.invoiceDate),
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    order.customer,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    DisplayFormat.formatPhone(order.customerPhone),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color? background;
}

_StatusStyle _statusStyle(OrderStatus status) => switch (status) {
  OrderStatus.noSelection => const _StatusStyle(
    icon: Icons.radio_button_unchecked,
    foreground: AppColors.textSecondary,
    background: null,
  ),
  OrderStatus.inProgress => const _StatusStyle(
    icon: Icons.timelapse,
    foreground: AppColors.orderStatusInProgressForeground,
    background: AppColors.orderStatusInProgressBackground,
  ),
  OrderStatus.readyForIssue => const _StatusStyle(
    icon: Icons.check_circle_outline,
    foreground: AppColors.orderStatusReadyForeground,
    background: AppColors.orderStatusReadyBackground,
  ),
  OrderStatus.issued => const _StatusStyle(
    icon: Icons.task_alt,
    foreground: AppColors.orderStatusIssuedForeground,
    background: AppColors.orderStatusIssuedBackground,
  ),
  OrderStatus.exported => const _StatusStyle(
    icon: Icons.lock_outline,
    foreground: AppColors.orderStatusExportedForeground,
    background: AppColors.orderStatusExportedBackground,
  ),
};

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({required this.status});

  final OrderStatus? status;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) {
      return Text(
        '—',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      );
    }
    final visual = _statusStyle(current);
    return Row(
      children: [
        Icon(visual.icon, size: 18, color: visual.foreground),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            current.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: visual.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String _exportRejectedMessage(List<CumulativeExportFailure> failures) {
  final orderIds = <String>[];
  for (final failure in failures) {
    if (failure.reason != CumulativeExportReason.invalidExciseStamp) continue;
    final orderId = failure.orderId;
    if (orderId == null || orderIds.contains(orderId)) continue;
    orderIds.add(orderId);
  }
  if (orderIds.isEmpty) return AppStrings.jsonExportRejected;
  return AppStrings.jsonExportExciseRejected(orderIds);
}
