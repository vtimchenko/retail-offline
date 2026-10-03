import 'package:flutter/foundation.dart';

/// One product line of an [Order] (one Excel row of the orders file).
///
/// Money is stored in integer minor units (kopiykas): `329.00` → `32900`.
/// [amountMinorUnits] is stored exactly as supplied; it is NOT derived from
/// [priceMinorUnits] × [quantity] (the source data does not always satisfy
/// that).
@immutable
class OrderItem {
  const OrderItem({
    required this.product,
    required this.productId,
    required this.quantity,
    required this.priceMinorUnits,
    required this.amountMinorUnits,
  });

  final String product;

  /// Identifier kept as text: real ids have 19 digits and would lose
  /// precision as a number (especially in JavaScript).
  final String productId;
  final int quantity;
  final int priceMinorUnits;
  final int amountMinorUnits;

  @override
  bool operator ==(Object other) =>
      other is OrderItem &&
      other.product == product &&
      other.productId == productId &&
      other.quantity == quantity &&
      other.priceMinorUnits == priceMinorUnits &&
      other.amountMinorUnits == amountMinorUnits;

  @override
  int get hashCode => Object.hash(
    product,
    productId,
    quantity,
    priceMinorUnits,
    amountMinorUnits,
  );

  @override
  String toString() => 'OrderItem($productId x$quantity)';
}

/// A customer order. One order can span several Excel rows; each row is an
/// [OrderItem]. Order-level values repeat in every row and are identical for
/// all items of the order.
@immutable
class Order {
  Order({
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.orderNumber,
    required this.customer,
    required this.customerPhone,
    required List<OrderItem> items,
  }) : items = List.unmodifiable(items);

  final DateTime invoiceDate;
  final String invoiceNumber;
  final String orderNumber;
  final String customer;

  /// Text, never a number: leading zeroes must be preserved.
  final String customerPhone;
  final List<OrderItem> items;

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.invoiceDate == invoiceDate &&
      other.invoiceNumber == invoiceNumber &&
      other.orderNumber == orderNumber &&
      other.customer == customer &&
      other.customerPhone == customerPhone &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(
    invoiceDate,
    invoiceNumber,
    orderNumber,
    customer,
    customerPhone,
    Object.hashAll(items),
  );

  @override
  String toString() => 'Order($orderNumber, ${items.length} items)';
}
