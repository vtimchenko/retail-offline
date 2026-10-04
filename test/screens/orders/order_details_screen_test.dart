import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/screens/orders/order_details_screen.dart';

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderDetailsScreen(store: _store, order: _order),
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
    expect(find.textContaining(_productId), findsNothing);
  });
}
