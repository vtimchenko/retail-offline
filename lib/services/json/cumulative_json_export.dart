import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/fulfilment/fulfilment_session.dart';
import '../../models/exact_integer.dart';
import '../../models/retail_dataset.dart';

/// Canonical non-negative JSON integer token.
///
/// `0` and `11` match. `01` and `1e2` do not. The text is never parsed.
final _canonicalInteger = RegExp(r'^(0|[1-9][0-9]*)$');

/// Builds a cumulative JSON export from a [FulfilmentSession].
///
/// [prepare] returns a new session and file bytes. It does not store them
/// or replace the caller's session.
class CumulativeJsonExport {
  const CumulativeJsonExport();

  /// Prepares a cumulative export of issued and already exported orders.
  ///
  /// Returns [CumulativeExportUnchanged] when no order has
  /// [OrderStatus.issued]. Previously exported orders do not start an
  /// export. [now] is not called, and [FulfilmentSession.markOrdersExported]
  /// is not called.
  ///
  /// Otherwise reconstructs Goods for every issued and exported order. A
  /// consistency failure returns [CumulativeExportRejected] and does not
  /// read [now]. [session] is left as it was.
  ///
  /// A consistent session reads [now] once, or [DateTime.now] when [now] is
  /// omitted, and uses that local time for `dateCreate` and the filename.
  /// The returned [CumulativeExportPrepared.pendingSession] is the result of
  /// [FulfilmentSession.markOrdersExported] for the newly issued ids only.
  CumulativeExportResult prepare(
    FulfilmentSession session, {
    DateTime Function()? now,
  }) {
    final issuedIds = _newlyIssuedIds(session);
    if (issuedIds.isEmpty) {
      return const CumulativeExportUnchanged();
    }
    final reconstruction = _reconstruct(session);
    if (reconstruction.failures.isNotEmpty) {
      return CumulativeExportRejected(reconstruction.failures);
    }

    final clock = now ?? DateTime.now;
    final dateCreate = _localStamp(clock());
    final bytes = writeExport(
      storeName: session.dataset.storeName,
      dbName: session.dataset.dbName,
      dateCreate: dateCreate,
      orders: reconstruction.orders,
    );
    return switch (session.markOrdersExported(issuedIds)) {
      MarkOrdersExportedRejected(:final failures) => CumulativeExportRejected(
        List.unmodifiable([
          for (final failure in failures)
            CumulativeExportFailure(
              reason: switch (failure.reason) {
                BatchExportRejection.unknownOrder =>
                  CumulativeExportReason.unknownOrder,
                BatchExportRejection.notIssued =>
                  CumulativeExportReason.notIssued,
              },
              orderId: failure.orderId,
            ),
        ]),
      ),
      OrdersMarkedExported(:final session) => CumulativeExportPrepared(
        pendingSession: session,
        document: ExportDocument(
          filename: 'export_${session.dataset.dbName}_$dateCreate.json',
          bytes: bytes,
          dateCreate: dateCreate,
        ),
      ),
    };
  }

  /// Projects issued and exported orders without starting an export.
  ///
  /// Orders in any other status are absent. This does not read a clock or
  /// mark orders exported.
  @visibleForTesting
  ExportReconstruction reconstruct(FulfilmentSession session) =>
      _reconstruct(session);

  /// Writes [orders] as pretty UTF-8 JSON using the supplied [dateCreate].
  ///
  /// [dateCreate] is already formatted. This does not read a clock, build a
  /// filename, or mark orders exported. `OrderNumber` and `ProductID` are
  /// copied from [ExactInteger.literal] as JSON numbers.
  ///
  /// Throws [ArgumentError] when one of those literals is not a canonical
  /// non-negative integer token.
  @visibleForTesting
  Uint8List writeExport({
    required String storeName,
    required String dbName,
    required String dateCreate,
    required List<ReconstructedExportOrder> orders,
  }) {
    return utf8.encode(
      _exportJson(
        storeName: storeName,
        dbName: dbName,
        dateCreate: dateCreate,
        orders: orders,
      ),
    );
  }
}

List<String> _newlyIssuedIds(FulfilmentSession session) {
  return [
    for (final order in session.dataset.orders)
      if (session.statusOf(order.orderId) == OrderStatus.issued) order.orderId,
  ];
}

/// Local `yyyyMMddHHmmss` from [time].
///
/// A UTC value is converted with [DateTime.toLocal] first. Components are
/// zero-padded. The imported dataset stamp is not used.
String _localStamp(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}'
      '${two(local.month)}'
      '${two(local.day)}'
      '${two(local.hour)}'
      '${two(local.minute)}'
      '${two(local.second)}';
}

ExportReconstruction _reconstruct(FulfilmentSession session) {
  final stocksByProduct = <String, List<DatasetStock>>{};
  for (final stock in session.dataset.stocks) {
    (stocksByProduct[stock.productId.literal] ??= []).add(stock);
  }

  final orders = <ReconstructedExportOrder>[];
  final failures = <CumulativeExportFailure>[];
  for (final order in session.dataset.orders) {
    final status = session.statusOf(order.orderId);
    if (status != OrderStatus.issued && status != OrderStatus.exported) {
      continue;
    }
    final built = _reconstructOrder(session, order, stocksByProduct);
    orders.add(built.order);
    failures.addAll(built.failures);
  }
  return ExportReconstruction(orders: orders, failures: failures);
}

({ReconstructedExportOrder order, List<CumulativeExportFailure> failures})
_reconstructOrder(
  FulfilmentSession session,
  DatasetOrder order,
  Map<String, List<DatasetStock>> stocksByProduct,
) {
  final failures = <CumulativeExportFailure>[];
  if (!_canonicalInteger.hasMatch(order.orderNumber.literal)) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.invalidIntegerLiteral,
        orderId: order.orderId,
      ),
    );
  }

  final grouped = <_GoodsKey, ReconstructedExportGood>{};
  for (final good in order.goods) {
    final productId = good.productId.literal;
    if (!_canonicalInteger.hasMatch(productId)) {
      failures.add(
        CumulativeExportFailure(
          reason: CumulativeExportReason.invalidIntegerLiteral,
          orderId: order.orderId,
          productId: productId,
        ),
      );
    }
    if (good.isServiceGood) {
      _reconstructService(session, order, good, grouped, failures);
    } else {
      _reconstructStockLine(
        session,
        order,
        good,
        stocksByProduct[productId] ?? const [],
        grouped,
        failures,
      );
    }
  }

  final goods = grouped.values.toList(growable: false);
  if (goods.isEmpty) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.emptyGoods,
        orderId: order.orderId,
      ),
    );
  }
  return (
    order: ReconstructedExportOrder(
      orderId: order.orderId,
      invoiceNumber: order.invoiceNumber,
      orderNumber: order.orderNumber,
      goods: goods,
    ),
    failures: List<CumulativeExportFailure>.unmodifiable(failures),
  );
}

void _reconstructService(
  FulfilmentSession session,
  DatasetOrder order,
  DatasetGood good,
  Map<_GoodsKey, ReconstructedExportGood> grouped,
  List<CumulativeExportFailure> failures,
) {
  final productId = good.productId.literal;
  final reserved = session.lineReservedQuantity(
    orderId: order.orderId,
    productId: productId,
  );
  if (reserved != 0) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.serviceHasReservation,
        orderId: order.orderId,
        productId: productId,
      ),
    );
  }
  _addGoods(grouped, good.productId, good.quantity, '', '');
}

void _reconstructStockLine(
  FulfilmentSession session,
  DatasetOrder order,
  DatasetGood good,
  List<DatasetStock> stocks,
  Map<_GoodsKey, ReconstructedExportGood> grouped,
  List<CumulativeExportFailure> failures,
) {
  final productId = good.productId.literal;
  final reserved = session.lineReservedQuantity(
    orderId: order.orderId,
    productId: productId,
  );
  if (reserved != good.quantity) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.reservationMismatch,
        orderId: order.orderId,
        productId: productId,
      ),
    );
  }

  var scanned = 0;
  var parcelMismatch = false;
  for (final stock in stocks) {
    final quantity = session.slotReservedQuantity(
      orderId: order.orderId,
      productId: productId,
      address: stock.address,
      serialNumber: stock.serialNumber,
    );
    if (quantity <= 0) continue;
    if (good.isParcel && stock.serialNumber != good.parcelTtn) {
      parcelMismatch = true;
    }
    scanned += quantity;
    _addGoods(
      grouped,
      good.productId,
      quantity,
      stock.address,
      stock.serialNumber,
    );
  }
  if (parcelMismatch) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.parcelSerialMismatch,
        orderId: order.orderId,
        productId: productId,
      ),
    );
  }
  if (scanned != reserved) {
    failures.add(
      CumulativeExportFailure(
        reason: CumulativeExportReason.slotTotalMismatch,
        orderId: order.orderId,
        productId: productId,
      ),
    );
  }
}

/// Adds [quantity] to the single Goods entry for this key.
///
/// A dataset cannot contain two stock rows with the same product, address,
/// and serial, so a reachable session adds each key once.
void _addGoods(
  Map<_GoodsKey, ReconstructedExportGood> grouped,
  ExactInteger productId,
  int quantity,
  String address,
  String serialNumber,
) {
  final key = _GoodsKey(productId.literal, address, serialNumber);
  final existing = grouped[key];
  if (existing == null) {
    grouped[key] = ReconstructedExportGood(
      productId: productId,
      quantity: quantity,
      address: address,
      serialNumber: serialNumber,
    );
    return;
  }
  grouped[key] = ReconstructedExportGood(
    productId: existing.productId,
    quantity: existing.quantity + quantity,
    address: address,
    serialNumber: serialNumber,
  );
}

@immutable
class _GoodsKey {
  const _GoodsKey(this.productId, this.address, this.serialNumber);

  final String productId;
  final String address;
  final String serialNumber;

  @override
  bool operator ==(Object other) =>
      other is _GoodsKey &&
      other.productId == productId &&
      other.address == address &&
      other.serialNumber == serialNumber;

  @override
  int get hashCode => Object.hash(productId, address, serialNumber);
}

String _exportJson({
  required String storeName,
  required String dbName,
  required String dateCreate,
  required List<ReconstructedExportOrder> orders,
}) {
  for (final order in orders) {
    _requireCanonical(order.orderNumber.literal, 'OrderNumber', order.orderId);
    for (final good in order.goods) {
      _requireCanonical(good.productId.literal, 'ProductID', order.orderId);
    }
  }

  final buffer = StringBuffer()..write('{\n');
  _jsonField(buffer, 1, 'storeName', jsonEncode(storeName));
  _jsonField(buffer, 1, 'dbName', jsonEncode(dbName));
  _jsonField(buffer, 1, 'dateCreate', jsonEncode(dateCreate));
  buffer.write('  "orders": ');
  _writeOrders(buffer, orders);
  buffer.write('\n}');
  return buffer.toString();
}

void _requireCanonical(String literal, String field, String orderId) {
  if (_canonicalInteger.hasMatch(literal)) return;
  throw ArgumentError.value(
    literal,
    field,
    'Order $orderId has a non-canonical $field',
  );
}

void _jsonField(StringBuffer buffer, int indent, String key, String jsonValue) {
  buffer
    ..write('  ' * indent)
    ..write('"')
    ..write(key)
    ..write('": ')
    ..write(jsonValue)
    ..write(',\n');
}

void _writeOrders(StringBuffer buffer, List<ReconstructedExportOrder> orders) {
  if (orders.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var i = 0; i < orders.length; i++) {
    _writeOrder(buffer, orders[i]);
    if (i + 1 != orders.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('  ]');
}

void _writeOrder(StringBuffer buffer, ReconstructedExportOrder order) {
  buffer.write('    {\n');
  _jsonField(buffer, 3, 'OrderID', jsonEncode(order.orderId));
  _jsonField(buffer, 3, 'InvoiceNumber', jsonEncode(order.invoiceNumber));
  _jsonField(buffer, 3, 'OrderNumber', order.orderNumber.literal);
  buffer.write('      "Goods": ');
  _writeGoods(buffer, order.goods);
  buffer.write('\n    }');
}

void _writeGoods(StringBuffer buffer, List<ReconstructedExportGood> goods) {
  if (goods.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var i = 0; i < goods.length; i++) {
    _writeGood(buffer, goods[i]);
    if (i + 1 != goods.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('      ]');
}

void _writeGood(StringBuffer buffer, ReconstructedExportGood good) {
  buffer.write('        {\n');
  _jsonField(buffer, 5, 'ProductID', good.productId.literal);
  _jsonField(buffer, 5, 'Quantity', good.quantity.toString());
  _jsonField(buffer, 5, 'Address', jsonEncode(good.address));
  buffer
    ..write('          "SerialNumber": ')
    ..write(jsonEncode(good.serialNumber))
    ..write('\n        }');
}

/// Outcome of [CumulativeJsonExport.prepare].
sealed class CumulativeExportResult {
  const CumulativeExportResult();
}

/// No newly issued order was found.
///
/// The caller keeps the session it passed in and any previously saved file.
final class CumulativeExportUnchanged extends CumulativeExportResult {
  const CumulativeExportUnchanged();
}

/// A generated file and the session that would record that export.
///
/// [pendingSession] is not active until a later phase stores it together
/// with [document]. [CumulativeJsonExport.prepare] does not store either.
final class CumulativeExportPrepared extends CumulativeExportResult {
  const CumulativeExportPrepared({
    required this.pendingSession,
    required this.document,
  });

  /// Session in which every order included from [OrderStatus.issued] is
  /// exported.
  final FulfilmentSession pendingSession;

  /// Filename and exact UTF-8 bytes of the generated file.
  final ExportDocument document;
}

/// The export was refused and the input session is unchanged.
final class CumulativeExportRejected extends CumulativeExportResult {
  const CumulativeExportRejected(this.failures);

  /// Every reason this attempt was refused, in discovery order.
  final List<CumulativeExportFailure> failures;

  @override
  String toString() => 'CumulativeExportRejected($failures)';
}

/// One reason [CumulativeJsonExport.prepare] refused an export.
@immutable
class CumulativeExportFailure {
  const CumulativeExportFailure({
    required this.reason,
    this.orderId,
    this.productId,
  });

  /// Why this export cannot continue.
  final CumulativeExportReason reason;

  /// Affected order, when the failure belongs to one order.
  final String? orderId;

  /// Affected product literal, when the failure belongs to one line.
  final String? productId;

  @override
  String toString() =>
      'CumulativeExportFailure($reason, order: $orderId, '
      'product: $productId)';
}

/// Machine-readable cause of [CumulativeExportFailure].
enum CumulativeExportReason {
  /// Reserved units on a non-service line are not the ordered quantity.
  reservationMismatch,

  /// Stock rows do not account for every unit reserved on a line.
  slotTotalMismatch,

  /// A reserved parcel serial is not that line's ParcelTTN.
  parcelSerialMismatch,

  /// A service line has reserved stock.
  serviceHasReservation,

  /// An included order produced no Goods entries.
  emptyGoods,

  /// An order number or product id is not a canonical integer token.
  invalidIntegerLiteral,

  /// [FulfilmentSession.markOrdersExported] rejected an unknown id.
  unknownOrder,

  /// [FulfilmentSession.markOrdersExported] rejected an id that is not issued.
  notIssued,
}

/// Exact bytes of one cumulative export file.
///
/// [dateCreate] and [filename] share one generation stamp. Holding this
/// value does not store the file.
@immutable
class ExportDocument {
  ExportDocument({
    required this.filename,
    required Uint8List bytes,
    required this.dateCreate,
  }) : _bytes = Uint8List.fromList(bytes);

  /// `export_{dbName}_yyyyMMddHHmmss.json`.
  final String filename;

  final Uint8List _bytes;

  /// Local generation stamp `yyyyMMddHHmmss`.
  final String dateCreate;

  /// A copy of the UTF-8 document.
  ///
  /// Changing the returned list does not change this document.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Issued and exported orders projected for a cumulative export.
///
/// [failures] follows dataset order, and line order inside each order.
/// [orders] uses that same order. Goods inside an order follow the order's
/// lines, and stock slots follow the dataset stock list.
@visibleForTesting
@immutable
class ExportReconstruction {
  ExportReconstruction({
    required List<ReconstructedExportOrder> orders,
    required List<CumulativeExportFailure> failures,
  }) : orders = List.unmodifiable(orders),
       failures = List.unmodifiable(failures);

  /// Included orders. Empty when every order is still unissued.
  final List<ReconstructedExportOrder> orders;

  /// Consistency problems found while projecting [orders].
  final List<CumulativeExportFailure> failures;
}

/// One order in an [ExportReconstruction].
@visibleForTesting
@immutable
class ReconstructedExportOrder {
  ReconstructedExportOrder({
    required this.orderId,
    required this.invoiceNumber,
    required this.orderNumber,
    required List<ReconstructedExportGood> goods,
  }) : goods = List.unmodifiable(goods);

  /// Dataset `OrderID`.
  final String orderId;

  /// Dataset `InvoiceNumber`.
  final String invoiceNumber;

  /// Dataset `OrderNumber`, still the original token.
  final ExactInteger orderNumber;

  /// Goods in line order, with stock slots in dataset order.
  final List<ReconstructedExportGood> goods;
}

/// One Goods entry inside a [ReconstructedExportOrder].
@visibleForTesting
@immutable
class ReconstructedExportGood {
  const ReconstructedExportGood({
    required this.productId,
    required this.quantity,
    required this.address,
    required this.serialNumber,
  });

  /// Dataset product token. It is not parsed as a number.
  final ExactInteger productId;

  /// Units reserved on this slot, or the ordered quantity of a service.
  final int quantity;

  /// Stock address, or an empty string for a service.
  final String address;

  /// Stock serial, or an empty string for a service.
  final String serialNumber;
}
