import '../models/inventory_balance.dart';
import '../models/serial_selection.dart';

/// In-memory serial reservations for the current browser session.
///
/// Nothing is written to disk. A successful data import clears these
/// reservations because the imported inventory snapshot has been replaced.
abstract interface class SerialSelectionRepository {
  /// Sum of selected quantities for this order line, across every slot.
  int selectedQuantity(String orderNumber, String productId);

  /// Available rows for [productId], in first-seen inventory order.
  ///
  /// Available quantity is the imported stock of that slot minus the quantity
  /// selected by every owner, including the order line being edited. Slots
  /// with no remaining quantity are omitted. Rows that share product, address
  /// and serial are summed into one pool.
  List<AvailableSerial> availableFor({
    required String productId,
    required List<InventoryBalance> inventory,
  });

  /// Slots reserved by this order line, in the order they were first selected.
  ///
  /// Each slot appears once. The quantity is the number of units reserved.
  List<SelectedSerial> selectedFor({
    required String orderNumber,
    required String productId,
  });

  /// Reserves one unit of the slot for this order line.
  ///
  /// Returns `false` without changing state when the slot has no remaining
  /// stock, or when this order line already has [requiredQuantity] units
  /// selected across all of its slots. [inventory] is only read.
  bool addOne({
    required String orderNumber,
    required String productId,
    required String address,
    required String serialNumber,
    required List<InventoryBalance> inventory,
    required int requiredQuantity,
  });

  /// Releases one reserved unit of the slot for this order line.
  ///
  /// Returns `false` when this order line has nothing reserved there.
  bool removeOne({
    required String orderNumber,
    required String productId,
    required String address,
    required String serialNumber,
  });

  /// Drops every reservation.
  void clear();
}

/// Keeps serial reservations in memory only.
///
/// They disappear on page reload, when the PWA is closed, and when [clear]
/// runs after a successful import.
class InMemorySerialSelectionRepository implements SerialSelectionRepository {
  final Map<SelectionOwner, Map<InventorySlot, int>> _byOwner = {};

  @override
  int selectedQuantity(String orderNumber, String productId) {
    final slots = _byOwner[_owner(orderNumber, productId)];
    if (slots == null) return 0;
    var total = 0;
    for (final quantity in slots.values) {
      total += quantity;
    }
    return total;
  }

  @override
  List<AvailableSerial> availableFor({
    required String productId,
    required List<InventoryBalance> inventory,
  }) {
    final stockBySlot = <InventorySlot, int>{};
    for (final balance in inventory) {
      if (balance.productId != productId) continue;
      final slot = InventorySlot(
        productId: productId,
        address: balance.address,
        serialNumber: balance.serialNumber,
      );
      stockBySlot[slot] = (stockBySlot[slot] ?? 0) + balance.quantity;
    }

    final rows = <AvailableSerial>[];
    for (final entry in stockBySlot.entries) {
      final available = entry.value - _reserved(entry.key);
      if (available <= 0) continue;
      rows.add(
        AvailableSerial(
          address: entry.key.address,
          serialNumber: entry.key.serialNumber,
          availableQuantity: available,
        ),
      );
    }
    return List.unmodifiable(rows);
  }

  @override
  List<SelectedSerial> selectedFor({
    required String orderNumber,
    required String productId,
  }) {
    final slots = _byOwner[_owner(orderNumber, productId)];
    if (slots == null || slots.isEmpty) return const [];
    return List.unmodifiable([
      for (final entry in slots.entries)
        if (entry.value > 0)
          SelectedSerial(
            address: entry.key.address,
            serialNumber: entry.key.serialNumber,
            quantity: entry.value,
          ),
    ]);
  }

  @override
  bool addOne({
    required String orderNumber,
    required String productId,
    required String address,
    required String serialNumber,
    required List<InventoryBalance> inventory,
    required int requiredQuantity,
  }) {
    if (selectedQuantity(orderNumber, productId) >= requiredQuantity) {
      return false;
    }
    final slot = _slot(productId, address, serialNumber);
    if (_reserved(slot) >= _stock(slot, inventory)) return false;

    final slots = _byOwner.putIfAbsent(
      _owner(orderNumber, productId),
      () => {},
    );
    slots[slot] = (slots[slot] ?? 0) + 1;
    return true;
  }

  @override
  bool removeOne({
    required String orderNumber,
    required String productId,
    required String address,
    required String serialNumber,
  }) {
    final owner = _owner(orderNumber, productId);
    final slots = _byOwner[owner];
    if (slots == null) return false;
    final slot = _slot(productId, address, serialNumber);
    final current = slots[slot] ?? 0;
    if (current <= 0) return false;
    if (current == 1) {
      slots.remove(slot);
      if (slots.isEmpty) _byOwner.remove(owner);
    } else {
      slots[slot] = current - 1;
    }
    return true;
  }

  @override
  void clear() => _byOwner.clear();

  SelectionOwner _owner(String orderNumber, String productId) =>
      SelectionOwner(orderNumber: orderNumber, productId: productId);

  InventorySlot _slot(String productId, String address, String serialNumber) =>
      InventorySlot(
        productId: productId,
        address: address,
        serialNumber: serialNumber,
      );

  int _reserved(InventorySlot slot) {
    var total = 0;
    for (final slots in _byOwner.values) {
      total += slots[slot] ?? 0;
    }
    return total;
  }

  int _stock(InventorySlot slot, List<InventoryBalance> inventory) {
    var total = 0;
    for (final balance in inventory) {
      if (balance.productId != slot.productId) continue;
      if (balance.address != slot.address) continue;
      if (balance.serialNumber != slot.serialNumber) continue;
      total += balance.quantity;
    }
    return total;
  }
}
