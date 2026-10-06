import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';
import 'package:retail_offline/screens/orders/order_details_screen.dart';
import 'package:retail_offline/services/file/xlsx_share.dart';

const _store = Store(nameStore: 'ТВ Тестовий Магазин 1', idStore: '42');
const _productId = '1290564103789190763';
const _phone = '+38 (067) 123-45-67';

final _order = Order(
  invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
  invoiceNumber: 'ТЕСТ000002',
  orderNumber: '900000002',
  customer: 'Тестовий Клієнт Б',
  customerPhone: _phone,
  items: const [
    OrderItem(
      product: 'Товар 1',
      productId: _productId,
      quantity: 2,
      priceMinorUnits: 1000,
      amountMinorUnits: 1999,
    ),
    OrderItem(
      product: 'Товар 2',
      productId: '80762',
      quantity: 4,
      priceMinorUnits: 150,
      amountMinorUnits: 450,
    ),
  ],
);

Future<void> _pumpDetails(
  WidgetTester tester, {
  Size size = const Size(1000, 1400),
  SerialSelectionRepository? selections,
  OrderExportRepository? exports,
  ShareXlsx? shareXlsx,
  Order? order,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final shown = order ?? _order;
  final repository = InMemorySessionDataRepository()
    ..commit(orders: [shown], inventory: const []);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderDetailsScreen(
        store: _store,
        order: shown,
        repository: repository,
        selections: selections ?? InMemorySerialSelectionRepository(),
        exports: exports ?? InMemoryOrderExportRepository(),
        shareXlsx: shareXlsx,
      ),
    ),
  );
}

void main() {
  testWidgets('shows the order, every item, and stored money', (tester) async {
    await _pumpDetails(tester);

    expect(find.text('ТВ Тестовий Магазин 1'), findsOneWidget);
    expect(find.text('03.10.2026 11:46'), findsOneWidget);
    expect(find.text('ТЕСТ000002'), findsOneWidget);
    expect(find.text('900000002'), findsOneWidget);
    expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
    expect(find.text(_phone), findsOneWidget);
    expect(find.text('Товар 1'), findsOneWidget);
    expect(find.text('Товар 2'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('10,00'), findsOneWidget);
    expect(find.text('19,99'), findsOneWidget);
    expect(find.text('1,50'), findsOneWidget);
    expect(find.text('4,50'), findsOneWidget);
    expect(find.text('Обрано 0 з 2'), findsOneWidget);
    expect(find.text('Обрано 0 з 4'), findsOneWidget);
    expect(find.text('Завершити обслуговування'), findsOneWidget);
    expect(find.text('20,00'), findsNothing);
    expect(find.text('6,00'), findsNothing);
    expect(find.textContaining(_productId), findsNothing);
    expect(find.text('80762'), findsNothing);
  });

  testWidgets('wide layout shows an item header row', (tester) async {
    await _pumpDetails(tester);

    final header = find.byKey(const Key('order-items-header'));
    expect(header, findsOneWidget);
    expect(find.byKey(const ValueKey('order-item-card-0')), findsNothing);
    expect(find.byKey(const ValueKey('order-item-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-item-row-1')), findsOneWidget);
    final product = find.descendant(of: header, matching: find.text('Товар'));
    final amount = find.descendant(of: header, matching: find.text('Сума'));
    expect(tester.getTopLeft(product).dy, tester.getTopLeft(amount).dy);
  });

  testWidgets('narrow layout uses item cards without overflow', (tester) async {
    await _pumpDetails(tester, size: const Size(360, 1400));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('order-items-header')), findsNothing);
    expect(find.byKey(const ValueKey('order-item-row-0')), findsNothing);
    expect(find.byKey(const ValueKey('order-item-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-item-card-1')), findsOneWidget);
    final first = tester.getTopLeft(find.text('Товар 1')).dy;
    final second = tester.getTopLeft(find.text('Товар 2')).dy;
    expect(second, greaterThan(first));
    expect(find.text('10,00'), findsOneWidget);
    expect(find.text('19,99'), findsOneWidget);
    expect(find.text('Обрано 0 з 2'), findsOneWidget);
    expect(find.textContaining(_productId), findsNothing);
  });

  testWidgets('completion lists every unfinished product', (tester) async {
    await _pumpDetails(tester, size: const Size(320, 700));

    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('fulfilment-incomplete')), findsOneWidget);
    expect(find.text('Товар 1 — потрібно 2, обрано 0'), findsOneWidget);
    expect(find.text('Товар 2 — потрібно 4, обрано 0'), findsOneWidget);
    expect(find.text('Файл Excel успішно сформовано'), findsNothing);

    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fulfilment-incomplete')), findsNothing);
  });

  testWidgets('completion confirms when every line is reserved', (
    tester,
  ) async {
    const inventory = [
      InventoryBalance(
        address: 'A',
        productId: _productId,
        serialNumber: 'S1',
        quantity: 2,
      ),
      InventoryBalance(
        address: 'A',
        productId: '80762',
        serialNumber: 'S2',
        quantity: 4,
      ),
    ];
    final selections = InMemorySerialSelectionRepository();
    for (var i = 0; i < 2; i++) {
      selections.addOne(
        orderNumber: _order.orderNumber,
        productId: _productId,
        address: 'A',
        serialNumber: 'S1',
        inventory: inventory,
        requiredQuantity: 2,
      );
    }
    for (var i = 0; i < 4; i++) {
      selections.addOne(
        orderNumber: _order.orderNumber,
        productId: '80762',
        address: 'A',
        serialNumber: 'S2',
        inventory: inventory,
        requiredQuantity: 4,
      );
    }

    final exports = InMemoryOrderExportRepository();
    String? sharedName;
    Uint8List? sharedBytes;
    await _pumpDetails(
      tester,
      selections: selections,
      exports: exports,
      shareXlsx: ({required filename, required bytes}) async {
        sharedName = filename;
        sharedBytes = bytes;
        return XlsxShareResult.shared;
      },
    );

    expect(find.text('Обрано 2 з 2'), findsOneWidget);
    expect(find.text('Обрано 4 з 4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    expect(find.text('Файл Excel успішно сформовано'), findsOneWidget);
    expect(find.text('Поширити файл'), findsOneWidget);
    expect(find.byKey(const Key('fulfilment-incomplete')), findsNothing);
    expect(exports.exportFor(_order.orderNumber)?.filename, sharedFileName);
    expect(exports.exportFor(_order.orderNumber)!.bytes, isNotEmpty);

    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-file')));
    await tester.pump();
    expect(sharedName, sharedFileName);
    expect(sharedBytes, exports.exportFor(_order.orderNumber)!.bytes);
  });

  testWidgets('keeps Поширити файл when the same order is opened again', (
    tester,
  ) async {
    final selections = _completeSelections();
    final exports = InMemoryOrderExportRepository();
    await _pumpDetails(tester, selections: selections, exports: exports);
    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();

    await _pumpDetails(tester, selections: selections, exports: exports);
    expect(find.text('Поширити файл'), findsOneWidget);
    expect(find.text('Завершити обслуговування'), findsNothing);
  });

  testWidgets('a later serial change brings back completion', (tester) async {
    final selections = _completeSelections();
    final exports = InMemoryOrderExportRepository();
    selections.setOrderChangedListener(exports.invalidate);
    await _pumpDetails(tester, selections: selections, exports: exports);

    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Поширити файл'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('order-item-row-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('selected', 'A', 'S1'))));
    await tester.pump();
    await tester.tap(find.byKey(const Key('remove-serial')));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Завершити обслуговування'), findsOneWidget);
    expect(find.text('Поширити файл'), findsNothing);
    expect(exports.exportFor(_order.orderNumber), isNull);
  });

  testWidgets('a failed export keeps the completion button', (tester) async {
    final order = Order(
      invoiceDate: _order.invoiceDate,
      invoiceNumber: _order.invoiceNumber,
      orderNumber: '9\u0001',
      customer: _order.customer,
      customerPhone: _order.customerPhone,
      items: _order.items,
    );
    final selections = InMemorySerialSelectionRepository();
    const inventory = [
      InventoryBalance(
        address: 'A',
        productId: _productId,
        serialNumber: 'S1',
        quantity: 2,
      ),
      InventoryBalance(
        address: 'A',
        productId: '80762',
        serialNumber: 'S2',
        quantity: 4,
      ),
    ];
    for (var i = 0; i < 2; i++) {
      selections.addOne(
        orderNumber: order.orderNumber,
        productId: _productId,
        address: 'A',
        serialNumber: 'S1',
        inventory: inventory,
        requiredQuantity: 2,
      );
    }
    for (var i = 0; i < 4; i++) {
      selections.addOne(
        orderNumber: order.orderNumber,
        productId: '80762',
        address: 'A',
        serialNumber: 'S2',
        inventory: inventory,
        requiredQuantity: 4,
      );
    }
    final exports = InMemoryOrderExportRepository();
    await _pumpDetails(
      tester,
      selections: selections,
      exports: exports,
      order: order,
    );

    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    expect(find.text('Не вдалося сформувати файл Excel'), findsOneWidget);
    expect(exports.exportFor(order.orderNumber), isNull);

    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Завершити обслуговування'), findsOneWidget);
    expect(find.text('Поширити файл'), findsNothing);
  });
}

const sharedFileName = '42_ТЕСТ000002_900000002.xlsx';

InMemorySerialSelectionRepository _completeSelections() {
  const inventory = [
    InventoryBalance(
      address: 'A',
      productId: _productId,
      serialNumber: 'S1',
      quantity: 2,
    ),
    InventoryBalance(
      address: 'A',
      productId: '80762',
      serialNumber: 'S2',
      quantity: 4,
    ),
  ];
  final selections = InMemorySerialSelectionRepository();
  for (var i = 0; i < 2; i++) {
    selections.addOne(
      orderNumber: _order.orderNumber,
      productId: _productId,
      address: 'A',
      serialNumber: 'S1',
      inventory: inventory,
      requiredQuantity: 2,
    );
  }
  for (var i = 0; i < 4; i++) {
    selections.addOne(
      orderNumber: _order.orderNumber,
      productId: '80762',
      address: 'A',
      serialNumber: 'S2',
      inventory: inventory,
      requiredQuantity: 4,
    );
  }
  return selections;
}
