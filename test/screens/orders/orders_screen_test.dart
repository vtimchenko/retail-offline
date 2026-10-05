import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/store.dart';
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
        selections: InMemorySerialSelectionRepository(),
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
}
