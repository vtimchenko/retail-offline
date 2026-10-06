import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/order.dart';
import '../../models/order_export.dart';
import '../../models/store.dart';
import '../../repositories/order_export_repository.dart';
import '../../repositories/serial_selection_repository.dart';
import '../../repositories/session_data_repository.dart';
import '../../services/excel/order_export_workbook.dart';
import '../../services/file/xlsx_share.dart';
import 'fulfilment_check.dart';
import 'serial_selection_screen.dart';

/// One imported [Order] and the serial quantities reserved for its items.
///
/// [OrderItem.productId] stays on the model and is not shown.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.store,
    required this.order,
    required this.repository,
    required this.selections,
    required this.exports,
    this.shareXlsx,
  });

  final Store store;
  final Order order;
  final SessionDataRepository repository;
  final SerialSelectionRepository selections;
  final OrderExportRepository exports;

  /// Replaces [shareOrDownloadXlsx] in tests.
  final ShareXlsx? shareXlsx;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  Future<void> _openItem(OrderItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SerialSelectionScreen(
          store: widget.store,
          orderNumber: widget.order.orderNumber,
          item: item,
          inventory: List.unmodifiable(
            widget.repository.inventoryByProductId(item.productId),
          ),
          selections: widget.selections,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _complete() {
    final result = FulfilmentCheck.check(widget.order, widget.selections);
    if (!result.isComplete) {
      _showIncomplete(result);
      return;
    }

    final OrderExport export;
    try {
      export = OrderExportWorkbook.build(
        idStore: widget.store.idStore,
        order: widget.order,
        selections: widget.selections,
      );
    } on Object catch (error, stack) {
      debugPrint('Excel export failed: $error\n$stack');
      _showNotice(
        AppStrings.excelGenerationFailed,
        key: const Key('export-failed'),
      );
      return;
    }

    widget.exports.put(export);
    setState(() {});
    _showNotice(
      AppStrings.excelFileCreated,
      key: const Key('fulfilment-success'),
    );
  }

  void _share() {
    final export = widget.exports.exportFor(widget.order.orderNumber);
    if (export == null) return;
    final pending = (widget.shareXlsx ?? shareOrDownloadXlsx)(
      filename: export.filename,
      bytes: export.bytes,
    );
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          debugPrint('Share failed: $error\n$stack');
          if (!mounted) return;
          _showNotice(
            AppStrings.excelShareFailed,
            key: const Key('share-failed'),
          );
        },
      ),
    );
  }

  void _showNotice(String message, {required Key key}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: key,
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('fulfilment-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.dialogOk),
          ),
        ],
      ),
    );
  }

  Widget _serviceButton() {
    final ready = widget.exports.exportFor(widget.order.orderNumber) != null;
    return FilledButton(
      key: Key(ready ? 'share-file' : 'complete-service'),
      onPressed: ready ? _share : _complete,
      child: Text(
        ready ? AppStrings.shareFile : AppStrings.completeService,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showIncomplete(FulfilmentResult result) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('fulfilment-incomplete'),
        title: const Text(AppStrings.fulfilmentIncompleteTitle),
        content: _IncompleteFulfilment(gaps: result.gaps),
        actions: [
          TextButton(
            key: const Key('fulfilment-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(AppStrings.dialogOk),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(title: Text(widget.store.nameStore)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth > AppConstants.ordersMaxWidth
                ? AppConstants.ordersMaxWidth
                : constraints.maxWidth;
            const padding = EdgeInsets.all(16);
            final wide =
                width - padding.horizontal >= AppConstants.wideLayoutBreakpoint;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        children: [
                          _OrderInfoCard(order: order),
                          const SizedBox(height: 20),
                          Text(
                            AppStrings.orderItemsTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          if (wide)
                            const _ItemsHeader(key: Key('order-items-header')),
                          for (var i = 0; i < order.items.length; i++)
                            wide
                                ? _ItemRow(
                                    key: ValueKey('order-item-row-$i'),
                                    item: order.items[i],
                                    selectedQuantity: widget.selections
                                        .selectedQuantity(
                                          order.orderNumber,
                                          order.items[i].productId,
                                        ),
                                    onTap: () => _openItem(order.items[i]),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ItemCard(
                                      key: ValueKey('order-item-card-$i'),
                                      item: order.items[i],
                                      selectedQuantity: widget.selections
                                          .selectedQuantity(
                                            order.orderNumber,
                                            order.items[i].productId,
                                          ),
                                      onTap: () => _openItem(order.items[i]),
                                    ),
                                  ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _serviceButton(),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IncompleteFulfilment extends StatelessWidget {
  const _IncompleteFulfilment({required this.gaps});

  final List<FulfilmentGap> gaps;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.fulfilmentIncompleteIntro),
            for (var i = 0; i < gaps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  AppStrings.fulfilmentGapLine(
                    gaps[i].product,
                    gaps[i].requiredQuantity,
                    gaps[i].selectedQuantity,
                  ),
                  key: ValueKey('fulfilment-gap-$i'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(
              AppStrings.invoiceDateLabel,
              DisplayFormat.formatInvoiceDate(order.invoiceDate),
            ),
            _Field(AppStrings.invoiceNumberLabel, order.invoiceNumber),
            _Field(AppStrings.orderNumberLabel, order.orderNumber),
            _Field(AppStrings.customerLabel, order.customer),
            _Field(AppStrings.customerPhoneLabel, order.customerPhone),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

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
          Text(value, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _ItemsHeader extends StatelessWidget {
  const _ItemsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _ItemColumns(
        product: AppStrings.productLabel,
        quantity: AppStrings.quantityLabel,
        price: AppStrings.priceLabel,
        amount: AppStrings.amountLabel,
        style: style,
        maxLines: 2,
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.selectedQuantity,
    required this.onTap,
  });

  final OrderItem item;
  final int selectedQuantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: _ItemColumns(
          product: item.product,
          quantity: '${item.quantity}',
          price: DisplayFormat.formatMoney(item.priceMinorUnits),
          amount: DisplayFormat.formatMoney(item.amountMinorUnits),
          subtitle: AppStrings.selectedOfRequired(
            selectedQuantity,
            item.quantity,
          ),
          subtitleColor: selectedQuantity == item.quantity
              ? AppColors.primaryDark
              : AppColors.textSecondary,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ItemColumns extends StatelessWidget {
  const _ItemColumns({
    required this.product,
    required this.quantity,
    required this.price,
    required this.amount,
    required this.style,
    this.subtitle,
    this.subtitleColor = AppColors.textSecondary,
    this.maxLines = 1,
  });

  final String product;
  final String quantity;
  final String price;
  final String amount;
  final TextStyle? style;
  final String? subtitle;
  final Color subtitleColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, int flex) => Expanded(
      flex: flex,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product,
                style: style,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: subtitleColor),
                ),
            ],
          ),
        ),
        cell(quantity, 2),
        cell(price, 2),
        cell(amount, 2),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.selectedQuantity,
    required this.onTap,
  });

  final OrderItem item;
  final int selectedQuantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progressColor = selectedQuantity == item.quantity
        ? AppColors.primaryDark
        : AppColors.textSecondary;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(AppStrings.productLabel, item.product),
              _Field(AppStrings.quantityLabel, '${item.quantity}'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  AppStrings.selectedOfRequired(
                    selectedQuantity,
                    item.quantity,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: progressColor),
                ),
              ),
              _Field(
                AppStrings.priceLabel,
                DisplayFormat.formatMoney(item.priceMinorUnits),
              ),
              _Field(
                AppStrings.amountLabel,
                DisplayFormat.formatMoney(item.amountMinorUnits),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
