import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/errors/dataset_parse_exception.dart';
import '../domain/fulfilment/session_snapshot.dart';
import '../models/retail_dataset.dart';
import '../services/json/cumulative_json_export.dart';
import '../services/json/precision_json_decoder.dart';
import 'dataset_fingerprint.dart';

/// Checks a stored cumulative export against the dataset and snapshot.
///
/// The digest is the SHA-256 of the exact file bytes. Parsing uses
/// [PrecisionJsonDecoder], so order numbers and product ids stay text.
/// A failure means the records are inconsistent. Nothing is rewritten.
abstract final class ExportConsistency {
  static const _rootKeys = ['storeName', 'dbName', 'dateCreate', 'orders'];
  static const _orderKeys = [
    'OrderID',
    'InvoiceNumber',
    'OrderNumber',
    'Goods',
  ];
  static const _goodKeys = ['ProductID', 'Quantity', 'Address', 'SerialNumber'];

  static final RegExp _canonicalInteger = RegExp(r'^(?:0|[1-9][0-9]*)$');
  static final RegExp _quantity = RegExp(r'^[1-9][0-9]{0,8}$');
  static final RegExp _stamp = RegExp(
    r'^[0-9]{4}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])'
    r'(?:[01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]$',
  );

  /// Whether [document] and [digest] agree with [snapshot] and [dataset].
  ///
  /// Both are absent only when [snapshot] exports nothing. A present
  /// document must hash to [digest], use the Phase 3 filename and
  /// `dateCreate`, and list the same exported order ids.
  static bool matches({
    required RetailDataset dataset,
    required String fingerprint,
    required SessionSnapshot snapshot,
    required ExportDocument? document,
    required String? digest,
  }) {
    if (snapshot.datasetFingerprint != fingerprint) return false;
    final exported = snapshot.exportedOrderIds;
    if (document == null || digest == null) {
      return document == null && digest == null && exported.isEmpty;
    }
    if (exported.isEmpty) return false;
    if (!DatasetFingerprint.matches(document.bytes, digest)) return false;
    if (!_stamp.hasMatch(document.dateCreate)) return false;
    if (document.filename != _filename(dataset.dbName, document.dateCreate)) {
      return false;
    }
    return _documentAgrees(dataset, document, exported);
  }

  static String _filename(String dbName, String dateCreate) =>
      'export_${dbName}_$dateCreate.json';

  static bool _documentAgrees(
    RetailDataset dataset,
    ExportDocument document,
    List<String> exported,
  ) {
    final String source;
    try {
      source = utf8.decode(document.bytes);
    } on FormatException {
      return false;
    }

    final JsonValue value;
    try {
      value = const PrecisionJsonDecoder().decode(source);
    } on JsonSyntaxException {
      return false;
    }
    if (value is! JsonObjectValue || !_sameKeys(value, _rootKeys)) {
      return false;
    }

    final storeName = value.fields['storeName'];
    final dbName = value.fields['dbName'];
    final dateCreate = value.fields['dateCreate'];
    final orders = value.fields['orders'];
    if (storeName is! JsonStringValue ||
        dbName is! JsonStringValue ||
        dateCreate is! JsonStringValue ||
        orders is! JsonArrayValue) {
      return false;
    }
    if (storeName.text != dataset.storeName || dbName.text != dataset.dbName) {
      return false;
    }
    if (dateCreate.text != document.dateCreate) return false;
    if (orders.items.isEmpty || orders.items.length != exported.length) {
      return false;
    }

    for (var i = 0; i < orders.items.length; i++) {
      final order = orders.items[i];
      if (order is! JsonObjectValue || !_orderAgrees(order, exported[i])) {
        return false;
      }
    }
    return true;
  }

  static bool _orderAgrees(JsonObjectValue order, String exportedId) {
    if (!_sameKeys(order, _orderKeys)) return false;
    final orderId = order.fields['OrderID'];
    final invoiceNumber = order.fields['InvoiceNumber'];
    final orderNumber = order.fields['OrderNumber'];
    final goods = order.fields['Goods'];
    if (orderId is! JsonStringValue ||
        invoiceNumber is! JsonStringValue ||
        orderNumber is! JsonNumberValue ||
        goods is! JsonArrayValue) {
      return false;
    }
    if (orderId.text.isEmpty || orderId.text != exportedId) return false;
    if (!_canonicalInteger.hasMatch(orderNumber.literal)) return false;
    if (goods.items.isEmpty) return false;
    for (final item in goods.items) {
      if (item is! JsonObjectValue || !_goodAgrees(item)) return false;
    }
    return true;
  }

  static bool _goodAgrees(JsonObjectValue good) {
    if (!_sameKeys(good, _goodKeys)) return false;
    final productId = good.fields['ProductID'];
    final quantity = good.fields['Quantity'];
    final address = good.fields['Address'];
    final serialNumber = good.fields['SerialNumber'];
    return productId is JsonNumberValue &&
        _canonicalInteger.hasMatch(productId.literal) &&
        quantity is JsonNumberValue &&
        _quantity.hasMatch(quantity.literal) &&
        address is JsonStringValue &&
        serialNumber is JsonStringValue;
  }

  static bool _sameKeys(JsonObjectValue object, List<String> keys) {
    return listEquals(object.fields.keys.toList(), keys);
  }
}
