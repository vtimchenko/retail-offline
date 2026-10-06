import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/order_export.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';

OrderExport _export(String orderNumber, List<int> bytes) => OrderExport(
  orderNumber: orderNumber,
  filename: '$orderNumber.xlsx',
  bytes: Uint8List.fromList(bytes),
);

void main() {
  test('stores, replaces, invalidates one order, and clears', () {
    final exports = InMemoryOrderExportRepository();
    final first = _export('900000001', const [1, 2]);
    final second = _export('900000002', const [3]);
    final replacement = _export('900000001', const [4, 5, 6]);

    expect(exports.exportFor('900000001'), isNull);

    exports.put(first);
    exports.put(second);
    expect(exports.exportFor('900000001')?.bytes, first.bytes);
    expect(exports.exportFor('900000002')?.filename, '900000002.xlsx');

    exports.put(replacement);
    expect(exports.exportFor('900000001')?.bytes, replacement.bytes);
    expect(exports.exportFor('900000002'), isNotNull);

    exports.invalidate('900000001');
    expect(exports.exportFor('900000001'), isNull);
    expect(exports.exportFor('900000002')?.bytes, second.bytes);

    exports.clear();
    expect(exports.exportFor('900000002'), isNull);
  });
}
