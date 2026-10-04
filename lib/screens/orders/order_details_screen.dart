import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/order.dart';
import '../../models/store.dart';

/// One imported [Order] and its items.
///
/// [OrderItem.productId] stays on the model and is not shown.
class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({
    super.key,
    required this.store,
    required this.order,
  });

  final Store store;
  final Order order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(store.nameStore)),
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
                child: ListView(
                  padding: padding,
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
                            )
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ItemCard(
                                key: ValueKey('order-item-card-$i'),
                                item: order.items[i],
                              ),
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
  const _ItemRow({super.key, required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _ItemColumns(
        product: item.product,
        quantity: '${item.quantity}',
        price: DisplayFormat.formatMoney(item.priceMinorUnits),
        amount: DisplayFormat.formatMoney(item.amountMinorUnits),
        style: Theme.of(context).textTheme.bodyMedium,
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
    this.maxLines = 1,
  });

  final String product;
  final String quantity;
  final String price;
  final String amount;
  final TextStyle? style;
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
        cell(product, 4),
        cell(quantity, 2),
        cell(price, 2),
        cell(amount, 2),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({super.key, required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(AppStrings.productLabel, item.product),
            _Field(AppStrings.quantityLabel, '${item.quantity}'),
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
    );
  }
}
