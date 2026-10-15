import 'package:flutter/foundation.dart';

/// Independent fulfilment overlay stored for one dataset.
///
/// Reservations and the issued and exported order ids are the only session
/// state. Available quantities and order status are derived again when a
/// session is restored. The caller supplies [datasetFingerprint]. This type
/// does not compute a hash.
@immutable
class SessionSnapshot {
  /// Creates a snapshot without checking business invariants.
  ///
  /// Restore rejects an unsupported [schemaVersion], a fingerprint that is
  /// not 64 lowercase hexadecimal characters, and reservation state the
  /// dataset cannot accept. The lists are copied.
  SessionSnapshot({
    required this.schemaVersion,
    required this.datasetFingerprint,
    required List<SnapshotReservation> reservations,
    required List<String> issuedOrderIds,
    required List<String> exportedOrderIds,
  }) : reservations = List.unmodifiable(reservations),
       issuedOrderIds = List.unmodifiable(issuedOrderIds),
       exportedOrderIds = List.unmodifiable(exportedOrderIds);

  /// Schema version accepted by restore and the snapshot codec.
  static const int supportedSchemaVersion = 1;

  static final RegExp _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Whether [value] is 64 lowercase hexadecimal characters.
  ///
  /// Uppercase hex is rejected. This does not compute a hash.
  static bool hasFingerprintFormat(String value) =>
      _fingerprintPattern.hasMatch(value);

  /// Schema version of this snapshot.
  final int schemaVersion;

  /// Lowercase SHA-256 hex of the original dataset bytes, as supplied.
  final String datasetFingerprint;

  /// Reserved units. Each entry is one order line on one stock slot.
  final List<SnapshotReservation> reservations;

  /// Order ids marked issued, with duplicates preserved for validation.
  final List<String> issuedOrderIds;

  /// Order ids marked exported, with duplicates preserved for validation.
  final List<String> exportedOrderIds;

  @override
  bool operator ==(Object other) =>
      other is SessionSnapshot &&
      other.schemaVersion == schemaVersion &&
      other.datasetFingerprint == datasetFingerprint &&
      listEquals(other.reservations, reservations) &&
      listEquals(other.issuedOrderIds, issuedOrderIds) &&
      listEquals(other.exportedOrderIds, exportedOrderIds);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    datasetFingerprint,
    Object.hashAll(reservations),
    Object.hashAll(issuedOrderIds),
    Object.hashAll(exportedOrderIds),
  );

  @override
  String toString() =>
      'SessionSnapshot(v$schemaVersion, ${reservations.length} reservations, '
      '${issuedOrderIds.length} issued, ${exportedOrderIds.length} exported)';
}

/// One reserved quantity of a stock slot for an order line.
///
/// [productId] is the exact decimal literal. It is never parsed as a number.
/// [address] and [serialNumber] keep their exact characters.
@immutable
class SnapshotReservation {
  /// Creates one reservation entry without checking it against a dataset.
  const SnapshotReservation({
    required this.orderId,
    required this.productId,
    required this.address,
    required this.serialNumber,
    required this.quantity,
  });

  /// Dataset `OrderID`.
  final String orderId;

  /// Exact product-id literal.
  final String productId;

  /// Stock address, compared as a case-sensitive string.
  final String address;

  /// Stock serial, compared as a case-sensitive string.
  final String serialNumber;

  /// Reserved units of this slot for this order line.
  final int quantity;

  @override
  bool operator ==(Object other) =>
      other is SnapshotReservation &&
      other.orderId == orderId &&
      other.productId == productId &&
      other.address == address &&
      other.serialNumber == serialNumber &&
      other.quantity == quantity;

  @override
  int get hashCode =>
      Object.hash(orderId, productId, address, serialNumber, quantity);

  @override
  String toString() =>
      'SnapshotReservation($orderId, $productId, $address, '
      '$serialNumber, x$quantity)';
}
