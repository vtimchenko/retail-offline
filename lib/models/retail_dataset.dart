import 'package:flutter/foundation.dart';

import 'exact_integer.dart';

/// Numeric limits shared by the dataset models and the validator.
abstract final class DatasetLimits {
  /// Largest accepted `Quantity`.
  static const int maxQuantity = 999999999;

  /// `999999999999.99` UAH in kopecks.
  static const int maxMinorUnits = 99999999999999;

  /// Largest order total, in kopecks, that JavaScript can store exactly.
  ///
  /// This is `Number.MAX_SAFE_INTEGER` (2^53 − 1).
  static const int maxSafeMinorUnits = 9007199254740991;
}

/// One stock row from a JSON dataset.
///
/// The parser rejects a second row with the same product, address and
/// serial number. This value does not merge quantities.
@immutable
class DatasetStock {
  const DatasetStock({
    required this.address,
    required this.productId,
    required this.serialNumber,
    required this.quantity,
  }) : assert(quantity >= 1 && quantity <= DatasetLimits.maxQuantity);

  final String address;
  final ExactInteger productId;
  final String serialNumber;
  final int quantity;

  @override
  bool operator ==(Object other) =>
      other is DatasetStock &&
      other.address == address &&
      other.productId == productId &&
      other.serialNumber == serialNumber &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(address, productId, serialNumber, quantity);

  @override
  String toString() =>
      'DatasetStock($address, $productId, $serialNumber, x$quantity)';
}

/// One goods line of a [DatasetOrder].
///
/// Money is stored in kopecks (`324.50` → `32450`). [amountMinorUnits] is
/// the supplied amount, not `price × quantity`.
///
/// [isServiceGood] and [isParcel] come from JSON integers `0` and `1`.
/// The combination `(1, 1)` is rejected before a value is built.
/// [parcelTtn] is set only for parcel goods. [meestTtn] keeps the original
/// string when the field is present, including an empty string; a missing
/// field is `null`.
@immutable
class DatasetGood {
  const DatasetGood({
    required this.product,
    required this.productId,
    required this.quantity,
    required this.priceMinorUnits,
    required this.amountMinorUnits,
    required this.isServiceGood,
    required this.isParcel,
    this.parcelTtn,
    this.meestTtn,
  }) : assert(quantity >= 1 && quantity <= DatasetLimits.maxQuantity),
       assert(
         priceMinorUnits >= 0 && priceMinorUnits <= DatasetLimits.maxMinorUnits,
       ),
       assert(
         amountMinorUnits >= 0 &&
             amountMinorUnits <= DatasetLimits.maxMinorUnits,
       ),
       assert(!isServiceGood || !isParcel);

  final String product;
  final ExactInteger productId;
  final int quantity;
  final int priceMinorUnits;
  final int amountMinorUnits;
  final bool isServiceGood;
  final bool isParcel;
  final String? parcelTtn;
  final String? meestTtn;

  @override
  bool operator ==(Object other) =>
      other is DatasetGood &&
      other.product == product &&
      other.productId == productId &&
      other.quantity == quantity &&
      other.priceMinorUnits == priceMinorUnits &&
      other.amountMinorUnits == amountMinorUnits &&
      other.isServiceGood == isServiceGood &&
      other.isParcel == isParcel &&
      other.parcelTtn == parcelTtn &&
      other.meestTtn == meestTtn;

  @override
  int get hashCode => Object.hash(
    product,
    productId,
    quantity,
    priceMinorUnits,
    amountMinorUnits,
    isServiceGood,
    isParcel,
    parcelTtn,
    meestTtn,
  );

  @override
  String toString() => 'DatasetGood($productId x$quantity)';
}

/// One customer order from a JSON dataset.
@immutable
class DatasetOrder {
  DatasetOrder({
    required this.orderId,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.orderNumber,
    required this.customer,
    required this.customerPhone,
    required this.totalMinorUnits,
    required List<DatasetGood> goods,
  }) : assert(goods.isNotEmpty),
       assert(
         totalMinorUnits >= 0 &&
             totalMinorUnits <= DatasetLimits.maxSafeMinorUnits,
       ),
       goods = List.unmodifiable(goods);

  final String orderId;
  final DateTime invoiceDate;
  final String invoiceNumber;

  /// JSON integer token, kept as text.
  ///
  /// The same number may appear on more than one order.
  final ExactInteger orderNumber;
  final String customer;
  final String customerPhone;

  /// Sum of [DatasetGood.amountMinorUnits] for this order, in kopecks.
  ///
  /// The parser rejects an order whose sum would exceed
  /// [DatasetLimits.maxSafeMinorUnits]. The addition that produces this
  /// value never uses floating-point arithmetic.
  final int totalMinorUnits;
  final List<DatasetGood> goods;

  @override
  bool operator ==(Object other) =>
      other is DatasetOrder &&
      other.orderId == orderId &&
      other.invoiceDate == invoiceDate &&
      other.invoiceNumber == invoiceNumber &&
      other.orderNumber == orderNumber &&
      other.customer == customer &&
      other.customerPhone == customerPhone &&
      other.totalMinorUnits == totalMinorUnits &&
      listEquals(other.goods, goods);

  @override
  int get hashCode => Object.hash(
    orderId,
    invoiceDate,
    invoiceNumber,
    orderNumber,
    customer,
    customerPhone,
    totalMinorUnits,
    Object.hashAll(goods),
  );

  @override
  String toString() => 'DatasetOrder($orderId, ${goods.length} goods)';
}

/// A validated JSON dataset.
///
/// Parsing does not persist the value.
@immutable
class RetailDataset {
  RetailDataset({
    required this.storeName,
    required this.dbName,
    required this.dateCreate,
    required List<DatasetStock> stocks,
    required List<DatasetOrder> orders,
  }) : assert(stocks.isNotEmpty),
       assert(orders.isNotEmpty),
       stocks = List.unmodifiable(stocks),
       orders = List.unmodifiable(orders);

  final String storeName;
  final String dbName;
  final DateTime dateCreate;
  final List<DatasetStock> stocks;
  final List<DatasetOrder> orders;

  @override
  bool operator ==(Object other) =>
      other is RetailDataset &&
      other.storeName == storeName &&
      other.dbName == dbName &&
      other.dateCreate == dateCreate &&
      listEquals(other.stocks, stocks) &&
      listEquals(other.orders, orders);

  @override
  int get hashCode => Object.hash(
    storeName,
    dbName,
    dateCreate,
    Object.hashAll(stocks),
    Object.hashAll(orders),
  );

  @override
  String toString() =>
      'RetailDataset($storeName, ${stocks.length} stocks, '
      '${orders.length} orders)';
}
