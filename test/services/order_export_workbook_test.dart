import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/services/excel/excel_import_service.dart';
import 'package:retail_offline/services/excel/order_export_workbook.dart';
import 'package:retail_offline/services/excel/raw_sheet.dart';

const _productId = '1290564103789190763';
const _storeName = 'ТВ Тестовий Магазин 1';
const _idStore = 'retail_test_store';

Order _order({
  String invoiceNumber = 'ТЕСТ/1',
  String orderNumber = '900000002',
  String productId = _productId,
  int quantity = 3,
}) {
  return Order(
    invoiceDate: DateTime(2026, 10, 3),
    invoiceNumber: invoiceNumber,
    orderNumber: orderNumber,
    customer: _storeName,
    customerPhone: '0501112233',
    items: [
      OrderItem(
        product: 'Товар',
        productId: productId,
        quantity: quantity,
        priceMinorUnits: 100,
        amountMinorUnits: 100,
      ),
    ],
  );
}

void _reserve(
  SerialSelectionRepository selections, {
  required String orderNumber,
  required String productId,
  required String address,
  required String serialNumber,
  required int quantity,
  required int stock,
  int? lineQuantity,
}) {
  final inventory = [
    InventoryBalance(
      address: address,
      productId: productId,
      serialNumber: serialNumber,
      quantity: stock,
    ),
  ];
  for (var i = 0; i < quantity; i++) {
    expect(
      selections.addOne(
        orderNumber: orderNumber,
        productId: productId,
        address: address,
        serialNumber: serialNumber,
        inventory: inventory,
        requiredQuantity: lineQuantity ?? quantity,
      ),
      isTrue,
    );
  }
}

RawCell _cell(RawSheet sheet, int rowNumber, int column) {
  final row = sheet.rows.singleWhere((row) => row.number == rowNumber);
  return row.cells[column]!;
}

List<String> _texts(RawSheet sheet, int rowNumber) => [
  for (var column = 0; column < 7; column++)
    _cell(sheet, rowNumber, column).value,
];

void main() {
  test('sanitizes filename characters and keeps letters and spaces', () {
    expect(
      orderExportFileName(
        idStore: 'a/b',
        invoiceNumber: r'c\d',
        orderNumber: 'e:f',
      ),
      'a_b_c_d_e_f.xlsx',
    );
    expect(
      orderExportFileName(
        idStore: 'a*b',
        invoiceNumber: 'c?d',
        orderNumber: 'e"f',
      ),
      'a_b_c_d_e_f.xlsx',
    );
    expect(
      orderExportFileName(
        idStore: 'a<b',
        invoiceNumber: 'c>d',
        orderNumber: 'e|f',
      ),
      'a_b_c_d_e_f.xlsx',
    );
    expect(
      orderExportFileName(
        idStore: 'a\x01b',
        invoiceNumber: 'c\x7Fd',
        orderNumber: 'e\nf',
      ),
      'a_b_c_d_e_f.xlsx',
    );
    expect(
      orderExportFileName(
        idStore: 'retail_a',
        invoiceNumber: 'ТЕСТ 1',
        orderNumber: '900',
      ),
      'retail_a_ТЕСТ 1_900.xlsx',
    );
  });

  test('writes one row per slot and keeps a 19-digit ProductID as text', () {
    final order = _order();
    final selections = InMemorySerialSelectionRepository();
    _reserve(
      selections,
      orderNumber: order.orderNumber,
      productId: _productId,
      address: 'A01',
      serialNumber: 'SN001',
      quantity: 2,
      stock: 2,
      lineQuantity: 3,
    );
    _reserve(
      selections,
      orderNumber: order.orderNumber,
      productId: _productId,
      address: 'A&2',
      serialNumber: 'SN002',
      quantity: 1,
      stock: 1,
      lineQuantity: 3,
    );

    final export = OrderExportWorkbook.build(
      idStore: _idStore,
      order: order,
      selections: selections,
    );

    expect(export.filename, 'retail_test_store_ТЕСТ_1_900000002.xlsx');
    final sheet = const ExcelImportService().readFirstSheet(export.bytes);
    expect(sheet.rows, hasLength(3));
    expect(_texts(sheet, 1), OrderExportWorkbook.columns);

    expect(_texts(sheet, 2), [
      _idStore,
      'ТЕСТ/1',
      '900000002',
      _productId,
      'A01',
      'SN001',
      '2',
    ]);
    expect(_cell(sheet, 2, 3).type, RawCellType.text);
    expect(_cell(sheet, 2, 3).value, _productId);
    expect(_productId.length, 19);
    expect(_cell(sheet, 2, 6).type, RawCellType.number);
    expect(_cell(sheet, 2, 6).value, '2');

    expect(_texts(sheet, 3), [
      _idStore,
      'ТЕСТ/1',
      '900000002',
      _productId,
      'A&2',
      'SN002',
      '1',
    ]);
    expect(_cell(sheet, 3, 6).type, RawCellType.number);
    expect(_cell(sheet, 3, 6).value, '1');

    for (final row in sheet.rows) {
      for (final cell in row.cells.values) {
        expect(cell.value.contains(_storeName), isFalse);
      }
    }
  });

  test('keeps a leading-zero serial number through the XLSX reader', () {
    const serial = '000001234567';
    final order = _order(invoiceNumber: 'INV1', quantity: 1);
    final selections = InMemorySerialSelectionRepository();
    _reserve(
      selections,
      orderNumber: order.orderNumber,
      productId: _productId,
      address: 'A1',
      serialNumber: serial,
      quantity: 1,
      stock: 1,
    );

    final export = OrderExportWorkbook.build(
      idStore: _idStore,
      order: order,
      selections: selections,
    );
    final sheet = const ExcelImportService().readFirstSheet(export.bytes);
    final cell = _cell(sheet, 2, 5);
    expect(cell.type, RawCellType.text);
    expect(cell.value, serial);
  });

  test('refuses an identifier that cannot be stored as XML text', () {
    final order = _order(orderNumber: '9\u0001');
    final selections = InMemorySerialSelectionRepository();
    _reserve(
      selections,
      orderNumber: order.orderNumber,
      productId: _productId,
      address: 'A1',
      serialNumber: 'SN001',
      quantity: 1,
      stock: 1,
    );

    expect(
      () => OrderExportWorkbook.build(
        idStore: _idStore,
        order: order,
        selections: selections,
      ),
      throwsA(isA<OrderExportException>()),
    );
  });
}
