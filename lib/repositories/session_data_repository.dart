import '../models/inventory_balance.dart';
import '../models/order.dart';

/// Data imported for the current session.
///
/// Parsing and UI depend only on this interface, so a persistent
/// implementation can replace [InMemorySessionDataRepository] later.
abstract interface class SessionDataRepository {
  /// True once a successful [commit] has happened.
  bool get hasData;

  List<Order> get orders;
  List<InventoryBalance> get inventory;

  /// Number of [Order]s (not Excel rows).
  int get orderCount;

  /// Total [OrderItem]s over all orders (≈ Excel rows of the orders file).
  int get orderItemCount;

  int get inventoryCount;

  /// Replaces BOTH datasets at once. Nothing changes if this throws.
  void commit({
    required List<Order> orders,
    required List<InventoryBalance> inventory,
  });

  Order? orderByNumber(String orderNumber);
  List<Order> ordersByPhone(String customerPhone);
  List<InventoryBalance> inventoryByProductId(String productId);
  List<InventoryBalance> inventoryBySerialNumber(String serialNumber);
}

/// Keeps the session data in memory only: it disappears on page reload or
/// when the PWA is closed (accepted for this version).
class InMemorySessionDataRepository implements SessionDataRepository {
  List<Order> _orders = const [];
  List<InventoryBalance> _inventory = const [];
  int _orderItemCount = 0;
  bool _hasData = false;

  Map<String, Order> _ordersByNumber = const {};
  Map<String, List<Order>> _ordersByPhone = const {};
  Map<String, List<InventoryBalance>> _inventoryByProductId = const {};
  Map<String, List<InventoryBalance>> _inventoryBySerial = const {};

  @override
  bool get hasData => _hasData;

  @override
  List<Order> get orders => _orders;

  @override
  List<InventoryBalance> get inventory => _inventory;

  @override
  int get orderCount => _orders.length;

  @override
  int get orderItemCount => _orderItemCount;

  @override
  int get inventoryCount => _inventory.length;

  @override
  void commit({
    required List<Order> orders,
    required List<InventoryBalance> inventory,
  }) {
    // Build everything first; assign only when nothing can fail any more, so
    // a failure never leaves the repository half-updated.
    final ordersByNumber = <String, Order>{};
    final ordersByPhone = <String, List<Order>>{};
    var itemCount = 0;
    for (final order in orders) {
      if (ordersByNumber.containsKey(order.orderNumber)) {
        throw ArgumentError.value(
          order.orderNumber,
          'orders',
          'Duplicate order number',
        );
      }
      ordersByNumber[order.orderNumber] = order;
      (ordersByPhone[order.customerPhone] ??= []).add(order);
      itemCount += order.items.length;
    }

    final byProduct = <String, List<InventoryBalance>>{};
    final bySerial = <String, List<InventoryBalance>>{};
    for (final balance in inventory) {
      (byProduct[balance.productId] ??= []).add(balance);
      (bySerial[balance.serialNumber] ??= []).add(balance);
    }

    _orders = List.unmodifiable(orders);
    _inventory = List.unmodifiable(inventory);
    _orderItemCount = itemCount;
    _ordersByNumber = ordersByNumber;
    _ordersByPhone = ordersByPhone;
    _inventoryByProductId = byProduct;
    _inventoryBySerial = bySerial;
    _hasData = true;
  }

  @override
  Order? orderByNumber(String orderNumber) => _ordersByNumber[orderNumber];

  @override
  List<Order> ordersByPhone(String customerPhone) =>
      _ordersByPhone[customerPhone] ?? const [];

  @override
  List<InventoryBalance> inventoryByProductId(String productId) =>
      _inventoryByProductId[productId] ?? const [];

  @override
  List<InventoryBalance> inventoryBySerialNumber(String serialNumber) =>
      _inventoryBySerial[serialNumber] ?? const [];
}
