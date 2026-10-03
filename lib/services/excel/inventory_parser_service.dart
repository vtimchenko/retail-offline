import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../models/inventory_balance.dart';
import 'raw_sheet.dart';
import 'sheet_table.dart';

/// Converts the rows of the inventory sheet into [InventoryBalance]s.
class InventoryParserService {
  const InventoryParserService();

  static const String address = 'Address';
  static const String productId = 'ProductID';
  static const String serialNumber = 'SerialNumber';
  static const String quantity = 'Quantity';

  static const List<String> requiredHeaders = [
    address,
    productId,
    serialNumber,
    quantity,
  ];

  /// Validates strictly: the first invalid row fails the whole import.
  /// Throws [ImportException].
  List<InventoryBalance> parse(RawSheet sheet) {
    final table = SheetTable.from(
      sheet,
      fileLabel: ImportFileLabels.inventory,
      requiredHeaders: requiredHeaders,
    );

    return [for (final row in table.dataRows) _parseRow(table.reader(row))];
  }

  InventoryBalance _parseRow(RowReader r) => InventoryBalance(
    address: r.text(address),
    productId: r.identifier(productId),
    serialNumber: r.identifier(serialNumber),
    quantity: r.quantity(quantity),
  );
}
