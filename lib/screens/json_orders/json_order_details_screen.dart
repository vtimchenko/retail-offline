import 'package:flutter/material.dart';

import '../../application/fulfilment_scope.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../models/retail_dataset.dart';
import '../../widgets/status_message.dart';
import '../json_import/fulfilment_block_message.dart';
import 'json_serial_selection_screen.dart';

/// Read-only details for one order in the current JSON session.
///
/// [orderId] is the only value this screen keeps. Each build reads
/// [FulfilmentScope], resolves that id on the current [FulfilmentSession],
/// and drops the previous order when the id is gone. Money is shown from
/// the stored minor units.
class JsonOrderDetailsScreen extends StatelessWidget {
  /// Creates details that resolve [orderId] from the ambient session.
  const JsonOrderDetailsScreen({super.key, required this.orderId});

  /// Dataset `OrderID`. This is not [DatasetOrder.orderNumber].
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    final session = controller.session;
    final title = controller.phase == FulfilmentUiPhase.ready && session != null
        ? session.dataset.storeName
        : AppStrings.ordersScreenTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: switch (controller.phase) {
          FulfilmentUiPhase.loading => const _LoadingBody(),
          FulfilmentUiPhase.empty => _MessageBody(
            onRetry: controller.refreshInFlight ? null : () => _retry(context),
            refreshing: controller.refreshInFlight,
            child: const StatusMessage(
              key: Key('json-order-details-empty'),
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
                : () => _retry(context),
          ),
          FulfilmentUiPhase.ready =>
            session == null
                ? _MessageBody(
                    onRetry: controller.refreshInFlight
                        ? null
                        : () => _retry(context),
                    refreshing: controller.refreshInFlight,
                    child: const StatusMessage(
                      key: Key('json-order-details-empty'),
                      icon: Icons.receipt_long_outlined,
                      title: AppStrings.jsonEmptyTitle,
                      message: AppStrings.jsonEmptyMessage,
                    ),
                  )
                : _ReadyDetails(session: session, orderId: orderId),
        },
      ),
    );
  }
}

/// Reloads storage once. A build does not call this.
Future<void> _retry(BuildContext context) async {
  final controller = FulfilmentScope.read(context);
  try {
    await controller.refresh();
  } on Object {
    // operationError is already recorded. The blocked view explains it.
  }
}

/// Opens serial selection for a stock line.
///
/// A service line stays on this screen. Issued and exported orders still
/// open, and that screen keeps their reservations read-only.
VoidCallback? _openSerial(
  BuildContext context,
  String orderId,
  DatasetGood good,
) {
  if (good.isServiceGood) return null;
  final productId = good.productId.literal;
  return () {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            JsonSerialSelectionScreen(orderId: orderId, productId: productId),
      ),
    );
  };
}

DatasetOrder? _orderById(FulfilmentSession session, String orderId) {
  for (final order in session.dataset.orders) {
    if (order.orderId == orderId) return order;
  }
  return null;
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        key: Key('json-order-details-loading'),
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
              key: const Key('json-order-details-retry'),
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
          key: const Key('json-order-details-blocked'),
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
              key: const Key('json-order-details-blocked-message'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-order-details-retry'),
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

class _ReadyDetails extends StatelessWidget {
  const _ReadyDetails({required this.session, required this.orderId});

  final FulfilmentSession session;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = _orderById(session, orderId);
    if (order == null) return const _MissingOrder();
    return _OrderBody(session: session, order: order);
  }
}

class _MissingOrder extends StatelessWidget {
  const _MissingOrder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('json-order-missing'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const StatusMessage(
              icon: Icons.search_off,
              title: AppStrings.jsonOrderNotFoundTitle,
              message: AppStrings.jsonOrderNotFoundMessage,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-order-missing-back'),
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) navigator.pop();
              },
              child: const Text(AppStrings.jsonBackToOrders),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.session, required this.order});

  final FulfilmentSession session;
  final DatasetOrder order;

  @override
  Widget build(BuildContext context) {
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
                  return ListView(
                    key: const Key('json-order-details'),
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      _OrderInfoCard(session: session, order: order),
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.orderItemsTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (wide) ...[
                        const _GoodsHeader(key: Key('json-goods-table-header')),
                        const Divider(height: 1, color: AppColors.border),
                      ],
                      for (final good in order.goods)
                        wide
                            ? _GoodRow(
                                key: ValueKey(
                                  'json-good-${good.productId.literal}',
                                ),
                                good: good,
                                progress: _lineProgress(
                                  session,
                                  order.orderId,
                                  good,
                                ),
                                onOpen: _openSerial(
                                  context,
                                  order.orderId,
                                  good,
                                ),
                              )
                            : Padding(
                                key: ValueKey(
                                  'json-good-${good.productId.literal}',
                                ),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _GoodCard(
                                  good: good,
                                  progress: _lineProgress(
                                    session,
                                    order.orderId,
                                    good,
                                  ),
                                  onOpen: _openSerial(
                                    context,
                                    order.orderId,
                                    good,
                                  ),
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

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({required this.session, required this.order});

  final FulfilmentSession session;
  final DatasetOrder order;

  @override
  Widget build(BuildContext context) {
    final status = session.statusOf(order.orderId);
    final visual = status == null ? null : _statusStyle(status);
    return Card(
      key: const Key('json-order-info'),
      color: visual?.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OrderStatusBadge(
              key: const Key('json-order-status'),
              status: status,
            ),
            const SizedBox(height: 8),
            _DetailField(
              AppStrings.invoiceDateLabel,
              DisplayFormat.formatInvoiceDate(order.invoiceDate),
              valueKey: const Key('json-order-date'),
            ),
            _DetailField(
              AppStrings.invoiceNumberLabel,
              order.invoiceNumber,
              valueKey: const Key('json-invoice-number'),
            ),
            _DetailField(
              AppStrings.orderNumberLabel,
              order.orderNumber.literal,
              valueKey: const Key('json-order-number'),
            ),
            _DetailField(
              AppStrings.customerLabel,
              order.customer,
              valueKey: const Key('json-customer'),
            ),
            _DetailField(
              AppStrings.customerPhoneLabel,
              order.customerPhone,
              valueKey: const Key('json-customer-phone'),
            ),
            _DetailField(
              AppStrings.jsonStoreNameLabel,
              session.dataset.storeName,
              valueKey: const Key('json-store-name'),
            ),
            _DetailField(
              AppStrings.orderTotalLabel,
              DisplayFormat.formatMoney(order.totalMinorUnits),
              valueKey: const Key('json-order-total'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField(this.label, this.value, {required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, key: valueKey, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _GoodsHeader extends StatelessWidget {
  const _GoodsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _GoodColumns(
        product: Text(
          AppStrings.productLabel,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        quantity: Text(
          AppStrings.quantityLabel,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        price: Text(
          AppStrings.priceLabel,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        amount: Text(
          AppStrings.amountLabel,
          style: style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _GoodRow extends StatelessWidget {
  const _GoodRow({
    super.key,
    required this.good,
    required this.progress,
    required this.onOpen,
  });

  final DatasetGood good;
  final _LineProgress progress;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _GoodColumns(
        product: _GoodFacts(good: good, progress: progress),
        quantity: Text(
          '${good.quantity}',
          key: ValueKey('json-good-quantity-${good.productId.literal}'),
          style: style,
        ),
        price: Text(
          DisplayFormat.formatMoney(good.priceMinorUnits),
          key: ValueKey('json-good-price-${good.productId.literal}'),
          style: style,
        ),
        amount: Text(
          DisplayFormat.formatMoney(good.amountMinorUnits),
          key: ValueKey('json-good-amount-${good.productId.literal}'),
          style: style,
        ),
      ),
    );
    final open = onOpen;
    if (open == null) return row;
    return InkWell(
      key: ValueKey('json-good-open-${good.productId.literal}'),
      onTap: open,
      child: row,
    );
  }
}

class _GoodCard extends StatelessWidget {
  const _GoodCard({
    required this.good,
    required this.progress,
    required this.onOpen,
  });

  final DatasetGood good;
  final _LineProgress progress;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GoodFacts(good: good, progress: progress),
          _DetailField(
            AppStrings.quantityLabel,
            '${good.quantity}',
            valueKey: ValueKey('json-good-quantity-${good.productId.literal}'),
          ),
          _DetailField(
            AppStrings.priceLabel,
            DisplayFormat.formatMoney(good.priceMinorUnits),
            valueKey: ValueKey('json-good-price-${good.productId.literal}'),
          ),
          _DetailField(
            AppStrings.amountLabel,
            DisplayFormat.formatMoney(good.amountMinorUnits),
            valueKey: ValueKey('json-good-amount-${good.productId.literal}'),
          ),
        ],
      ),
    );
    final open = onOpen;
    return Card(
      child: open == null
          ? body
          : InkWell(
              key: ValueKey('json-good-open-${good.productId.literal}'),
              onTap: open,
              child: body,
            ),
    );
  }
}

class _GoodColumns extends StatelessWidget {
  const _GoodColumns({
    required this.product,
    required this.quantity,
    required this.price,
    required this.amount,
  });

  final Widget product;
  final Widget quantity;
  final Widget price;
  final Widget amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: product),
        Expanded(flex: 2, child: quantity),
        Expanded(flex: 2, child: price),
        Expanded(flex: 2, child: amount),
      ],
    );
  }
}

class _GoodFacts extends StatelessWidget {
  const _GoodFacts({required this.good, required this.progress});

  final DatasetGood good;
  final _LineProgress progress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final kind = good.isServiceGood
        ? AppStrings.serviceGoodLabel
        : good.isParcel
        ? AppStrings.parcelGoodLabel
        : null;
    final parcelTtn = good.parcelTtn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(good.product, style: textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          AppStrings.productIdLabel,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          good.productId.literal,
          key: ValueKey('json-product-id-${good.productId.literal}'),
          style: textTheme.bodyMedium,
        ),
        if (kind != null) ...[
          const SizedBox(height: 4),
          Text(
            kind,
            key: ValueKey(
              good.isServiceGood
                  ? 'json-good-service-${good.productId.literal}'
                  : 'json-good-parcel-${good.productId.literal}',
            ),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        if (good.isParcel && parcelTtn != null)
          _DetailField(
            AppStrings.parcelTtnLabel,
            parcelTtn,
            valueKey: ValueKey('json-parcel-ttn-${good.productId.literal}'),
          ),
        const SizedBox(height: 4),
        _LineProgressView(good: good, progress: progress),
      ],
    );
  }
}

class _LineProgressView extends StatelessWidget {
  const _LineProgressView({required this.good, required this.progress});

  final DatasetGood good;
  final _LineProgress progress;

  @override
  Widget build(BuildContext context) {
    final color = progress.ready
        ? AppColors.primaryDark
        : AppColors.textSecondary;
    final label = progress.service
        ? AppStrings.serviceLineProgress
        : AppStrings.selectedOfRequired(
            progress.reservedQuantity!,
            progress.requiredQuantity,
          );
    return Row(
      key: ValueKey(
        progress.ready
            ? 'json-good-ready-${good.productId.literal}'
            : 'json-good-progress-${good.productId.literal}',
      ),
      children: [
        Icon(
          progress.ready
              ? Icons.check_circle_outline
              : Icons.radio_button_unchecked,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Selected units of one goods line, taken from the current session.
///
/// A service line is omitted by [FulfilmentSession.statusOf] and
/// [FulfilmentSession.reserve] rejects it, so it is ready without a selected
/// quantity. Any other line is ready when [FulfilmentSession.lineReservedQuantity]
/// equals [DatasetGood.quantity].
@immutable
class _LineProgress {
  const _LineProgress({
    required this.requiredQuantity,
    required this.reservedQuantity,
    required this.ready,
    required this.service,
  });

  final int requiredQuantity;

  /// Units from [FulfilmentSession.lineReservedQuantity], or `null` for a
  /// service line.
  final int? reservedQuantity;

  /// Whether this line meets the session's readiness rule.
  final bool ready;

  /// Whether [DatasetGood.isServiceGood] is set.
  final bool service;
}

_LineProgress _lineProgress(
  FulfilmentSession session,
  String orderId,
  DatasetGood good,
) {
  if (good.isServiceGood) {
    return _LineProgress(
      requiredQuantity: good.quantity,
      reservedQuantity: null,
      ready: true,
      service: true,
    );
  }
  final reserved = session.lineReservedQuantity(
    orderId: orderId,
    productId: good.productId.literal,
  );
  return _LineProgress(
    requiredQuantity: good.quantity,
    reservedQuantity: reserved,
    ready: reserved == good.quantity,
    service: false,
  );
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
  const _OrderStatusBadge({super.key, required this.status});

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
            maxLines: 1,
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
