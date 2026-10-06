import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/order_export.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/screens/orders/order_progress.dart';

const _productId = '1290564103789190763';

final _order = Order(
  invoiceDate: DateTime(2026, 10, 3),
  invoiceNumber: 'ТЕСТ000001',
  orderNumber: '900000001',
  customer: 'Клієнт',
  customerPhone: '0501112233',
  items: const [
    OrderItem(
      product: 'Товар',
      productId: _productId,
      quantity: 2,
      priceMinorUnits: 100,
      amountMinorUnits: 200,
    ),
  ],
);

const _inventory = [
  InventoryBalance(
    address: 'A1',
    productId: _productId,
    serialNumber: 'SN001',
    quantity: 2,
  ),
];

void main() {
  late InMemorySerialSelectionRepository selections;
  late InMemoryOrderExportRepository exports;

  setUp(() {
    selections = InMemorySerialSelectionRepository();
    exports = InMemoryOrderExportRepository();
  });

  OrderProgress progress() => OrderProgress.of(_order, selections, exports);

  void addOne() {
    expect(
      selections.addOne(
        orderNumber: _order.orderNumber,
        productId: _productId,
        address: 'A1',
        serialNumber: 'SN001',
        inventory: _inventory,
        requiredQuantity: 2,
      ),
      isTrue,
    );
  }

  test('no selections', () {
    expect(progress(), OrderProgress.none);
  });

  test('partial selection is in progress', () {
    addOne();
    expect(progress(), OrderProgress.inProgress);
  });

  test('a complete order without a workbook is ready', () {
    addOne();
    addOne();
    expect(progress(), OrderProgress.ready);
  });

  test('a stored workbook is file ready', () {
    addOne();
    addOne();
    exports.put(
      OrderExport(
        orderNumber: _order.orderNumber,
        filename: 'file.xlsx',
        bytes: Uint8List.fromList(const [1]),
      ),
    );
    expect(progress(), OrderProgress.fileReady);

    selections.removeOne(
      orderNumber: _order.orderNumber,
      productId: _productId,
      address: 'A1',
      serialNumber: 'SN001',
    );
    expect(progress(), OrderProgress.fileReady);
  });
}
