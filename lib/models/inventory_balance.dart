import 'package:flutter/foundation.dart';

/// One row of the inventory balances file.
@immutable
class InventoryBalance {
  const InventoryBalance({
    required this.address,
    required this.productId,
    required this.serialNumber,
    required this.quantity,
  });

  /// Storage location, trimmed.
  final String address;

  /// Identifier kept as text (19 digits do not fit a JavaScript number).
  final String productId;

  /// Text, never a number: may contain letters and leading zeroes. Not
  /// guaranteed to be unique.
  final String serialNumber;
  final int quantity;

  @override
  bool operator ==(Object other) =>
      other is InventoryBalance &&
      other.address == address &&
      other.productId == productId &&
      other.serialNumber == serialNumber &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(address, productId, serialNumber, quantity);

  @override
  String toString() =>
      'InventoryBalance($address, $productId, $serialNumber, x$quantity)';
}
