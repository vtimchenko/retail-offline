import '../../models/order.dart';
import '../../repositories/order_export_repository.dart';
import '../../repositories/serial_selection_repository.dart';
import 'fulfilment_check.dart';

/// How far one order is toward a current fulfilment workbook.
///
/// Derived from [SerialSelectionRepository] and [OrderExportRepository].
/// It is not stored on [Order].
enum OrderProgress {
  /// No serial quantity is reserved for any item.
  none,

  /// At least one serial is reserved, and the order is not fully reserved.
  inProgress,

  /// Every item has its required quantity, and no current workbook exists.
  ready,

  /// A current fulfilment workbook is stored for this order.
  fileReady;

  /// Derives the progress of [order].
  ///
  /// A stored workbook wins, including when reservations no longer match.
  /// Invalidation of that workbook is the selection listener's job.
  static OrderProgress of(
    Order order,
    SerialSelectionRepository selections,
    OrderExportRepository exports,
  ) {
    if (exports.exportFor(order.orderNumber) != null) {
      return OrderProgress.fileReady;
    }
    if (FulfilmentCheck.check(order, selections).isComplete) {
      return OrderProgress.ready;
    }
    for (final item in order.items) {
      if (selections.selectedQuantity(order.orderNumber, item.productId) > 0) {
        return OrderProgress.inProgress;
      }
    }
    return OrderProgress.none;
  }
}
