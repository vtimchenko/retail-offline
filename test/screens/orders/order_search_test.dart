import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/screens/orders/order_search.dart';

Order _order(String number, String phone) => Order(
  invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
  invoiceNumber: 'INV-$number',
  orderNumber: number,
  customer: 'Клієнт $number',
  customerPhone: phone,
  items: const [
    OrderItem(
      product: 'Товар',
      productId: '1290564103789190763',
      quantity: 1,
      priceMinorUnits: 100,
      amountMinorUnits: 100,
    ),
  ],
);

void main() {
  const formattedPhone = '+38 (067) 123-45-67';
  final orders = [
    _order('900000001', '0501112233'),
    _order('900000002', formattedPhone),
    _order('800000003', '0931112233'),
  ];

  List<String> numbers({
    String orderNumberQuery = '',
    String phoneQuery = '',
  }) => OrderSearch.filter(
    orders,
    orderNumberQuery: orderNumberQuery,
    phoneQuery: phoneQuery,
  ).map((order) => order.orderNumber).toList();

  test('normalizePhone strips formatting and keeps digits', () {
    expect(OrderSearch.normalizePhone(formattedPhone), '380671234567');
    expect(OrderSearch.normalizePhone('0501112233'), '0501112233');
  });

  test('empty filters return every order in the original order', () {
    expect(numbers(), ['900000001', '900000002', '800000003']);
    expect(numbers(orderNumberQuery: '   ', phoneQuery: ' +()- '), [
      '900000001',
      '900000002',
      '800000003',
    ]);
  });

  test('order number matches a partial substring', () {
    expect(numbers(orderNumberQuery: '900'), ['900000001', '900000002']);
    expect(numbers(orderNumberQuery: '000002'), ['900000002']);
  });

  test('phone matches a partial substring', () {
    expect(numbers(phoneQuery: '093'), ['800000003']);
  });

  test('phone formatting is ignored for comparison only', () {
    expect(numbers(phoneQuery: '380671234567'), ['900000002']);
    expect(numbers(phoneQuery: '067'), ['900000002']);
    expect(
      OrderSearch.filter(
        orders,
        orderNumberQuery: '',
        phoneQuery: '067',
      ).single.customerPhone,
      formattedPhone,
    );
  });

  test('both filters use AND', () {
    expect(numbers(orderNumberQuery: '900', phoneQuery: '050'), ['900000001']);
    expect(numbers(orderNumberQuery: '900', phoneQuery: '093'), isEmpty);
  });

  test('no matching orders returns an empty list', () {
    expect(numbers(orderNumberQuery: 'ZZZ'), isEmpty);
    expect(numbers(phoneQuery: '000'), isEmpty);
  });

  test('filtering does not mutate stored numbers or phones', () {
    final originalNumbers = orders.map((order) => order.orderNumber).toList();
    final originalPhones = orders.map((order) => order.customerPhone).toList();

    OrderSearch.filter(
      orders,
      orderNumberQuery: '900',
      phoneQuery: formattedPhone,
    );

    expect(orders.map((order) => order.orderNumber), originalNumbers);
    expect(orders.map((order) => order.customerPhone), originalPhones);
    expect(orders[1].customerPhone, formattedPhone);
  });
}
