import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/errors/dataset_parse_exception.dart';
import '../domain/fulfilment/session_snapshot.dart';
import '../models/retail_dataset.dart';
import '../services/json/precision_json_decoder.dart';

/// Canonical non-negative JSON integer token.
///
/// `0` and `11` match. `01`, `-1`, and `1e2` do not. The text is never parsed
/// as a floating-point number.
final _canonicalInteger = RegExp(r'^(0|[1-9][0-9]*)$');

const _rootFields = <String>[
  'schemaVersion',
  'datasetFingerprint',
  'reservations',
  'issuedOrderIds',
  'exportedOrderIds',
];

const _reservationFields = <String>[
  'orderId',
  'productId',
  'address',
  'serialNumber',
  'quantity',
];

/// Encodes and decodes a [SessionSnapshot] as JSON text.
///
/// Numbers are read with [PrecisionJsonDecoder]. Product ids, order ids,
/// addresses, and serials are accepted only as JSON strings, so a large
/// product id cannot pass through a JavaScript number.
class SessionSnapshotCodec {
  /// Creates a codec with no stored state.
  const SessionSnapshotCodec();

  /// Writes [snapshot] with a fixed key order and stable whitespace.
  ///
  /// The same snapshot always produces the same text. Identifier fields are
  /// JSON strings. [SessionSnapshot.schemaVersion] and
  /// [SnapshotReservation.quantity] are JSON numbers written from their
  /// decimal digits.
  String encode(SessionSnapshot snapshot) {
    final buffer = StringBuffer()..writeln('{');
    _rootField(buffer, 'schemaVersion', '${snapshot.schemaVersion}');
    _rootField(
      buffer,
      'datasetFingerprint',
      jsonEncode(snapshot.datasetFingerprint),
    );
    buffer.write('  "reservations": ');
    _writeReservations(buffer, snapshot.reservations);
    buffer.writeln(',');
    buffer.write('  "issuedOrderIds": ');
    _writeStrings(buffer, snapshot.issuedOrderIds);
    buffer.writeln(',');
    buffer.write('  "exportedOrderIds": ');
    _writeStrings(buffer, snapshot.exportedOrderIds);
    buffer.write('\n}');
    return buffer.toString();
  }

  /// Reads [source] and returns the snapshot or the first problem found.
  ///
  /// Unknown object fields, missing required fields, non-canonical numbers,
  /// and a schema version other than
  /// [SessionSnapshot.supportedSchemaVersion] are rejected. `exciseStamps`
  /// may be absent on a reservation; that absence is an empty list. The
  /// snapshot lists keep the order of the JSON arrays.
  SnapshotDecodeResult decode(String source) {
    final JsonValue root;
    try {
      root = const PrecisionJsonDecoder().decode(source);
    } on JsonSyntaxException {
      return const SnapshotDecodeRejected(SnapshotDecodeReason.malformedJson);
    }
    if (root is! JsonObjectValue) {
      return const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'snapshot',
      );
    }
    final shape = _objectShape(root, _rootFields);
    if (shape != null) return shape;

    final version = _readSchemaVersion(root.fields['schemaVersion']!);
    if (version.rejected != null) return version.rejected!;
    final fingerprint = _readFingerprint(root.fields['datasetFingerprint']!);
    if (fingerprint.rejected != null) return fingerprint.rejected!;
    final reservations = _readReservations(root.fields['reservations']!);
    if (reservations.rejected != null) return reservations.rejected!;
    final issued = _readStrings(
      root.fields['issuedOrderIds']!,
      'issuedOrderIds',
    );
    if (issued.rejected != null) return issued.rejected!;
    final exported = _readStrings(
      root.fields['exportedOrderIds']!,
      'exportedOrderIds',
    );
    if (exported.rejected != null) return exported.rejected!;

    return SnapshotDecoded(
      SessionSnapshot(
        schemaVersion: version.value!,
        datasetFingerprint: fingerprint.value!,
        reservations: reservations.value!,
        issuedOrderIds: issued.value!,
        exportedOrderIds: exported.value!,
      ),
    );
  }
}

/// Outcome of [SessionSnapshotCodec.decode].
@immutable
sealed class SnapshotDecodeResult {
  const SnapshotDecodeResult();
}

/// [snapshot] was read from well-formed, supported JSON.
final class SnapshotDecoded extends SnapshotDecodeResult {
  /// Creates a successful decode result.
  const SnapshotDecoded(this.snapshot);

  /// The snapshot described by the JSON text.
  final SessionSnapshot snapshot;
}

/// The JSON text cannot become a snapshot.
final class SnapshotDecodeRejected extends SnapshotDecodeResult {
  /// Creates a rejection. [detail] names the field or token when one is known.
  const SnapshotDecodeRejected(this.reason, {this.detail});

  /// Why this text was rejected.
  final SnapshotDecodeReason reason;

  /// Field or token involved in [reason], when one is known.
  final String? detail;

  @override
  String toString() => 'SnapshotDecodeRejected($reason, $detail)';
}

/// Why [SessionSnapshotCodec.decode] rejected its input.
enum SnapshotDecodeReason {
  /// The text is not JSON this decoder accepts.
  malformedJson,

  /// A value has the wrong JSON type, or the root is not an object.
  malformedStructure,

  /// An object contains a field this schema does not define.
  unknownField,

  /// A required field is absent.
  missingField,

  /// A number token is not a canonical integer in the accepted range.
  invalidNumber,

  /// A fingerprint is not 64 lowercase hexadecimal characters.
  invalidFingerprint,

  /// The schema version is a canonical integer other than version 1.
  unsupportedVersion,
}

void _rootField(StringBuffer buffer, String key, String jsonValue) {
  buffer
    ..write('  "')
    ..write(key)
    ..write('": ')
    ..write(jsonValue)
    ..write(',\n');
}

void _writeReservations(StringBuffer buffer, List<SnapshotReservation> values) {
  if (values.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var i = 0; i < values.length; i++) {
    final entry = values[i];
    buffer.write('    {\n');
    _entryField(buffer, 'orderId', jsonEncode(entry.orderId));
    _entryField(buffer, 'productId', jsonEncode(entry.productId));
    _entryField(buffer, 'address', jsonEncode(entry.address));
    _entryField(buffer, 'serialNumber', jsonEncode(entry.serialNumber));
    if (entry.exciseStamps.isEmpty) {
      buffer
        ..write('      "quantity": ')
        ..write(entry.quantity)
        ..write('\n    }');
    } else {
      buffer
        ..write('      "quantity": ')
        ..write(entry.quantity)
        ..write(',\n      "exciseStamps": ');
      _writeExciseStamps(buffer, entry.exciseStamps);
      buffer.write('\n    }');
    }
    if (i + 1 != values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('  ]');
}

void _writeExciseStamps(StringBuffer buffer, List<String> stamps) {
  buffer.write('[\n');
  for (var i = 0; i < stamps.length; i++) {
    buffer
      ..write('        ')
      ..write(jsonEncode(stamps[i]));
    if (i + 1 != stamps.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('      ]');
}

void _entryField(StringBuffer buffer, String key, String jsonValue) {
  buffer
    ..write('      "')
    ..write(key)
    ..write('": ')
    ..write(jsonValue)
    ..write(',\n');
}

void _writeStrings(StringBuffer buffer, List<String> values) {
  if (values.isEmpty) {
    buffer.write('[]');
    return;
  }
  buffer.write('[\n');
  for (var i = 0; i < values.length; i++) {
    buffer
      ..write('    ')
      ..write(jsonEncode(values[i]));
    if (i + 1 != values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('  ]');
}

SnapshotDecodeRejected? _objectShape(
  JsonObjectValue object,
  List<String> fields, {
  Set<String> optional = const {},
}) {
  final allowed = fields.toSet()..addAll(optional);
  for (final key in object.fields.keys) {
    if (!allowed.contains(key)) {
      return SnapshotDecodeRejected(
        SnapshotDecodeReason.unknownField,
        detail: key,
      );
    }
  }
  for (final key in fields) {
    if (!object.fields.containsKey(key)) {
      return SnapshotDecodeRejected(
        SnapshotDecodeReason.missingField,
        detail: key,
      );
    }
  }
  return null;
}

typedef _Read<T> = ({T? value, SnapshotDecodeRejected? rejected});

_Read<int> _readSchemaVersion(JsonValue value) {
  if (value is! JsonNumberValue) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'schemaVersion',
      ),
    );
  }
  if (!_canonicalInteger.hasMatch(value.literal)) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.invalidNumber,
        detail: 'schemaVersion',
      ),
    );
  }
  if (value.literal != '${SessionSnapshot.supportedSchemaVersion}') {
    return (
      value: null,
      rejected: SnapshotDecodeRejected(
        SnapshotDecodeReason.unsupportedVersion,
        detail: value.literal,
      ),
    );
  }
  return (value: SessionSnapshot.supportedSchemaVersion, rejected: null);
}

_Read<String> _readFingerprint(JsonValue value) {
  if (value is! JsonStringValue) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'datasetFingerprint',
      ),
    );
  }
  if (!SessionSnapshot.hasFingerprintFormat(value.text)) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.invalidFingerprint,
        detail: 'datasetFingerprint',
      ),
    );
  }
  return (value: value.text, rejected: null);
}

_Read<List<SnapshotReservation>> _readReservations(JsonValue value) {
  if (value is! JsonArrayValue) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'reservations',
      ),
    );
  }
  final entries = <SnapshotReservation>[];
  for (final item in value.items) {
    if (item is! JsonObjectValue) {
      return (
        value: null,
        rejected: const SnapshotDecodeRejected(
          SnapshotDecodeReason.malformedStructure,
          detail: 'reservations',
        ),
      );
    }
    final shape = _objectShape(
      item,
      _reservationFields,
      optional: const {'exciseStamps'},
    );
    if (shape != null) return (value: null, rejected: shape);
    final orderId = _readRequiredString(item, 'orderId');
    if (orderId.rejected != null) {
      return (value: null, rejected: orderId.rejected);
    }
    final productId = _readRequiredString(item, 'productId');
    if (productId.rejected != null) {
      return (value: null, rejected: productId.rejected);
    }
    final address = _readRequiredString(item, 'address');
    if (address.rejected != null) {
      return (value: null, rejected: address.rejected);
    }
    final serialNumber = _readRequiredString(item, 'serialNumber');
    if (serialNumber.rejected != null) {
      return (value: null, rejected: serialNumber.rejected);
    }
    final quantity = _readQuantity(item.fields['quantity']!);
    if (quantity.rejected != null) {
      return (value: null, rejected: quantity.rejected);
    }
    final stamps = _readExciseStamps(item.fields['exciseStamps']);
    if (stamps.rejected != null) {
      return (value: null, rejected: stamps.rejected);
    }
    entries.add(
      SnapshotReservation(
        orderId: orderId.value!,
        productId: productId.value!,
        address: address.value!,
        serialNumber: serialNumber.value!,
        quantity: quantity.value!,
        exciseStamps: List.unmodifiable(stamps.value!),
      ),
    );
  }
  return (value: entries, rejected: null);
}

_Read<String> _readRequiredString(JsonObjectValue object, String field) {
  final value = object.fields[field];
  if (value is! JsonStringValue) {
    return (
      value: null,
      rejected: SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: field,
      ),
    );
  }
  return (value: value.text, rejected: null);
}

_Read<List<String>> _readExciseStamps(JsonValue? value) {
  if (value == null) return (value: const [], rejected: null);
  if (value is! JsonArrayValue) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'exciseStamps',
      ),
    );
  }
  final stamps = <String>[];
  for (final item in value.items) {
    if (item is! JsonStringValue) {
      return (
        value: null,
        rejected: const SnapshotDecodeRejected(
          SnapshotDecodeReason.malformedStructure,
          detail: 'exciseStamps',
        ),
      );
    }
    stamps.add(item.text);
  }
  return (value: stamps, rejected: null);
}

_Read<int> _readQuantity(JsonValue value) {
  if (value is! JsonNumberValue) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: 'quantity',
      ),
    );
  }
  final literal = value.literal;
  if (!_canonicalInteger.hasMatch(literal) || literal.length > 9) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.invalidNumber,
        detail: 'quantity',
      ),
    );
  }
  final quantity = int.parse(literal);
  if (quantity < 1 || quantity > DatasetLimits.maxQuantity) {
    return (
      value: null,
      rejected: const SnapshotDecodeRejected(
        SnapshotDecodeReason.invalidNumber,
        detail: 'quantity',
      ),
    );
  }
  return (value: quantity, rejected: null);
}

_Read<List<String>> _readStrings(JsonValue value, String field) {
  if (value is! JsonArrayValue) {
    return (
      value: null,
      rejected: SnapshotDecodeRejected(
        SnapshotDecodeReason.malformedStructure,
        detail: field,
      ),
    );
  }
  final items = <String>[];
  for (final item in value.items) {
    if (item is! JsonStringValue) {
      return (
        value: null,
        rejected: SnapshotDecodeRejected(
          SnapshotDecodeReason.malformedStructure,
          detail: field,
        ),
      );
    }
    items.add(item.text);
  }
  return (value: items, rejected: null);
}
