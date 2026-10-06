import '../models/order_export.dart';

/// Fulfilment workbooks for the current browser session.
///
/// Nothing is written to disk. A successful data import clears these
/// workbooks together with the serial reservations.
abstract interface class OrderExportRepository {
  /// The current workbook for [orderNumber], or `null` when none is stored.
  OrderExport? exportFor(String orderNumber);

  /// Stores [export], replacing any workbook already kept for its order.
  void put(OrderExport export);

  /// Drops the workbook for [orderNumber]. Other orders stay.
  void invalidate(String orderNumber);

  /// Drops every workbook.
  void clear();
}

/// Keeps fulfilment workbooks in memory only.
///
/// They disappear on page reload, when the PWA is closed, and when [clear]
/// runs after a successful import.
class InMemoryOrderExportRepository implements OrderExportRepository {
  final Map<String, OrderExport> _byOrder = {};

  @override
  OrderExport? exportFor(String orderNumber) => _byOrder[orderNumber];

  @override
  void put(OrderExport export) => _byOrder[export.orderNumber] = export;

  @override
  void invalidate(String orderNumber) => _byOrder.remove(orderNumber);

  @override
  void clear() => _byOrder.clear();
}
