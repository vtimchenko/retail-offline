import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/theme/app_colors.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/order_export.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';
import 'package:retail_offline/screens/orders/order_details_screen.dart';
import 'package:retail_offline/screens/orders/orders_screen.dart';

const _store = Store(nameStore: 'ТВ Тестовий Магазин 1', idStore: '42');
const _formattedPhone = '+38 (067) 123-45-67';
const _productId = '1290564103789190763';

Order _order({
  required String number,
  required String phone,
  required String customer,
  required String invoice,
  required String product,
}) {
  return Order(
    invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
    invoiceNumber: invoice,
    orderNumber: number,
    customer: customer,
    customerPhone: phone,
    items: [
      OrderItem(
        product: product,
        productId: _productId,
        quantity: 2,
        priceMinorUnits: 1000,
        amountMinorUnits: 1999,
      ),
    ],
  );
}

final _orders = [
  _order(
    number: '900000001',
    phone: _formattedPhone,
    customer: 'Клієнт А',
    invoice: 'ТЕСТ000001',
    product: 'Секретний товар Альфа',
  ),
  _order(
    number: '900000002',
    phone: '0501112233',
    customer: 'Клієнт Б',
    invoice: 'ТЕСТ000002',
    product: 'Секретний товар Бета',
  ),
];

SessionDataRepository _repository(List<Order> orders) {
  final repository = InMemorySessionDataRepository();
  repository.commit(orders: orders, inventory: const []);
  return repository;
}

Future<void> _pumpOrders(
  WidgetTester tester,
  SessionDataRepository repository, {
  SerialSelectionRepository? selections,
  OrderExportRepository? exports,
  Size size = const Size(1000, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrdersScreen(
        store: _store,
        repository: repository,
        selections: selections ?? InMemorySerialSelectionRepository(),
        exports: exports ?? InMemoryOrderExportRepository(),
      ),
    ),
  );
}

void main() {
  testWidgets('shows order-level fields and hides item data', (tester) async {
    await _pumpOrders(tester, _repository(_orders));

    expect(find.text('ТВ Тестовий Магазин 1'), findsOneWidget);
    expect(find.text('Замовлення'), findsOneWidget);
    expect(find.text('03.10.2026 11:46'), findsNWidgets(2));
    expect(find.text('ТЕСТ000001'), findsOneWidget);
    expect(find.text('ТЕСТ000002'), findsOneWidget);
    expect(find.text('900000001'), findsOneWidget);
    expect(find.text('900000002'), findsOneWidget);
    expect(find.text('Клієнт А'), findsOneWidget);
    expect(find.text('Клієнт Б'), findsOneWidget);
    expect(find.text(_formattedPhone), findsOneWidget);
    expect(find.text('0501112233'), findsOneWidget);
    expect(find.text('Секретний товар Альфа'), findsNothing);
    expect(find.text('Секретний товар Бета'), findsNothing);
    expect(find.textContaining(_productId), findsNothing);
    expect(find.text('2'), findsNothing);
    expect(find.text('10,00'), findsNothing);
    expect(find.text('19,99'), findsNothing);
  });

  testWidgets('filters by order number and phone while typing', (tester) async {
    await _pumpOrders(tester, _repository(_orders));

    await tester.enterText(
      find.byKey(const Key('order-number-search')),
      '000002',
    );
    await tester.pump();

    expect(find.text('900000002'), findsOneWidget);
    expect(find.text('900000001'), findsNothing);
    expect(find.text('Клієнт Б'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('order-number-search')), '');
    await tester.enterText(
      find.byKey(const Key('customer-phone-search')),
      '067',
    );
    await tester.pump();

    expect(find.text('900000001'), findsOneWidget);
    expect(find.text(_formattedPhone), findsOneWidget);
    expect(find.text('380671234567'), findsNothing);
    expect(find.text('900000002'), findsNothing);

    await tester.enterText(find.byKey(const Key('order-number-search')), '900');
    await tester.enterText(
      find.byKey(const Key('customer-phone-search')),
      '050',
    );
    await tester.pump();

    expect(find.text('900000002'), findsOneWidget);
    expect(find.text('900000001'), findsNothing);
  });

  testWidgets('shows a no-match state without dropping the source phone', (
    tester,
  ) async {
    await _pumpOrders(tester, _repository(_orders));

    await tester.enterText(
      find.byKey(const Key('order-number-search')),
      'немає',
    );
    await tester.pump();

    expect(find.byKey(const Key('orders-no-match')), findsOneWidget);
    expect(find.text('900000001'), findsNothing);
    expect(find.text('900000002'), findsNothing);
    expect(_orders[0].customerPhone, _formattedPhone);
  });

  testWidgets('shows an empty state when the repository has no orders', (
    tester,
  ) async {
    await _pumpOrders(tester, _repository(const []));

    expect(find.byKey(const Key('orders-empty')), findsOneWidget);
    expect(find.byKey(const Key('orders-no-match')), findsNothing);
  });

  testWidgets('tapping an order opens its details', (tester) async {
    await _pumpOrders(tester, _repository(_orders));

    await tester.tap(find.byKey(const ValueKey('900000001')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.text('Секретний товар Альфа'), findsOneWidget);
    expect(find.text('900000001'), findsOneWidget);
    expect(find.text(_formattedPhone), findsOneWidget);
    expect(find.textContaining(_productId), findsNothing);
  });

  testWidgets('wide layout puts column headers on one row', (tester) async {
    await _pumpOrders(tester, _repository(_orders));

    final header = find.byKey(const Key('orders-table-header'));
    expect(header, findsOneWidget);
    final date = find.descendant(of: header, matching: find.text('Дата'));
    final invoice = find.descendant(
      of: header,
      matching: find.text('Накладна'),
    );
    final phone = find.descendant(of: header, matching: find.text('Телефон'));
    expect(tester.getTopLeft(date).dy, tester.getTopLeft(invoice).dy);
    expect(tester.getTopLeft(date).dy, tester.getTopLeft(phone).dy);
    expect(
      tester.getTopLeft(find.text('900000001')).dy,
      tester.getTopLeft(find.text('ТЕСТ000001')).dy,
    );
  });

  testWidgets('narrow layout stacks order cards without overflow', (
    tester,
  ) async {
    await _pumpOrders(
      tester,
      _repository(_orders),
      size: const Size(360, 1400),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('orders-table-header')), findsNothing);
    final first = tester.getTopLeft(find.text('900000001')).dy;
    final second = tester.getTopLeft(find.text('900000002')).dy;
    expect(second, greaterThan(first + 40));
    expect(find.text(_formattedPhone), findsOneWidget);
  });

  testWidgets('wide rows show derived status colors and labels', (
    tester,
  ) async {
    final fixture = _statusFixture();
    await _pumpOrders(
      tester,
      fixture.repository,
      selections: fixture.selections,
      exports: fixture.exports,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Статус'), findsOneWidget);
    expect(find.text('Без вибору'), findsOneWidget);
    expect(find.text('В процесі'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Файл сформовано'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.byIcon(Icons.timelapse), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(_rowColor(tester, 'none'), AppColors.background);
    expect(
      _rowColor(tester, 'progress'),
      AppColors.orderStatusInProgressBackground,
    );
    expect(_rowColor(tester, 'ready'), AppColors.orderStatusReadyBackground);
    expect(_rowColor(tester, 'file'), AppColors.orderStatusFileReadyBackground);
  });

  testWidgets('narrow cards show the same derived statuses', (tester) async {
    final fixture = _statusFixture();
    await _pumpOrders(
      tester,
      fixture.repository,
      selections: fixture.selections,
      exports: fixture.exports,
      size: const Size(360, 1400),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('orders-table-header')), findsNothing);
    expect(find.text('Статус'), findsNothing);
    expect(find.text('Без вибору'), findsOneWidget);
    expect(find.text('В процесі'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Файл сформовано'), findsOneWidget);
    expect(_cardColor(tester, 'none'), isNull);
    expect(
      _cardColor(tester, 'progress'),
      AppColors.orderStatusInProgressBackground,
    );
    expect(_cardColor(tester, 'ready'), AppColors.orderStatusReadyBackground);
    expect(
      _cardColor(tester, 'file'),
      AppColors.orderStatusFileReadyBackground,
    );
  });

  testWidgets('refreshes status after returning from order details', (
    tester,
  ) async {
    final selections = InMemorySerialSelectionRepository();
    const inventory = [
      InventoryBalance(
        address: 'A',
        productId: _productId,
        serialNumber: 'S1',
        quantity: 2,
      ),
    ];
    for (var i = 0; i < 2; i++) {
      selections.addOne(
        orderNumber: '900000001',
        productId: _productId,
        address: 'A',
        serialNumber: 'S1',
        inventory: inventory,
        requiredQuantity: 2,
      );
    }
    final exports = InMemoryOrderExportRepository();
    await _pumpOrders(
      tester,
      _repository(_orders),
      selections: selections,
      exports: exports,
    );

    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Без вибору'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('900000001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('complete-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fulfilment-ok')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Файл сформовано'), findsOneWidget);
    expect(find.text('Готово'), findsNothing);
    expect(find.text('Без вибору'), findsOneWidget);
    expect(
      _rowColor(tester, '900000001'),
      AppColors.orderStatusFileReadyBackground,
    );
  });
}

typedef _StatusFixture = ({
  SessionDataRepository repository,
  SerialSelectionRepository selections,
  OrderExportRepository exports,
});

_StatusFixture _statusFixture() {
  Order order(String number, String productId) => Order(
    invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
    invoiceNumber: number,
    orderNumber: number,
    customer: 'Клієнт $number',
    customerPhone: '0501112233',
    items: [
      OrderItem(
        product: 'Товар $number',
        productId: productId,
        quantity: 2,
        priceMinorUnits: 100,
        amountMinorUnits: 200,
      ),
    ],
  );

  const noneId = '100';
  const progressId = '200';
  const readyId = '300';
  const fileId = '400';
  final orders = [
    order('none', noneId),
    order('progress', progressId),
    order('ready', readyId),
    order('file', fileId),
  ];
  final selections = InMemorySerialSelectionRepository();
  void reserve(String number, String productId, int count) {
    final inventory = [
      InventoryBalance(
        address: 'A',
        productId: productId,
        serialNumber: 'S',
        quantity: 2,
      ),
    ];
    for (var i = 0; i < count; i++) {
      selections.addOne(
        orderNumber: number,
        productId: productId,
        address: 'A',
        serialNumber: 'S',
        inventory: inventory,
        requiredQuantity: 2,
      );
    }
  }

  reserve('progress', progressId, 1);
  reserve('ready', readyId, 2);
  reserve('file', fileId, 2);
  final exports = InMemoryOrderExportRepository()
    ..put(
      OrderExport(
        orderNumber: 'file',
        filename: 'file.xlsx',
        bytes: Uint8List.fromList(const [1]),
      ),
    );
  return (
    repository: _repository(orders),
    selections: selections,
    exports: exports,
  );
}

Color? _rowColor(WidgetTester tester, String orderNumber) {
  return tester
      .widget<Material>(
        find.descendant(
          of: find.byKey(ValueKey(orderNumber)),
          matching: find.byType(Material),
        ),
      )
      .color;
}

Color? _cardColor(WidgetTester tester, String orderNumber) {
  return tester
      .widget<Card>(
        find.descendant(
          of: find.byKey(ValueKey(orderNumber)),
          matching: find.byType(Card),
        ),
      )
      .color;
}
