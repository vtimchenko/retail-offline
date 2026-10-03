import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';

Order _order(String number, String phone, int items) => Order(
  invoiceDate: DateTime(2026, 10, 3),
  invoiceNumber: 'INV-$number',
  orderNumber: number,
  customer: 'Клієнт $number',
  customerPhone: phone,
  items: [
    for (var i = 0; i < items; i++)
      OrderItem(
        product: 'Товар $i',
        productId: '${1000 + i}',
        quantity: 1,
        priceMinorUnits: 100,
        amountMinorUnits: 100,
      ),
  ],
);

InventoryBalance _balance(
  String product,
  String serial, [
  String address = 'A',
]) => InventoryBalance(
  address: address,
  productId: product,
  serialNumber: serial,
  quantity: 1,
);

void main() {
  test('starts empty', () {
    final repo = InMemorySessionDataRepository();
    expect(repo.hasData, isFalse);
    expect(repo.orderCount, 0);
    expect(repo.orderItemCount, 0);
    expect(repo.inventoryCount, 0);
    expect(repo.orderByNumber('1'), isNull);
    expect(repo.ordersByPhone('0'), isEmpty);
  });

  test('commit stores both datasets and exposes separate counts', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: [_order('1', '0501', 1), _order('2', '0502', 3)],
      inventory: [
        _balance('p1', 's1'),
        _balance('p1', 's2'),
        _balance('p2', 's3'),
      ],
    );

    expect(repo.hasData, isTrue);
    expect(repo.orderCount, 2); // Orders
    expect(repo.orderItemCount, 4); // OrderItems
    expect(repo.inventoryCount, 3);
  });

  test('order indexes: OrderNumber → Order, CustomerPhone → List<Order>', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: [
        _order('1', '0501112233', 1),
        _order('2', '0501112233', 2),
        _order('3', '0670000000', 1),
      ],
      inventory: const [],
    );

    expect(repo.orderByNumber('2')!.items, hasLength(2));
    expect(repo.orderByNumber('999'), isNull);
    expect(repo.ordersByPhone('0501112233').map((o) => o.orderNumber), [
      '1',
      '2',
    ]);
    expect(repo.ordersByPhone('0670000000'), hasLength(1));
    // Phone is looked up as text, leading zero included.
    expect(repo.ordersByPhone('501112233'), isEmpty);
  });

  test('ProductID index returns every balance of the product', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: const [],
      inventory: [
        _balance('1290564103789190763', 's1', 'A1'),
        _balance('1290564103789190763', 's2', 'A2'),
        _balance('43848', 's3'),
      ],
    );

    expect(
      repo
          .inventoryByProductId('1290564103789190763')
          .map((b) => b.serialNumber),
      ['s1', 's2'],
    );
    expect(repo.inventoryByProductId('43848'), hasLength(1));
    expect(repo.inventoryByProductId('0'), isEmpty);
  });

  test('SerialNumber index is NOT assumed unique', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: const [],
      inventory: [
        _balance('p1', 'DUP', 'A1'),
        _balance('p2', 'DUP', 'A2'),
        _balance('p3', 'UNIQUE'),
      ],
    );

    expect(repo.inventoryBySerialNumber('DUP').map((b) => b.address), [
      'A1',
      'A2',
    ]);
    expect(repo.inventoryBySerialNumber('UNIQUE'), hasLength(1));
    expect(repo.inventoryBySerialNumber('none'), isEmpty);
  });

  test('a second commit replaces both datasets and all indexes', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: [_order('1', '0501', 1)],
      inventory: [_balance('p1', 's1')],
    );
    repo.commit(
      orders: [_order('9', '0509', 2)],
      inventory: [_balance('p9', 's9')],
    );

    expect(repo.orderByNumber('1'), isNull);
    expect(repo.orderByNumber('9'), isNotNull);
    expect(repo.inventoryBySerialNumber('s1'), isEmpty);
    expect(repo.inventoryBySerialNumber('s9'), hasLength(1));
    expect(repo.orderCount, 1);
    expect(repo.orderItemCount, 2);
  });

  test('a failing commit leaves the previous data untouched (atomic)', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: [_order('1', '0501', 1)],
      inventory: [_balance('p1', 's1')],
    );

    expect(
      () => repo.commit(
        orders: [
          _order('5', '0505', 1),
          _order('5', '0506', 1),
        ], // duplicate key
        inventory: [_balance('new', 'new')],
      ),
      throwsArgumentError,
    );

    expect(repo.orderCount, 1);
    expect(repo.orderByNumber('1'), isNotNull);
    expect(repo.orderByNumber('5'), isNull);
    expect(repo.inventoryBySerialNumber('s1'), hasLength(1));
    expect(repo.inventoryBySerialNumber('new'), isEmpty);
  });

  test('exposed lists are unmodifiable', () {
    final repo = InMemorySessionDataRepository();
    repo.commit(
      orders: [_order('1', '0501', 1)],
      inventory: [_balance('p', 's')],
    );
    expect(() => repo.orders.add(_order('2', '0', 1)), throwsUnsupportedError);
    expect(() => repo.orders.first.items.clear(), throwsUnsupportedError);
    expect(() => repo.inventory.clear(), throwsUnsupportedError);
  });
}
