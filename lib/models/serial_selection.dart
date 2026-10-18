import 'package:flutter/foundation.dart';

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
