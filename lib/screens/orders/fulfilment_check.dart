import 'package:flutter/foundation.dart';

import '../../models/order.dart';
import '../../repositories/serial_selection_repository.dart';

/// One order line whose reserved quantity is not the required quantity.
@immutable
class FulfilmentGap {
  const FulfilmentGap({
    required this.product,
    required this.requiredQuantity,
    required this.selectedQuantity,
  });

  /// Product name stored on the order line.
  final String product;

  /// Units the order line requires.
  final int requiredQuantity;

  /// Units currently reserved for this order line.
  final int selectedQuantity;

  @override
  bool operator ==(Object other) =>
      other is FulfilmentGap &&
      other.product == product &&
      other.requiredQuantity == requiredQuantity &&
      other.selectedQuantity == selectedQuantity;

  @override
  int get hashCode => Object.hash(product, requiredQuantity, selectedQuantity);
}

/// Outcome of checking every line of one order.
@immutable
class FulfilmentResult {
  FulfilmentResult({required List<FulfilmentGap> gaps})
    : gaps = List.unmodifiable(gaps);

  /// Lines that do not match, in order-item order.
  final List<FulfilmentGap> gaps;

  /// Whether every order line has the required serial quantity.
  bool get isComplete => gaps.isEmpty;
}

/// Compares each order line with the serial quantity reserved for it.
abstract final class FulfilmentCheck {
  /// Returns a gap for every item whose reserved sum is not its quantity.
  ///
  /// The reserved sum covers every inventory slot of that order number and
  /// product id. Items are checked independently.
  static FulfilmentResult check(
    Order order,
    SerialSelectionRepository selections,
  ) {
    final gaps = <FulfilmentGap>[];
    for (final item in order.items) {
      final selected = selections.selectedQuantity(
        order.orderNumber,
        item.productId,
      );
      if (selected == item.quantity) continue;
      gaps.add(
        FulfilmentGap(
          product: item.product,
          requiredQuantity: item.quantity,
          selectedQuantity: selected,
        ),
      );
    }
    return FulfilmentResult(gaps: gaps);
  }
}
