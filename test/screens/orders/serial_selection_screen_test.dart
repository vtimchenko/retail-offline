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
import 'package:retail_offline/screens/orders/serial_selection_screen.dart';

const _store = Store(nameStore: 'ТВ Тестовий Магазин 1', idStore: '42');
const _productId = '1290564103789190763';
const _otherProductId = '1289540227082816241';

const _a1 = ValueKey(('available', r'$$A1', 'SN001'));
const _b2 = ValueKey(('available', 'B2', 'SN001'));
const _selectedA1 = ValueKey(('selected', r'$$A1', 'SN001'));

final _inventory = [
  const InventoryBalance(
    address: r'$$A1',
    productId: _productId,
    serialNumber: 'SN001',
    quantity: 3,
  ),
  const InventoryBalance(
    address: 'B2',
    productId: _productId,
    serialNumber: 'SN001',
    quantity: 1,
  ),
  const InventoryBalance(
    address: 'C9',
    productId: _otherProductId,
    serialNumber: 'SN777',
    quantity: 9,
  ),
];

OrderItem _item({String product = 'Тестовий товар', int quantity = 2}) =>
    OrderItem(
      product: product,
      productId: _productId,
      quantity: quantity,
      priceMinorUnits: 1000,
      amountMinorUnits: 2000,
    );

Order _order({String number = '907907', int quantity = 2}) => Order(
  invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
  invoiceNumber: 'ТЕСТ000001',
  orderNumber: number,
  customer: 'Тестовий Клієнт',
  customerPhone: '0501112233',
  items: [_item(quantity: quantity)],
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSelection(
  WidgetTester tester, {
  Size size = const Size(1000, 1400),
  SerialSelectionRepository? selections,
  OrderItem? item,
  String orderNumber = '907907',
  List<InventoryBalance>? inventory,
  TargetPlatform? platform,
}) async {
  await _setSize(tester, size);
  final theme = platform == null
      ? AppTheme.light
      : AppTheme.light.copyWith(platform: platform);
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(platform),
      theme: theme,
      home: SerialSelectionScreen(
        store: _store,
        orderNumber: orderNumber,
        item: item ?? _item(),
        inventory: inventory ?? _inventory,
        selections: selections ?? InMemorySerialSelectionRepository(),
      ),
    ),
  );
}

Future<void> _tapAdd(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('add-serial')));
  await tester.pump();
}

Future<void> _tapRemove(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('remove-serial')));
  await tester.pump();
}

void main() {
  testWidgets('shows this product stock, address and required quantity', (
    tester,
  ) async {
    await _pumpSelection(tester);

    expect(find.text('ТВ Тестовий Магазин 1'), findsOneWidget);
    expect(find.text('Тестовий товар'), findsOneWidget);
    expect(find.text('Потрібна кількість: 2'), findsOneWidget);
    expect(find.text('Обрано 0 з 2'), findsOneWidget);
    expect(find.text(r'$$A1'), findsOneWidget);
    expect(find.text('B2'), findsOneWidget);
    expect(find.text('SN001'), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('SN777'), findsNothing);
    expect(find.text('C9'), findsNothing);
    expect(find.text('9'), findsNothing);
    expect(find.textContaining(_productId), findsNothing);
    expect(find.byKey(const Key('serial-selected-empty')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-serial')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('remove-serial')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('moves one unit at a time and stops at the required quantity', (
    tester,
  ) async {
    final selections = InMemorySerialSelectionRepository();
    await _pumpSelection(tester, selections: selections);

    await tester.tap(find.byKey(_a1));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-serial')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('remove-serial')))
          .onPressed,
      isNull,
    );

    await _tapAdd(tester);
    expect(find.text('Обрано 1 з 2'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.byKey(_selectedA1), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_selectedA1),
        matching: find.text(r'$$A1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_selectedA1),
        matching: find.text('SN001'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(_selectedA1), matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.byKey(_b2), findsOneWidget);

    await tester.tap(find.byKey(_selectedA1));
    await tester.pump();
    await _tapRemove(tester);
    expect(find.byKey(_selectedA1), findsNothing);
    expect(find.byKey(const Key('serial-selected-empty')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await _tapAdd(tester);
    await _tapAdd(tester);
    expect(find.text('Обрано 2 з 2'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-serial')))
          .onPressed,
      isNull,
    );
    expect(
      find.descendant(of: find.byKey(_selectedA1), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('serial-search')), 'немає');
    await tester.pump();
    expect(find.byKey(const Key('serial-available-no-match')), findsOneWidget);
    expect(find.byKey(_selectedA1), findsOneWidget);
    expect(_inventory.first.serialNumber, 'SN001');
  });

  testWidgets('search filters serials only and keeps the stored text', (
    tester,
  ) async {
    await _pumpSelection(tester);

    await tester.enterText(find.byKey(const Key('serial-search')), 'sn001');
    await tester.pump();
    expect(find.byKey(const Key('serial-available-no-match')), findsOneWidget);
    expect(find.text('SN001'), findsNothing);

    await tester.enterText(find.byKey(const Key('serial-search')), '  SN001 ');
    await tester.pump();
    expect(find.text('SN001'), findsNWidgets(2));
    expect(find.text('B2'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('serial-search')), '');
    await tester.pump();
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-serial')))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byKey(const Key('serial-search')), 'B2');
    await tester.pump();
    expect(find.byKey(const Key('serial-available-no-match')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-serial')))
          .onPressed,
      isNull,
    );
    expect(_inventory.first.serialNumber, 'SN001');
    expect(_inventory.last.serialNumber, 'SN777');
  });

  testWidgets('a second order sees the reduced remainder', (tester) async {
    final selections = InMemorySerialSelectionRepository();
    await _pumpSelection(tester, selections: selections, orderNumber: '907907');
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await _tapAdd(tester);
    await _tapAdd(tester);

    await _pumpSelection(
      tester,
      selections: selections,
      orderNumber: '907908',
      item: _item(quantity: 1),
    );
    expect(find.text('Обрано 0 з 1'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('serial-selected-empty')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_b2), matching: find.text('1')),
      findsOneWidget,
    );

    await _pumpSelection(tester, selections: selections, orderNumber: '907907');
    expect(find.text('Обрано 2 з 2'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_selectedA1), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets('double-click adds on desktop and only highlights on iOS', (
    tester,
  ) async {
    final touch = InMemorySerialSelectionRepository();
    await _pumpSelection(
      tester,
      selections: touch,
      platform: TargetPlatform.iOS,
    );
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    expect(find.byKey(const Key('serial-selected-empty')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('3')),
      findsOneWidget,
    );

    final desktop = InMemorySerialSelectionRepository();
    await _pumpSelection(
      tester,
      selections: desktop,
      platform: TargetPlatform.macOS,
    );
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    expect(find.text('Обрано 1 з 2'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_a1), matching: find.text('2')),
      findsOneWidget,
    );
    expect(desktop.selectedQuantity('907907', _productId), 1);
  });

  testWidgets('wide layout shows both table headers on one row', (
    tester,
  ) async {
    final selections = InMemorySerialSelectionRepository();
    await _pumpSelection(tester, selections: selections);
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await _tapAdd(tester);

    for (final key in const [Key('available-header'), Key('selected-header')]) {
      final header = find.byKey(key);
      expect(header, findsOneWidget);
      final address = find.descendant(
        of: header,
        matching: find.text('Адреса'),
      );
      final serial = find.descendant(
        of: header,
        matching: find.text('Серійний номер'),
      );
      expect(tester.getTopLeft(address).dy, tester.getTopLeft(serial).dy);
    }
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('narrow layout uses cards without overflow', (tester) async {
    await _pumpSelection(tester, size: const Size(360, 1400));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('available-header')), findsNothing);
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('SN001'), findsNWidgets(2));
    expect(find.textContaining(_productId), findsNothing);

    await _pumpSelection(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await _tapAdd(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Обрано 1 з 2'), findsOneWidget);
  });

  testWidgets('empty stock explains that nothing is available', (tester) async {
    await _pumpSelection(tester, inventory: const []);
    expect(find.byKey(const Key('serial-available-empty')), findsOneWidget);
    expect(
      find.text('Немає доступних залишків для цього товару'),
      findsOneWidget,
    );
  });

  testWidgets('back navigation keeps the selection and completion validates', (
    tester,
  ) async {
    final selections = InMemorySerialSelectionRepository();
    final repository = InMemorySessionDataRepository()
      ..commit(
        orders: [
          _order(),
          _order(number: '907908', quantity: 1),
        ],
        inventory: _inventory,
      );

    await _setSize(tester, const Size(1000, 1400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OrderDetailsScreen(
          store: _store,
          order: _order(),
          repository: repository,
          selections: selections,
          exports: InMemoryOrderExportRepository(),
        ),
      ),
    );

    expect(find.text('Обрано 0 з 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-item-row-0')));
    await tester.pumpAndSettle();
    expect(find.byType(SerialSelectionScreen), findsOneWidget);

    await tester.tap(find.byKey(_a1));
    await tester.pump();
    await _tapAdd(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.text('Обрано 1 з 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fulfilment-incomplete')), findsOneWidget);
    expect(find.text('Тестовий товар — потрібно 2, обрано 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fulfilment-incomplete')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('order-item-row-0')));
    await tester.pumpAndSettle();
    expect(find.text('Обрано 1 з 2'), findsOneWidget);
    expect(find.byKey(_selectedA1), findsOneWidget);
  });
}
