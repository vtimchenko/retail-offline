import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/format/display_format.dart';
import '../../core/theme/app_colors.dart';
import '../../models/order.dart';
import '../../models/store.dart';
import '../../repositories/session_data_repository.dart';
import '../../widgets/status_message.dart';
import 'order_details_screen.dart';
import 'order_search.dart';

/// Lists the orders loaded for this session and opens one on tap.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.store,
    required this.repository,
  });

  final Store store;
  final SessionDataRepository repository;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _orderNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) => setState(() {});

  void _openDetails(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailsScreen(store: widget.store, order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.repository.orders;
    final filtered = OrderSearch.filter(
      orders,
      orderNumberQuery: _orderNumberController.text,
      phoneQuery: _phoneController.text,
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.store.nameStore)),
      body: SafeArea(
        child: LayoutBuilder(
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
                          Text(
                            AppStrings.ordersScreenTitle,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 16),
                          _SearchFields(
                            wide: wide,
                            orderNumberController: _orderNumberController,
                            phoneController: _phoneController,
                            onChanged: _onSearchChanged,
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _OrdersBody(
                              allOrders: orders,
                              orders: filtered,
                              wide: wide,
                              onOpen: _openDetails,
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
        ),
      ),
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
      key: const Key('order-number-search'),
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
      key: const Key('customer-phone-search'),
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
    required this.allOrders,
    required this.orders,
    required this.wide,
    required this.onOpen,
  });

  final List<Order> allOrders;
  final List<Order> orders;
  final bool wide;
  final ValueChanged<Order> onOpen;

  @override
  Widget build(BuildContext context) {
    if (allOrders.isEmpty) {
      return const Center(
        child: StatusMessage(
          key: Key('orders-empty'),
          icon: Icons.receipt_long_outlined,
          title: AppStrings.ordersEmptyTitle,
          message: AppStrings.ordersEmptyMessage,
        ),
      );
    }
    if (orders.isEmpty) {
      return const Center(
        child: StatusMessage(
          key: Key('orders-no-match'),
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
          const _OrdersTableHeader(key: Key('orders-table-header')),
          const Divider(height: 1, color: AppColors.border),
        ],
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              if (wide) {
                return _OrderTableRow(
                  key: ValueKey(order.orderNumber),
                  order: order,
                  onTap: () => onOpen(order),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OrderCard(
                  key: ValueKey(order.orderNumber),
                  order: order,
                  onTap: () => onOpen(order),
                ),
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
        style: style,
        maxLines: 2,
      ),
    );
  }
}

class _OrderTableRow extends StatelessWidget {
  const _OrderTableRow({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: _OrderColumns(
          date: DisplayFormat.formatInvoiceDate(order.invoiceDate),
          invoiceNumber: order.invoiceNumber,
          orderNumber: order.orderNumber,
          customer: order.customer,
          phone: order.customerPhone,
          style: Theme.of(context).textTheme.bodyMedium,
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
    required this.style,
    this.maxLines = 1,
  });

  final String date;
  final String invoiceNumber;
  final String orderNumber;
  final String customer;
  final String phone;
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
        cell(date, 3),
        cell(invoiceNumber, 3),
        cell(orderNumber, 3),
        cell(customer, 4),
        cell(phone, 3),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardField(
                AppStrings.invoiceDateLabel,
                DisplayFormat.formatInvoiceDate(order.invoiceDate),
              ),
              _CardField(AppStrings.invoiceNumberLabel, order.invoiceNumber),
              _CardField(AppStrings.orderNumberLabel, order.orderNumber),
              _CardField(AppStrings.customerLabel, order.customer),
              _CardField(AppStrings.customerPhoneLabel, order.customerPhone),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardField extends StatelessWidget {
  const _CardField(this.label, this.value);

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
