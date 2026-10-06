import 'package:flutter/foundation.dart';

/// The fulfilment workbook generated for one order during this session.
///
/// [filename] is the download/share name. Cell values inside [bytes] keep
/// the original identifiers.
@immutable
class OrderExport {
  const OrderExport({
    required this.orderNumber,
    required this.filename,
    required this.bytes,
  });

  final String orderNumber;
  final String filename;
  final Uint8List bytes;

  @override
  String toString() =>
      'OrderExport($orderNumber, $filename, ${bytes.length} B)';
}
