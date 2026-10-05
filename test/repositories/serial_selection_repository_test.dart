import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/serial_selection.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';

const _product = '1290564103789190763';
const _otherProduct = '1290564103789190764';
const _serial = '0MSH3HJL900062';

InventoryBalance _balance({
  String productId = _product,
  String address = 'A1',
  String serialNumber = 'SN001',
  int quantity = 1,
}) => InventoryBalance(
  address: address,
  productId: productId,
  serialNumber: serialNumber,
  quantity: quantity,
);

void main() {
  late InMemorySerialSelectionRepository repo;

  setUp(() => repo = InMemorySerialSelectionRepository());

  List<AvailableSerial> available(
    List<InventoryBalance> inventory, {
    String productId = _product,
  }) => repo.availableFor(productId: productId, inventory: inventory);

  bool add({
    String orderNumber = '907907',
    String productId = _product,
    String address = 'A1',
    String serialNumber = 'SN001',
    required List<InventoryBalance> inventory,
    required int requiredQuantity,
  }) => repo.addOne(
    orderNumber: orderNumber,
    productId: productId,
    address: address,
    serialNumber: serialNumber,
    inventory: inventory,
    requiredQuantity: requiredQuantity,
  );

  group('availability', () {
    test('sums duplicate slots and keeps first-seen order', () {
      final rows = available([
        _balance(serialNumber: 'SN', quantity: 0),
        _balance(address: 'B2', serialNumber: 'OTHER', quantity: 1),
        _balance(serialNumber: 'SN', quantity: 2),
        _balance(productId: _otherProduct, serialNumber: 'SN', quantity: 9),
      ]);

      expect(rows, [
        const AvailableSerial(
          address: 'A1',
          serialNumber: 'SN',
          availableQuantity: 2,
        ),
        const AvailableSerial(
          address: 'B2',
          serialNumber: 'OTHER',
          availableQuantity: 1,
        ),
      ]);
    });

    test('a zero-only slot is omitted', () {
      expect(available([_balance(quantity: 0)]), isEmpty);
    });

    test(
      'available quantity subtracts every owner, including the current one',
      () {
        final inventory = [_balance(quantity: 3)];
        expect(add(inventory: inventory, requiredQuantity: 5), isTrue);

        expect(available(inventory).single.availableQuantity, 2);
        expect(repo.selectedFor(orderNumber: '907907', productId: _product), [
          const SelectedSerial(
            address: 'A1',
            serialNumber: 'SN001',
            quantity: 1,
          ),
        ]);
      },
    );

    test('returned lists are unmodifiable', () {
      final inventory = [_balance()];
      add(inventory: inventory, requiredQuantity: 1);
      expect(
        () => available(inventory).add(
          const AvailableSerial(
            address: 'X',
            serialNumber: 'Y',
            availableQuantity: 1,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => repo
            .selectedFor(orderNumber: '907907', productId: _product)
            .clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('add and remove', () {
    test('aggregates repeated adds of one slot', () {
      final inventory = [
        _balance(quantity: 5),
        _balance(address: 'B2', serialNumber: 'SN002', quantity: 5),
      ];
      expect(add(inventory: inventory, requiredQuantity: 5), isTrue);
      expect(add(inventory: inventory, requiredQuantity: 5), isTrue);
      expect(
        add(
          inventory: inventory,
          address: 'B2',
          serialNumber: 'SN002',
          requiredQuantity: 5,
        ),
        isTrue,
      );

      expect(repo.selectedQuantity('907907', _product), 3);
      expect(repo.selectedFor(orderNumber: '907907', productId: _product), [
        const SelectedSerial(address: 'A1', serialNumber: 'SN001', quantity: 2),
        const SelectedSerial(address: 'B2', serialNumber: 'SN002', quantity: 1),
      ]);
    });

    test('remove frees one unit and drops the row at zero', () {
      final inventory = [_balance(quantity: 3)];
      add(inventory: inventory, requiredQuantity: 3);
      add(inventory: inventory, requiredQuantity: 3);

      expect(
        repo.removeOne(
          orderNumber: '907907',
          productId: _product,
          address: 'A1',
          serialNumber: 'SN001',
        ),
        isTrue,
      );
      expect(available(inventory).single.availableQuantity, 2);
      expect(
        repo.selectedFor(orderNumber: '907907', productId: _product).single,
        const SelectedSerial(address: 'A1', serialNumber: 'SN001', quantity: 1),
      );

      expect(
        repo.removeOne(
          orderNumber: '907907',
          productId: _product,
          address: 'A1',
          serialNumber: 'SN001',
        ),
        isTrue,
      );
      expect(available(inventory).single.availableQuantity, 3);
      expect(
        repo.selectedFor(orderNumber: '907907', productId: _product),
        isEmpty,
      );
      expect(repo.selectedQuantity('907907', _product), 0);
    });

    test('remove of an empty slot does nothing', () {
      expect(
        repo.removeOne(
          orderNumber: '907907',
          productId: _product,
          address: 'A1',
          serialNumber: 'SN001',
        ),
        isFalse,
      );
      expect(repo.selectedQuantity('907907', _product), 0);
    });

    test('add does not change the inventory row', () {
      final inventory = [_balance(quantity: 3, serialNumber: _serial)];
      final before = inventory.single;
      add(inventory: inventory, serialNumber: _serial, requiredQuantity: 1);
      expect(inventory.single, before);
      expect(inventory.single.serialNumber, _serial);
    });
  });

  group('caps', () {
    test('stops at the slot stock', () {
      final inventory = [_balance(quantity: 2)];
      expect(add(inventory: inventory, requiredQuantity: 5), isTrue);
      expect(add(inventory: inventory, requiredQuantity: 5), isTrue);
      expect(add(inventory: inventory, requiredQuantity: 5), isFalse);
      expect(repo.selectedQuantity('907907', _product), 2);
      expect(available(inventory), isEmpty);
    });

    test('stops at the order line quantity across slots', () {
      final inventory = [
        _balance(quantity: 5),
        _balance(address: 'B2', serialNumber: 'SN002', quantity: 5),
      ];
      expect(add(inventory: inventory, requiredQuantity: 2), isTrue);
      expect(add(inventory: inventory, requiredQuantity: 2), isTrue);
      expect(
        add(
          inventory: inventory,
          address: 'B2',
          serialNumber: 'SN002',
          requiredQuantity: 2,
        ),
        isFalse,
      );
      expect(repo.selectedQuantity('907907', _product), 2);
      expect(available(inventory).map((row) => row.availableQuantity), [3, 5]);
    });
  });

  group('identity', () {
    test(
      'another order sees the remainder and the owner keeps its selection',
      () {
        final inventory = [_balance(quantity: 3)];
        add(orderNumber: '907907', inventory: inventory, requiredQuantity: 3);
        add(orderNumber: '907907', inventory: inventory, requiredQuantity: 3);

        expect(available(inventory).single.availableQuantity, 1);
        expect(
          add(orderNumber: '907908', inventory: inventory, requiredQuantity: 3),
          isTrue,
        );
        expect(available(inventory), isEmpty);
        expect(repo.selectedQuantity('907907', _product), 2);
        expect(repo.selectedQuantity('907908', _product), 1);

        repo.removeOne(
          orderNumber: '907907',
          productId: _product,
          address: 'A1',
          serialNumber: 'SN001',
        );
        expect(available(inventory).single.availableQuantity, 1);
        expect(repo.selectedQuantity('907907', _product), 1);
        expect(repo.selectedQuantity('907908', _product), 1);
      },
    );

    test('the same serial at another address is a separate pool', () {
      final inventory = [
        _balance(address: 'A1', quantity: 2),
        _balance(address: 'B2', quantity: 4),
      ];
      add(inventory: inventory, requiredQuantity: 2);
      add(inventory: inventory, requiredQuantity: 2);

      expect(available(inventory), [
        const AvailableSerial(
          address: 'B2',
          serialNumber: 'SN001',
          availableQuantity: 4,
        ),
      ]);
      expect(
        repo.selectedFor(orderNumber: '907907', productId: _product).single,
        const SelectedSerial(address: 'A1', serialNumber: 'SN001', quantity: 2),
      );
    });

    test('the same serial on another product is a separate pool', () {
      final inventory = [
        _balance(productId: _product, quantity: 5, serialNumber: _serial),
        _balance(productId: _otherProduct, quantity: 5, serialNumber: _serial),
      ];
      for (var i = 0; i < 5; i++) {
        expect(
          add(
            productId: _product,
            serialNumber: _serial,
            inventory: inventory,
            requiredQuantity: 5,
          ),
          isTrue,
        );
      }

      expect(available(inventory, productId: _product), isEmpty);
      expect(
        available(inventory, productId: _otherProduct).single,
        AvailableSerial(
          address: 'A1',
          serialNumber: _serial,
          availableQuantity: 5,
        ),
      );
      expect(
        repo
            .selectedFor(orderNumber: '907907', productId: _product)
            .single
            .serialNumber,
        _serial,
      );
      expect(repo.selectedQuantity('907907', _otherProduct), 0);
    });

    test('keeps a 19-digit product id and a leading zero as text', () {
      final inventory = [_balance(serialNumber: _serial)];
      add(inventory: inventory, serialNumber: _serial, requiredQuantity: 1);
      expect(repo.selectedQuantity('907907', _product), 1);
      expect(repo.selectedQuantity('907907', _otherProduct), 0);
      expect(
        repo
            .selectedFor(orderNumber: '907907', productId: _product)
            .single
            .serialNumber,
        '0MSH3HJL900062',
      );
    });
  });

  test('clear drops every reservation', () {
    final inventory = [_balance(quantity: 2)];
    add(inventory: inventory, requiredQuantity: 2);
    repo.clear();
    expect(repo.selectedQuantity('907907', _product), 0);
    expect(available(inventory).single.availableQuantity, 2);
    expect(
      repo.selectedFor(orderNumber: '907907', productId: _product),
      isEmpty,
    );
  });
}
