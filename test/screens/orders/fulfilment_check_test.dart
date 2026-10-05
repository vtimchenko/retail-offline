import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/screens/orders/fulfilment_check.dart';

const _productA = '1290564103789190763';
const _productB = '80762';

Order _order(List<OrderItem> items) => Order(
  invoiceDate: DateTime(2026, 10, 3),
  invoiceNumber: 'INV',
  orderNumber: '907907',
  customer: 'Клієнт',
  customerPhone: '0501112233',
  items: items,
);

OrderItem _item(String product, String productId, int quantity) => OrderItem(
  product: product,
  productId: productId,
  quantity: quantity,
  priceMinorUnits: 100,
  amountMinorUnits: 100,
);

void main() {
  late InMemorySerialSelectionRepository selections;
  final inventory = [
    const InventoryBalance(
      address: 'A1',
      productId: _productA,
      serialNumber: 'SN001',
      quantity: 5,
    ),
    const InventoryBalance(
      address: 'B2',
      productId: _productA,
      serialNumber: 'SN002',
      quantity: 5,
    ),
    const InventoryBalance(
      address: 'A1',
      productId: _productB,
      serialNumber: 'SN003',
      quantity: 5,
    ),
  ];

  setUp(() => selections = InMemorySerialSelectionRepository());

  void reserve(String productId, String serial, int count, int required) {
    for (var i = 0; i < count; i++) {
      final added = selections.addOne(
        orderNumber: '907907',
        productId: productId,
        address: serial == 'SN002' ? 'B2' : 'A1',
        serialNumber: serial,
        inventory: inventory,
        requiredQuantity: required,
      );
      expect(added, isTrue, reason: '$productId $serial #$i');
    }
  }

  test('a full match has no gaps', () {
    reserve(_productA, 'SN001', 1, 2);
    reserve(_productA, 'SN002', 1, 2);
    reserve(_productB, 'SN003', 3, 3);

    final result = FulfilmentCheck.check(
      _order([_item('Товар А', _productA, 2), _item('Товар Б', _productB, 3)]),
      selections,
    );

    expect(result.isComplete, isTrue);
    expect(result.gaps, isEmpty);
    expect(selections.selectedQuantity('907907', _productA), 2);
  });

  test('reports each short line with required and selected quantities', () {
    reserve(_productA, 'SN001', 1, 2);

    final result = FulfilmentCheck.check(
      _order([_item('Товар А', _productA, 2), _item('Товар Б', _productB, 3)]),
      selections,
    );

    expect(result.isComplete, isFalse);
    expect(result.gaps, [
      const FulfilmentGap(
        product: 'Товар А',
        requiredQuantity: 2,
        selectedQuantity: 1,
      ),
      const FulfilmentGap(
        product: 'Товар Б',
        requiredQuantity: 3,
        selectedQuantity: 0,
      ),
    ]);
  });

  test('reports a line whose reserved sum is above its quantity', () {
    reserve(_productA, 'SN001', 3, 5);

    final result = FulfilmentCheck.check(
      _order([_item('Товар А', _productA, 2)]),
      selections,
    );

    expect(
      result.gaps.single,
      const FulfilmentGap(
        product: 'Товар А',
        requiredQuantity: 2,
        selectedQuantity: 3,
      ),
    );
  });
}
