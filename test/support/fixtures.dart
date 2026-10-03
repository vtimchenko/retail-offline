import 'dart:typed_data';

import 'package:retail_offline/models/imported_file.dart';
import 'package:retail_offline/services/excel/inventory_parser_service.dart';
import 'package:retail_offline/services/excel/orders_parser_service.dart';

import 'xlsx_builder.dart';

/// Synthetic data only: no real customers, phones or products.

/// 19-digit id, larger than 2^53 (loses precision as a double / JS number).
const String bigProductId = '1290564103789190763';
const String bigProductId2 = '1289540227082816241';
const String bigProductId3 = '1292052703978381705';

/// One Excel row of the orders file, keyed by header.
Map<String, Object?> orderRow({
  String invoiceDate = '20261003114618',
  String invoiceNumber = 'ТЕСТ000001',
  Object orderNumber = const XlsxNumber('900000001'),
  String customer = 'Тестовий Клієнт А',
  String customerPhone = '0501112233',
  String product = 'Тестовий товар 1',
  Object productId = bigProductId,
  String quantity = '1',
  String price = '329.00',
  String amount = '329.00',
}) => {
  OrdersParserService.invoiceDate: XlsxNumber(invoiceDate),
  OrdersParserService.invoiceNumber: invoiceNumber,
  OrdersParserService.orderNumber: orderNumber,
  OrdersParserService.customer: customer,
  OrdersParserService.customerPhone: customerPhone,
  OrdersParserService.product: product,
  OrdersParserService.productId: productId,
  OrdersParserService.quantity: XlsxNumber(quantity),
  OrdersParserService.price: price,
  OrdersParserService.amount: amount,
};

/// Builds an orders workbook. [headers] sets the column order (and may omit
/// columns to emulate a missing header).
Uint8List ordersXlsx(
  List<Map<String, Object?>> rows, {
  List<String>? headers,
  String sheetName = 'Аркуш1',
}) {
  final h = headers ?? OrdersParserService.requiredHeaders;
  return buildXlsx([
    h,
    for (final r in rows) [for (final name in h) r[name]],
  ], sheetName: sheetName);
}

Map<String, Object?> inventoryRow({
  String address = '\$\$TEST01',
  Object productId = bigProductId,
  Object serialNumber = 'SN-0001',
  String quantity = '1',
}) => {
  InventoryParserService.address: address,
  InventoryParserService.productId: productId,
  InventoryParserService.serialNumber: serialNumber,
  InventoryParserService.quantity: XlsxNumber(quantity),
};

Uint8List inventoryXlsx(
  List<Map<String, Object?>> rows, {
  List<String>? headers,
  String sheetName = 'Sheet1',
}) {
  final h = headers ?? InventoryParserService.requiredHeaders;
  return buildXlsx([
    h,
    for (final r in rows) [for (final name in h) r[name]],
  ], sheetName: sheetName);
}

ImportedFile localFile(String name, Uint8List bytes) =>
    ImportedFile(name: name, bytes: bytes, source: FileSource.local);

/// Sample orders: A (1 row), B (3 rows, 3 products, non-adjacent in the
/// file, with another order C in between).
List<Map<String, Object?>> sampleOrderRows() => [
  orderRow(
    orderNumber: const XlsxNumber('900000001'),
    invoiceNumber: 'ТЕСТ000001',
    customerPhone: '0501112233',
    productId: bigProductId,
  ),
  orderRow(
    orderNumber: const XlsxNumber('900000002'),
    invoiceNumber: 'ТЕСТ000002',
    customer: 'Тестовий Клієнт Б',
    customerPhone: '0671112233',
    product: 'Товар B1',
    productId: bigProductId2,
    price: '100.50',
    amount: '100.50',
  ),
  orderRow(
    orderNumber: const XlsxNumber('900000003'),
    invoiceNumber: 'ТЕСТ000003',
    customer: 'Тестовий Клієнт В',
    customerPhone: '0931112233',
    product: 'Товар C1',
    productId: bigProductId3,
  ),
  orderRow(
    orderNumber: const XlsxNumber('900000002'),
    invoiceNumber: 'ТЕСТ000002',
    customer: 'Тестовий Клієнт Б',
    customerPhone: '0671112233',
    product: 'Товар B2',
    productId: const XlsxNumber('43848'),
    quantity: '2',
    price: '10',
    amount: '19.99',
  ),
  orderRow(
    orderNumber: const XlsxNumber('900000002'),
    invoiceNumber: 'ТЕСТ000002',
    customer: 'Тестовий Клієнт Б',
    customerPhone: '0671112233',
    product: 'Товар B3',
    productId: '80762',
    quantity: '3',
    price: '1,5',
    amount: '4,50',
  ),
];

List<Map<String, Object?>> sampleInventoryRows() => [
  inventoryRow(address: '\$\$AGVI             ', serialNumber: 'SN-0001'),
  inventoryRow(
    productId: const XlsxNumber('43848'),
    serialNumber: const XlsxNumber('2251313016465'),
  ),
  inventoryRow(serialNumber: '0MSH3HJL900062', quantity: '6'),
  inventoryRow(serialNumber: '00554244106062000627'),
];
