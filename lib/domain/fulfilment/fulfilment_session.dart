import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/exact_integer.dart';
import '../../models/retail_dataset.dart';

/// Fulfilment overlay for one active [RetailDataset].
///
/// The value is immutable. Reservation, issuance, export, and dataset
/// replacement return a new session or a failure result and do not change
/// this one. Expected business failures are result values, not exceptions.
///
/// Reservations are owned by `(OrderID, ProductID)`. `OrderNumber` is not an
/// owner, and `dbName` does not select among sessions. Issued and exported
/// orders keep consuming stock until a replacement succeeds.
///
/// A reservation copies the overlay and reuses this dataset together with
/// the stock and order indexes. The copy is one map of lines that already
/// have reservations, one map of stock slots that already have reservations,
/// and a new slot map for the edited line. The cost follows the overlay,
/// not the number of rows in the dataset. Unchanged lines keep their slot
/// maps. A failure does not allocate a session.
@immutable
class FulfilmentSession {
  FulfilmentSession._({
    required this.dataset,
    required this._catalogue,
    required this._reservations,
    required this._reservedByStock,
    required this._issuedOrderIds,
    required this._exportedOrderIds,
  }) : assert(_exportedOrderIds.every(_issuedOrderIds.contains));

  /// Checks [dataset] and, when it is usable, returns an empty overlay.
  ///
  /// Duplicate stock keys are rejected here even when the dataset was built
  /// in Dart rather than by the JSON parser. Duplicate order ids and a
  /// repeated product id inside one order are rejected as well, because a
  /// line is identified by that pair. Quantities of duplicate stock rows
  /// are not added together.
  static OpenDatasetResult open(RetailDataset dataset) {
    final stockQuantity = <StockKey, int>{};
    for (final stock in dataset.stocks) {
      final key = StockKey.fromStock(stock);
      if (stockQuantity.containsKey(key)) {
        return DatasetRejected(DatasetProblem.duplicateStock(key));
      }
      stockQuantity[key] = stock.quantity;
    }

    final ordersById = <String, DatasetOrder>{};
    final goodsByLine = <LineKey, DatasetGood>{};
    for (final order in dataset.orders) {
      if (ordersById.containsKey(order.orderId)) {
        return DatasetRejected(DatasetProblem.duplicateOrder(order.orderId));
      }
      ordersById[order.orderId] = order;
      for (final good in order.goods) {
        final line = LineKey(order.orderId, good.productId.literal);
        if (goodsByLine.containsKey(line)) {
          return DatasetRejected(
            DatasetProblem.duplicateProduct(
              orderId: order.orderId,
              productId: good.productId.literal,
            ),
          );
        }
        goodsByLine[line] = good;
      }
    }

    return DatasetOpened(
      FulfilmentSession._(
        dataset: dataset,
        catalogue: _Catalogue(
          stockQuantity: Map.unmodifiable(stockQuantity),
          ordersById: Map.unmodifiable(ordersById),
          goodsByLine: Map.unmodifiable(goodsByLine),
        ),
        reservations: const {},
        reservedByStock: const {},
        issuedOrderIds: const {},
        exportedOrderIds: const {},
      ),
    );
  }

  /// Dataset whose stock and orders this overlay refers to.
  final RetailDataset dataset;

  final _Catalogue _catalogue;
  final Map<LineKey, Map<StockKey, int>> _reservations;
  final Map<StockKey, int> _reservedByStock;
  final Set<String> _issuedOrderIds;
  final Set<String> _exportedOrderIds;

  /// Derived status of [orderId], or `null` when the dataset has no such
  /// order.
  ///
  /// Exported and issued are stored flags. The other three states are
  /// computed from non-service lines. A service line never counts as a
  /// reserved unit.
  OrderStatus? statusOf(String orderId) {
    final order = _catalogue.ordersById[orderId];
    if (order == null) return null;
    if (_exportedOrderIds.contains(orderId)) return OrderStatus.exported;
    if (_issuedOrderIds.contains(orderId)) return OrderStatus.issued;

    var hasStockGoods = false;
    var anyReserved = false;
    var complete = true;
    for (final good in order.goods) {
      if (good.isServiceGood) continue;
      hasStockGoods = true;
      final reserved = lineReservedQuantity(
        orderId: orderId,
        productId: good.productId.literal,
      );
      if (reserved > 0) anyReserved = true;
      if (reserved != good.quantity) complete = false;
    }
    if (!hasStockGoods || complete) return OrderStatus.readyForIssue;
    if (anyReserved) return OrderStatus.inProgress;
    return OrderStatus.noSelection;
  }

  /// Units of this slot that no order has reserved.
  ///
  /// An unknown slot contributes nothing, so the result is zero.
  int availableQuantity({
    required String productId,
    required String address,
    required String serialNumber,
  }) {
    final key = StockKey(
      productId: productId,
      address: address,
      serialNumber: serialNumber,
    );
    final stock = _catalogue.stockQuantity[key];
    if (stock == null) return 0;
    return stock - (_reservedByStock[key] ?? 0);
  }

  /// Units reserved for this order line across every slot.
  int lineReservedQuantity({
    required String orderId,
    required String productId,
  }) {
    final slots = _reservations[LineKey(orderId, productId)];
    if (slots == null) return 0;
    var total = 0;
    for (final quantity in slots.values) {
      total += quantity;
    }
    return total;
  }

  /// Units this order line holds on one slot.
  int slotReservedQuantity({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
  }) {
    return _reservations[LineKey(orderId, productId)]?[StockKey(
          productId: productId,
          address: address,
          serialNumber: serialNumber,
        )] ??
        0;
  }

  /// Reserves up to [quantity] units of one manually chosen slot.
  ///
  /// [productId] is the exact decimal literal of an [ExactInteger], compared
  /// as text. [address] and [serialNumber] are compared as case-sensitive
  /// strings with the values already stored on the dataset.
  ///
  /// The applied quantity is the minimum of [quantity], the line's remaining
  /// requirement, and the units of this slot that are still free. No other
  /// slot is filled in. A line that already has its full quantity returns
  /// [LineComplete]. A slot with nothing free, while the line still needs
  /// units, returns [InsufficientStock]. Neither changes this session.
  ///
  /// On success the result's session shares [dataset] and the stock and
  /// order indexes. Only the reservation overlay is copied, in proportion
  /// to lines and slots that already hold reservations, plus the edited
  /// line's own slots.
  ReserveResult reserve({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
  }) {
    if (quantity < 1) {
      return const ReserveRejected(ReserveRejection.invalidQuantity);
    }
    final good = _catalogue.goodsByLine[LineKey(orderId, productId)];
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const ReserveRejected(ReserveRejection.unknownOrder);
    }
    if (good == null) {
      return const ReserveRejected(ReserveRejection.unknownLine);
    }
    if (_isLocked(orderId)) {
      return const ReserveRejected(ReserveRejection.orderLocked);
    }
    if (good.isServiceGood) {
      return const ReserveRejected(ReserveRejection.serviceLine);
    }
    if (good.isParcel && serialNumber != good.parcelTtn) {
      return const ReserveRejected(ReserveRejection.parcelMismatch);
    }

    final stock = StockKey(
      productId: productId,
      address: address,
      serialNumber: serialNumber,
    );
    final stockQuantity = _catalogue.stockQuantity[stock];
    if (stockQuantity == null) {
      return const ReserveRejected(ReserveRejection.unknownStock);
    }

    final line = LineKey(orderId, productId);
    final remaining =
        good.quantity -
        lineReservedQuantity(orderId: orderId, productId: productId);
    if (remaining == 0) {
      return const LineComplete();
    }
    final available = stockQuantity - (_reservedByStock[stock] ?? 0);
    if (available == 0) {
      return const InsufficientStock();
    }

    final applied = min(quantity, min(remaining, available));
    return ReserveApplied(
      session: _add(line, stock, applied),
      requestedQuantity: quantity,
      appliedQuantity: applied,
    );
  }

  /// Releases [quantity] units that this order line holds on one slot.
  ///
  /// The freed units are available to other orders on the returned session.
  /// Removing more than the line holds on that slot leaves this session
  /// unchanged.
  RemoveUnitsResult removeUnits({
    required String orderId,
    required String productId,
    required String address,
    required String serialNumber,
    required int quantity,
  }) {
    if (quantity < 1) {
      return const RemoveUnitsRejected(RemoveRejection.invalidQuantity);
    }
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const RemoveUnitsRejected(RemoveRejection.unknownOrder);
    }
    final line = LineKey(orderId, productId);
    if (!_catalogue.goodsByLine.containsKey(line)) {
      return const RemoveUnitsRejected(RemoveRejection.unknownLine);
    }
    if (_isLocked(orderId)) {
      return const RemoveUnitsRejected(RemoveRejection.orderLocked);
    }
    final stock = StockKey(
      productId: productId,
      address: address,
      serialNumber: serialNumber,
    );
    final current = _reservations[line]?[stock] ?? 0;
    if (current < quantity) {
      return const RemoveUnitsRejected(RemoveRejection.insufficientReserved);
    }
    return UnitsRemoved(
      session: _subtract(line, stock, quantity),
      removedQuantity: quantity,
    );
  }

  /// Drops every reservation of [orderId].
  ///
  /// Other orders are left as they are. An order that holds nothing is a
  /// successful no-op and returns this same session.
  ClearOrderResult clearOrder(String orderId) {
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const ClearOrderRejected(ClearRejection.unknownOrder);
    }
    if (_isLocked(orderId)) {
      return const ClearOrderRejected(ClearRejection.orderLocked);
    }

    final lineKeys = [
      for (final line in _reservations.keys)
        if (line.orderId == orderId) line,
    ];
    if (lineKeys.isEmpty) {
      return OrderCleared(session: this, clearedQuantity: 0);
    }

    final reservations = Map<LineKey, Map<StockKey, int>>.of(_reservations);
    final reservedByStock = Map<StockKey, int>.of(_reservedByStock);
    var cleared = 0;
    for (final line in lineKeys) {
      final slots = reservations.remove(line)!;
      for (final entry in slots.entries) {
        cleared += entry.value;
        final next = reservedByStock[entry.key]! - entry.value;
        if (next == 0) {
          reservedByStock.remove(entry.key);
        } else {
          reservedByStock[entry.key] = next;
        }
      }
    }
    return OrderCleared(
      session: _copy(
        reservations: Map.unmodifiable(reservations),
        reservedByStock: Map.unmodifiable(reservedByStock),
      ),
      clearedQuantity: cleared,
    );
  }

  /// Marks a ready order as issued without releasing its reservations.
  IssueOrderResult issueOrder(String orderId) {
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const IssueOrderRejected(IssueRejection.unknownOrder);
    }
    if (_isLocked(orderId)) {
      return const IssueOrderRejected(IssueRejection.alreadyIssued);
    }
    if (statusOf(orderId) != OrderStatus.readyForIssue) {
      return const IssueOrderRejected(IssueRejection.notReady);
    }
    return OrderIssued(
      session: _copy(
        issuedOrderIds: Set.unmodifiable({..._issuedOrderIds, orderId}),
      ),
    );
  }

  /// Returns an issued order to ready and keeps its reservations.
  ///
  /// An exported order stays exported.
  CancelIssuanceResult cancelIssuance(String orderId) {
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const CancelIssuanceRejected(CancelRejection.unknownOrder);
    }
    if (_exportedOrderIds.contains(orderId)) {
      return const CancelIssuanceRejected(CancelRejection.exported);
    }
    if (!_issuedOrderIds.contains(orderId)) {
      return const CancelIssuanceRejected(CancelRejection.notIssued);
    }
    final issued = Set<String>.of(_issuedOrderIds)..remove(orderId);
    return IssuanceCancelled(
      session: _copy(issuedOrderIds: Set.unmodifiable(issued)),
    );
  }

  /// Records that one issued order was included in an export.
  ///
  /// This only sets the exported flag. It does not build a file, and opening
  /// a share dialog is not this operation. The order stays issued and keeps
  /// its reservations. The flag cannot be cleared inside this dataset.
  ///
  /// An export that covers more than one order should use
  /// [markOrdersExported] instead of calling this method in a loop.
  MarkExportedResult markExported(String orderId) {
    if (!_catalogue.ordersById.containsKey(orderId)) {
      return const MarkExportedRejected(MarkExportRejection.unknownOrder);
    }
    if (_exportedOrderIds.contains(orderId)) {
      return const MarkExportedRejected(MarkExportRejection.alreadyExported);
    }
    if (!_issuedOrderIds.contains(orderId)) {
      return const MarkExportedRejected(MarkExportRejection.notIssued);
    }
    return OrderMarkedExported(
      session: _copy(
        exportedOrderIds: Set.unmodifiable({..._exportedOrderIds, orderId}),
      ),
    );
  }

  /// Marks every issued order in [orderIds] as exported, in one step.
  ///
  /// This is the domain primitive for a cumulative export. A later phase
  /// must call it only after that export's JSON has been generated
  /// successfully. This method does not build or share a file.
  ///
  /// Every id is validated before a session is published. One unknown id,
  /// or one id that has not been issued, rejects the whole batch and leaves
  /// this session unchanged. Orders that are already exported stay exported.
  /// Duplicate ids are recorded once. Reservations and the stock they
  /// consume stay in place.
  MarkOrdersExportedResult markOrdersExported(Iterable<String> orderIds) {
    final uniqueIds = <String>[];
    final seen = <String>{};
    final failures = <OrderExportFailure>[];
    for (final orderId in orderIds) {
      if (!seen.add(orderId)) continue;
      uniqueIds.add(orderId);
      if (!_catalogue.ordersById.containsKey(orderId)) {
        failures.add(
          OrderExportFailure(
            orderId: orderId,
            reason: BatchExportRejection.unknownOrder,
          ),
        );
      } else if (!_issuedOrderIds.contains(orderId)) {
        failures.add(
          OrderExportFailure(
            orderId: orderId,
            reason: BatchExportRejection.notIssued,
          ),
        );
      }
    }
    if (failures.isNotEmpty) {
      return MarkOrdersExportedRejected(List.unmodifiable(failures));
    }

    final exported = Set<String>.of(_exportedOrderIds);
    var changed = false;
    for (final orderId in uniqueIds) {
      if (exported.add(orderId)) changed = true;
    }
    if (!changed) return OrdersMarkedExported(session: this);
    return OrdersMarkedExported(
      session: _copy(exportedOrderIds: Set.unmodifiable(exported)),
    );
  }

  /// Replaces the active dataset when no unfinished work remains.
  ///
  /// [next] is validated before the current overlay is consulted. An invalid
  /// dataset, including duplicate stock keys, keeps this session. Otherwise
  /// replacement is refused while any unissued order still has reservations
  /// or any issued order is not exported. A service-only issued order blocks
  /// even though it has no stock units. Exported orders do not block.
  ///
  /// The same rules apply when [next] has the same `dbName`. Success is a
  /// new session with an empty overlay. This session is left intact either
  /// way.
  ReplaceDatasetResult replaceDataset(RetailDataset next) {
    switch (FulfilmentSession.open(next)) {
      case DatasetRejected(:final problem):
        return ReplacementRejected(problem);
      case DatasetOpened(:final session):
        final blocking = _blockingOrderIds();
        if (blocking.isNotEmpty) return ReplacementBlocked(blocking);
        return DatasetReplaced(session: session);
    }
  }

  bool _isLocked(String orderId) => _issuedOrderIds.contains(orderId);

  List<String> _blockingOrderIds() {
    final blocking = <String>[];
    for (final order in dataset.orders) {
      final orderId = order.orderId;
      if (_exportedOrderIds.contains(orderId)) continue;
      if (_issuedOrderIds.contains(orderId) || _hasReservation(orderId)) {
        blocking.add(orderId);
      }
    }
    return List.unmodifiable(blocking);
  }

  bool _hasReservation(String orderId) {
    for (final line in _reservations.keys) {
      if (line.orderId == orderId) return true;
    }
    return false;
  }

  FulfilmentSession _add(LineKey line, StockKey stock, int applied) {
    assert(applied > 0);
    final slots = Map<StockKey, int>.of(_reservations[line] ?? const {});
    slots[stock] = (slots[stock] ?? 0) + applied;
    final reservations = Map<LineKey, Map<StockKey, int>>.of(_reservations);
    reservations[line] = Map.unmodifiable(slots);
    final reservedByStock = Map<StockKey, int>.of(_reservedByStock);
    reservedByStock[stock] = (_reservedByStock[stock] ?? 0) + applied;
    return _copy(
      reservations: Map.unmodifiable(reservations),
      reservedByStock: Map.unmodifiable(reservedByStock),
    );
  }

  FulfilmentSession _subtract(LineKey line, StockKey stock, int quantity) {
    final slots = Map<StockKey, int>.of(_reservations[line]!);
    final nextSlot = slots[stock]! - quantity;
    if (nextSlot == 0) {
      slots.remove(stock);
    } else {
      slots[stock] = nextSlot;
    }
    final reservations = Map<LineKey, Map<StockKey, int>>.of(_reservations);
    if (slots.isEmpty) {
      reservations.remove(line);
    } else {
      reservations[line] = Map.unmodifiable(slots);
    }
    final reservedByStock = Map<StockKey, int>.of(_reservedByStock);
    final nextStock = reservedByStock[stock]! - quantity;
    if (nextStock == 0) {
      reservedByStock.remove(stock);
    } else {
      reservedByStock[stock] = nextStock;
    }
    return _copy(
      reservations: Map.unmodifiable(reservations),
      reservedByStock: Map.unmodifiable(reservedByStock),
    );
  }

  FulfilmentSession _copy({
    Map<LineKey, Map<StockKey, int>>? reservations,
    Map<StockKey, int>? reservedByStock,
    Set<String>? issuedOrderIds,
    Set<String>? exportedOrderIds,
  }) {
    return FulfilmentSession._(
      dataset: dataset,
      catalogue: _catalogue,
      reservations: reservations ?? _reservations,
      reservedByStock: reservedByStock ?? _reservedByStock,
      issuedOrderIds: issuedOrderIds ?? _issuedOrderIds,
      exportedOrderIds: exportedOrderIds ?? _exportedOrderIds,
    );
  }

  @override
  String toString() =>
      'FulfilmentSession(${dataset.dbName}, '
      '${_reservations.length} reserved lines, '
      '${_issuedOrderIds.length} issued, '
      '${_exportedOrderIds.length} exported)';
}

/// Stock identity `(ProductID, Address, SerialNumber)`.
///
/// [productId] is the exact decimal literal. It is never parsed as a
/// floating-point number. [address] and [serialNumber] use case-sensitive
/// string equality.
@immutable
class StockKey {
  const StockKey({
    required this.productId,
    required this.address,
    required this.serialNumber,
  });

  factory StockKey.fromStock(DatasetStock stock) => StockKey(
    productId: stock.productId.literal,
    address: stock.address,
    serialNumber: stock.serialNumber,
  );

  final String productId;
  final String address;
  final String serialNumber;

  @override
  bool operator ==(Object other) =>
      other is StockKey &&
      other.productId == productId &&
      other.address == address &&
      other.serialNumber == serialNumber;

  @override
  int get hashCode => Object.hash(productId, address, serialNumber);

  @override
  String toString() => 'StockKey($productId, $address, $serialNumber)';
}

/// Reservation owner `(OrderID, ProductID)`.
///
/// [productId] is the exact decimal literal. `OrderNumber` is not part of
/// the key.
@immutable
class LineKey {
  const LineKey(this.orderId, this.productId);

  final String orderId;
  final String productId;

  @override
  bool operator ==(Object other) =>
      other is LineKey &&
      other.orderId == orderId &&
      other.productId == productId;

  @override
  int get hashCode => Object.hash(orderId, productId);

  @override
  String toString() => 'LineKey($orderId, $productId)';
}

/// Derived fulfilment state of one order.
enum OrderStatus {
  /// No non-service unit is reserved.
  noSelection('Без вибору'),

  /// At least one non-service unit is reserved, and some remain.
  inProgress('В процесі'),

  /// Every non-service line is fully reserved, or the order is service-only.
  readyForIssue('Готово до видачі'),

  /// Issued by an explicit operation. Reservations stay and edits are locked.
  issued('Видано'),

  /// Included in an export. Permanently locked inside this dataset.
  exported('Експортовано');

  const OrderStatus(this.label);

  /// Ukrainian label shown to a store employee.
  final String label;
}

/// Why a hand-built or parsed dataset cannot become a session.
enum DatasetProblemReason {
  /// Two stock rows share `(ProductID, Address, SerialNumber)`.
  duplicateStock,

  /// Two orders share an `OrderID`.
  duplicateOrder,

  /// One order repeats a `ProductID`.
  duplicateProduct,
}

/// Identity that prevented a dataset from opening.
@immutable
class DatasetProblem {
  DatasetProblem.duplicateStock(StockKey key)
    : reason = DatasetProblemReason.duplicateStock,
      orderId = null,
      productId = key.productId,
      address = key.address,
      serialNumber = key.serialNumber;

  const DatasetProblem.duplicateOrder(this.orderId)
    : reason = DatasetProblemReason.duplicateOrder,
      productId = null,
      address = null,
      serialNumber = null;

  const DatasetProblem.duplicateProduct({
    required this.orderId,
    required this.productId,
  }) : reason = DatasetProblemReason.duplicateProduct,
       address = null,
       serialNumber = null;

  final DatasetProblemReason reason;
  final String? orderId;
  final String? productId;
  final String? address;
  final String? serialNumber;

  @override
  String toString() =>
      'DatasetProblem($reason, order: $orderId, '
      'product: $productId, $address, $serialNumber)';
}

/// Result of [FulfilmentSession.open].
sealed class OpenDatasetResult {
  const OpenDatasetResult();
}

/// [session] has no reservations and no issued or exported orders.
final class DatasetOpened extends OpenDatasetResult {
  const DatasetOpened(this.session);

  final FulfilmentSession session;
}

/// [problem] describes the first duplicate identity that was found.
final class DatasetRejected extends OpenDatasetResult {
  const DatasetRejected(this.problem);

  final DatasetProblem problem;
}

/// Result of [FulfilmentSession.reserve].
sealed class ReserveResult {
  const ReserveResult();
}

/// [appliedQuantity] units were reserved in [session].
///
/// [appliedQuantity] may be smaller than [requestedQuantity] when the line
/// or the chosen slot cannot take the whole request. The whole applied
/// quantity is one update.
final class ReserveApplied extends ReserveResult {
  const ReserveApplied({
    required this.session,
    required this.requestedQuantity,
    required this.appliedQuantity,
  });

  final FulfilmentSession session;
  final int requestedQuantity;
  final int appliedQuantity;
}

/// The chosen slot has no free units and the line still needs some.
final class InsufficientStock extends ReserveResult {
  const InsufficientStock();

  @override
  String toString() => 'InsufficientStock';
}

/// The order line already has its full quantity.
final class LineComplete extends ReserveResult {
  const LineComplete();

  @override
  String toString() => 'LineComplete';
}

/// [FulfilmentSession.reserve] rejected the request before changing state.
final class ReserveRejected extends ReserveResult {
  const ReserveRejected(this.reason);

  final ReserveRejection reason;

  @override
  String toString() => 'ReserveRejected($reason)';
}

/// Why [FulfilmentSession.reserve] made no change.
enum ReserveRejection {
  invalidQuantity,
  unknownOrder,
  unknownLine,
  unknownStock,
  parcelMismatch,
  serviceLine,
  orderLocked,
}

/// Result of [FulfilmentSession.removeUnits].
sealed class RemoveUnitsResult {
  const RemoveUnitsResult();
}

/// [removedQuantity] units were released in [session].
final class UnitsRemoved extends RemoveUnitsResult {
  const UnitsRemoved({required this.session, required this.removedQuantity});

  final FulfilmentSession session;
  final int removedQuantity;
}

/// [FulfilmentSession.removeUnits] rejected the request.
final class RemoveUnitsRejected extends RemoveUnitsResult {
  const RemoveUnitsRejected(this.reason);

  final RemoveRejection reason;

  @override
  String toString() => 'RemoveUnitsRejected($reason)';
}

/// Why [FulfilmentSession.removeUnits] made no change.
enum RemoveRejection {
  invalidQuantity,
  unknownOrder,
  unknownLine,
  orderLocked,
  insufficientReserved,
}

/// Result of [FulfilmentSession.clearOrder].
sealed class ClearOrderResult {
  const ClearOrderResult();
}

/// Reservations of one order were removed, or there were none.
final class OrderCleared extends ClearOrderResult {
  const OrderCleared({required this.session, required this.clearedQuantity});

  final FulfilmentSession session;
  final int clearedQuantity;
}

/// [FulfilmentSession.clearOrder] rejected the request.
final class ClearOrderRejected extends ClearOrderResult {
  const ClearOrderRejected(this.reason);

  final ClearRejection reason;

  @override
  String toString() => 'ClearOrderRejected($reason)';
}

/// Why [FulfilmentSession.clearOrder] made no change.
enum ClearRejection { unknownOrder, orderLocked }

/// Result of [FulfilmentSession.issueOrder].
sealed class IssueOrderResult {
  const IssueOrderResult();
}

/// The order is issued in [session] and its reservations are unchanged.
final class OrderIssued extends IssueOrderResult {
  const OrderIssued({required this.session});

  final FulfilmentSession session;
}

/// [FulfilmentSession.issueOrder] rejected the request.
final class IssueOrderRejected extends IssueOrderResult {
  const IssueOrderRejected(this.reason);

  final IssueRejection reason;

  @override
  String toString() => 'IssueOrderRejected($reason)';
}

/// Why [FulfilmentSession.issueOrder] made no change.
enum IssueRejection { unknownOrder, notReady, alreadyIssued }

/// Result of [FulfilmentSession.cancelIssuance].
sealed class CancelIssuanceResult {
  const CancelIssuanceResult();
}

/// The order is ready again in [session]. Its reservations are unchanged.
final class IssuanceCancelled extends CancelIssuanceResult {
  const IssuanceCancelled({required this.session});

  final FulfilmentSession session;
}

/// [FulfilmentSession.cancelIssuance] rejected the request.
final class CancelIssuanceRejected extends CancelIssuanceResult {
  const CancelIssuanceRejected(this.reason);

  final CancelRejection reason;

  @override
  String toString() => 'CancelIssuanceRejected($reason)';
}

/// Why [FulfilmentSession.cancelIssuance] made no change.
enum CancelRejection { unknownOrder, notIssued, exported }

/// Result of [FulfilmentSession.markExported].
sealed class MarkExportedResult {
  const MarkExportedResult();
}

/// The order is exported in [session] and still holds its reservations.
final class OrderMarkedExported extends MarkExportedResult {
  const OrderMarkedExported({required this.session});

  final FulfilmentSession session;
}

/// [FulfilmentSession.markExported] rejected the request.
final class MarkExportedRejected extends MarkExportedResult {
  const MarkExportedRejected(this.reason);

  final MarkExportRejection reason;

  @override
  String toString() => 'MarkExportedRejected($reason)';
}

/// Why [FulfilmentSession.markExported] made no change.
enum MarkExportRejection { unknownOrder, notIssued, alreadyExported }

/// Result of [FulfilmentSession.markOrdersExported].
sealed class MarkOrdersExportedResult {
  const MarkOrdersExportedResult();
}

/// Every requested order is exported in [session].
///
/// Reservations are the same as before the call. When every requested order
/// was already exported, [session] is the session on which the method was
/// called.
final class OrdersMarkedExported extends MarkOrdersExportedResult {
  const OrdersMarkedExported({required this.session});

  final FulfilmentSession session;
}

/// At least one id was unknown or had not been issued.
///
/// No order in the batch was marked exported. [failures] follows the first
/// occurrence of each distinct id.
final class MarkOrdersExportedRejected extends MarkOrdersExportedResult {
  const MarkOrdersExportedRejected(this.failures);

  final List<OrderExportFailure> failures;

  @override
  String toString() => 'MarkOrdersExportedRejected($failures)';
}

/// One order that prevented [FulfilmentSession.markOrdersExported].
@immutable
class OrderExportFailure {
  const OrderExportFailure({required this.orderId, required this.reason});

  final String orderId;
  final BatchExportRejection reason;

  @override
  String toString() => 'OrderExportFailure($orderId, $reason)';
}

/// Why one id cannot be included in [FulfilmentSession.markOrdersExported].
enum BatchExportRejection { unknownOrder, notIssued }

/// Result of [FulfilmentSession.replaceDataset].
sealed class ReplaceDatasetResult {
  const ReplaceDatasetResult();
}

/// [session] is the incoming dataset with an empty overlay.
final class DatasetReplaced extends ReplaceDatasetResult {
  const DatasetReplaced({required this.session});

  final FulfilmentSession session;
}

/// Unfinished orders whose ids follow the current dataset order.
final class ReplacementBlocked extends ReplaceDatasetResult {
  const ReplacementBlocked(this.orderIds);

  final List<String> orderIds;

  @override
  String toString() => 'ReplacementBlocked($orderIds)';
}

/// The incoming dataset cannot be opened. The current session stays.
final class ReplacementRejected extends ReplaceDatasetResult {
  const ReplacementRejected(this.problem);

  final DatasetProblem problem;

  @override
  String toString() => 'ReplacementRejected($problem)';
}

class _Catalogue {
  const _Catalogue({
    required this.stockQuantity,
    required this.ordersById,
    required this.goodsByLine,
  });

  final Map<StockKey, int> stockQuantity;
  final Map<String, DatasetOrder> ordersById;
  final Map<LineKey, DatasetGood> goodsByLine;
}
