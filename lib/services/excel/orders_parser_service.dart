import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../models/order.dart';
import 'raw_sheet.dart';
import 'sheet_table.dart';

/// Converts the rows of the orders sheet into domain [Order]s.
///
/// One Excel row is one [OrderItem], NOT one order. Rows are grouped by
/// `OrderNumber` across the whole sheet (rows of one order need not be
/// adjacent). The order of first appearance is preserved.
class OrdersParserService {
  const OrdersParserService();

  static const String invoiceDate = 'InvoiceDate';
  static const String invoiceNumber = 'InvoiceNumber';
  static const String orderNumber = 'OrderNumber';
  static const String customer = 'Customer';
  static const String customerPhone = 'CustomerPhone';
  static const String product = 'Product';
  static const String productId = 'ProductID';
  static const String quantity = 'Quantity';
  static const String price = 'Price';
  static const String amount = 'Amount';

  static const List<String> requiredHeaders = [
    invoiceDate,
    invoiceNumber,
    orderNumber,
    customer,
    customerPhone,
    product,
    productId,
    quantity,
    price,
    amount,
  ];

  /// Validates strictly: the first invalid row fails the whole import.
  /// Throws [ImportException].
  List<Order> parse(RawSheet sheet) {
    final table = SheetTable.from(
      sheet,
      fileLabel: ImportFileLabels.orders,
      requiredHeaders: requiredHeaders,
    );

    // Dart's default Map is insertion-ordered → first-appearance order.
    final builders = <String, _OrderBuilder>{};

    for (final row in table.dataRows) {
      final r = table.reader(row);
      final number = r.identifier(orderNumber);
      final header = _OrderHeader(
        row: r.rowNumber,
        invoiceDate: r.dateTime(invoiceDate),
        invoiceNumber: r.identifier(invoiceNumber),
        customer: r.text(customer),
        customerPhone: r.phone(customerPhone),
      );
      final item = OrderItem(
        product: r.text(product),
        productId: r.identifier(productId),
        quantity: r.quantity(quantity, allowZero: false),
        priceMinorUnits: r.money(price),
        amountMinorUnits: r.money(amount),
      );

      final builder = builders[number];
      if (builder == null) {
        builders[number] = _OrderBuilder(number, header)..items.add(item);
      } else {
        builder.checkConsistent(header);
        builder.items.add(item);
      }
    }

    return [for (final b in builders.values) b.build()];
  }
}

/// Order-level values of one Excel row.
class _OrderHeader {
  const _OrderHeader({
    required this.row,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.customer,
    required this.customerPhone,
  });

  final int row;
  final DateTime invoiceDate;
  final String invoiceNumber;
  final String customer;
  final String customerPhone;
}

class _OrderBuilder {
  _OrderBuilder(this.orderNumber, this.header);

  final String orderNumber;
  final _OrderHeader header;
  final List<OrderItem> items = [];

  /// Rows of one order must agree on every order-level value; otherwise the
  /// file is inconsistent and we refuse to merge (or split) silently.
  void checkConsistent(_OrderHeader other) {
    void check(bool same, String field) {
      if (same) return;
      throw ImportException(
        ImportMessages.inconsistentOrder(
          orderNumber: orderNumber,
          field: field,
          firstRow: header.row,
          row: other.row,
        ),
      );
    }

    check(
      other.invoiceDate == header.invoiceDate,
      OrdersParserService.invoiceDate,
    );
    check(
      other.invoiceNumber == header.invoiceNumber,
      OrdersParserService.invoiceNumber,
    );
    check(other.customer == header.customer, OrdersParserService.customer);
    check(
      other.customerPhone == header.customerPhone,
      OrdersParserService.customerPhone,
    );
  }

  Order build() => Order(
    invoiceDate: header.invoiceDate,
    invoiceNumber: header.invoiceNumber,
    orderNumber: orderNumber,
    customer: header.customer,
    customerPhone: header.customerPhone,
    items: items,
  );
}
