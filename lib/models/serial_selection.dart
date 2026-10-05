import 'package:flutter/foundation.dart';

/// Identifies the order line that owns a reservation.
///
/// [orderNumber] and [productId] are the exact imported strings. Product id
/// is unique within one order, so the pair identifies one order line.
@immutable
class SelectionOwner {
  const SelectionOwner({required this.orderNumber, required this.productId});

  final String orderNumber;
  final String productId;

  @override
  bool operator ==(Object other) =>
      other is SelectionOwner &&
      other.orderNumber == orderNumber &&
      other.productId == productId;

  @override
  int get hashCode => Object.hash(orderNumber, productId);

  @override
  String toString() => 'SelectionOwner($orderNumber, $productId)';
}

/// Identifies one inventory pool that can be reserved.
///
/// The same [serialNumber] may exist for another product or at another
/// [address], so all three strings are required. Imported rows that share
/// this identity are one quantity pool.
@immutable
class InventorySlot {
  const InventorySlot({
    required this.productId,
    required this.address,
    required this.serialNumber,
  });

  final String productId;
  final String address;
  final String serialNumber;

  @override
  bool operator ==(Object other) =>
      other is InventorySlot &&
      other.productId == productId &&
      other.address == address &&
      other.serialNumber == serialNumber;

  @override
  int get hashCode => Object.hash(productId, address, serialNumber);

  @override
  String toString() => 'InventorySlot($productId, $address, $serialNumber)';
}

/// One row of the available-inventory list.
@immutable
class AvailableSerial {
  const AvailableSerial({
    required this.address,
    required this.serialNumber,
    required this.availableQuantity,
  });

  final String address;
  final String serialNumber;

  /// Units of this slot that no order line has reserved yet.
  final int availableQuantity;

  @override
  bool operator ==(Object other) =>
      other is AvailableSerial &&
      other.address == address &&
      other.serialNumber == serialNumber &&
      other.availableQuantity == availableQuantity;

  @override
  int get hashCode => Object.hash(address, serialNumber, availableQuantity);

  @override
  String toString() =>
      'AvailableSerial($address, $serialNumber, x$availableQuantity)';
}

/// One aggregated row reserved for a single order line.
@immutable
class SelectedSerial {
  const SelectedSerial({
    required this.address,
    required this.serialNumber,
    required this.quantity,
  });

  final String address;
  final String serialNumber;

  /// Units of this slot reserved by that order line.
  final int quantity;

  @override
  bool operator ==(Object other) =>
      other is SelectedSerial &&
      other.address == address &&
      other.serialNumber == serialNumber &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(address, serialNumber, quantity);

  @override
  String toString() => 'SelectedSerial($address, $serialNumber, x$quantity)';
}
