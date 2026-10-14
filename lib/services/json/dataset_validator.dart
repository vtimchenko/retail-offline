import '../../core/constants/dataset_messages.dart';
import '../../core/errors/dataset_parse_exception.dart';
import '../../models/exact_integer.dart';
import '../../models/retail_dataset.dart';
import 'precision_json_decoder.dart';

final _integerLiteral = RegExp(r'^(0|[1-9]\d*)$');
final _moneyLiteral = RegExp(r'^(0|[1-9]\d*)(?:\.(\d+))?$');
final _quantityLiteral = RegExp(r'^(0|[1-9]\d*)$');
final _dateLiteral = RegExp(
  r'^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$',
);
final _dbNameLiteral = RegExp(r'^[A-Za-z0-9_-]+$');

/// Checks a decoded JSON tree against the retail dataset rules.
///
/// The first invalid required field throws [DatasetValidationException].
/// Unknown object fields are ignored. Inventory is not matched to orders.
/// Two stock rows with the same product, address and serial number reject
/// the whole dataset.
class DatasetValidator {
  const DatasetValidator();

  static const _storeName = 'storeName';
  static const _dbName = 'dbName';
  static const _dateCreate = 'dateCreate';
  static const _stocks = 'stocks';
  static const _orders = 'orders';
  static const _address = 'Address';
  static const _productId = 'ProductID';
  static const _serialNumber = 'SerialNumber';
  static const _quantity = 'Quantity';
  static const _orderId = 'OrderID';
  static const _invoiceDate = 'InvoiceDate';
  static const _invoiceNumber = 'InvoiceNumber';
  static const _orderNumber = 'OrderNumber';
  static const _customer = 'Customer';
  static const _customerPhone = 'CustomerPhone';
  static const _goods = 'Goods';
  static const _product = 'Product';
  static const _price = 'Price';
  static const _amount = 'Amount';
  static const _isServiceGood = 'isServiceGood';
  static const _isParcel = 'isParcel';
  static const _parcelTtn = 'ParcelTTN';
  static const _meestTtn = 'MeestTTN';

  RetailDataset validate(JsonValue root) {
    if (root is! JsonObjectValue) {
      throw DatasetValidationException(DatasetMessages.notAnObject());
    }
    final where = DatasetMessages.inDataset;
    return RetailDataset(
      storeName: _requiredText(root, _storeName, where),
      dbName: _dbNameOf(root, where),
      dateCreate: _requiredDate(root, _dateCreate, where),
      stocks: _stocksOf(root),
      orders: _ordersOf(root),
    );
  }

  String _dbNameOf(JsonObjectValue object, String where) {
    final name = _requiredText(object, _dbName, where);
    if (!_dbNameLiteral.hasMatch(name)) {
      throw DatasetValidationException(DatasetMessages.invalidDbName(where));
    }
    return name;
  }

  List<DatasetStock> _stocksOf(JsonObjectValue root) {
    final array = _requiredArray(root, _stocks, DatasetMessages.inDataset);
    final seen = <_StockIdentity, int>{};
    final stocks = <DatasetStock>[];
    for (var i = 0; i < array.items.length; i++) {
      final index = i + 1;
      final stock = _stock(array.items[i], index);
      final identity = _StockIdentity(
        productId: stock.productId,
        address: stock.address,
        serialNumber: stock.serialNumber,
      );
      final firstIndex = seen[identity];
      if (firstIndex != null) {
        throw DatasetValidationException(
          DatasetMessages.duplicateStock(
            productId: stock.productId.literal,
            address: stock.address,
            serialNumber: stock.serialNumber,
            firstIndex: firstIndex,
            duplicateIndex: index,
          ),
        );
      }
      seen[identity] = index;
      stocks.add(stock);
    }
    return stocks;
  }

  DatasetStock _stock(JsonValue value, int index) {
    final where = DatasetMessages.stockAt(index);
    final object = _asRecord(value, where);
    final address = _requiredText(object, _address, where);
    final productId = _requiredInteger(object, _productId, where);
    final serialNumber = _requiredText(object, _serialNumber, where);
    final quantity = _requiredQuantity(object, _quantity, where);
    return DatasetStock(
      address: address,
      productId: productId,
      serialNumber: serialNumber,
      quantity: quantity,
    );
  }

  List<DatasetOrder> _ordersOf(JsonObjectValue root) {
    final array = _requiredArray(root, _orders, DatasetMessages.inDataset);
    final seenIds = <String>{};
    return [
      for (var i = 0; i < array.items.length; i++)
        _order(array.items[i], i + 1, seenIds),
    ];
  }

  DatasetOrder _order(JsonValue value, int index, Set<String> seenIds) {
    final whereIndex = DatasetMessages.orderAt(index);
    final object = _asRecord(value, whereIndex);
    final orderId = _requiredText(object, _orderId, whereIndex);
    if (!seenIds.add(orderId)) {
      throw DatasetValidationException(
        DatasetMessages.duplicateOrderId(orderId),
      );
    }
    final where = DatasetMessages.orderId(orderId);
    final invoiceDate = _requiredDate(object, _invoiceDate, where);
    final invoiceNumber = _requiredText(object, _invoiceNumber, where);
    final orderNumber = _requiredInteger(object, _orderNumber, where);
    final customer = _requiredText(object, _customer, where);
    final customerPhone = _requiredText(object, _customerPhone, where);
    final goods = _goodsOf(object, where);
    return DatasetOrder(
      orderId: orderId,
      invoiceDate: invoiceDate,
      invoiceNumber: invoiceNumber,
      orderNumber: orderNumber,
      customer: customer,
      customerPhone: customerPhone,
      totalMinorUnits: _totalMinorUnits(goods, orderId),
      goods: goods,
    );
  }

  List<DatasetGood> _goodsOf(JsonObjectValue order, String orderWhere) {
    final array = _requiredArray(order, _goods, orderWhere);
    final seenProductIds = <String>{};
    return [
      for (var i = 0; i < array.items.length; i++)
        _good(array.items[i], orderWhere, i + 1, seenProductIds),
    ];
  }

  DatasetGood _good(
    JsonValue value,
    String orderWhere,
    int index,
    Set<String> seenProductIds,
  ) {
    final where = DatasetMessages.goodAt(orderWhere, index);
    final object = _asRecord(value, where);
    final product = _requiredText(object, _product, where);
    final productId = _requiredInteger(object, _productId, where);
    if (!seenProductIds.add(productId.literal)) {
      throw DatasetValidationException(
        DatasetMessages.duplicateProductId(where, productId.literal),
      );
    }
    final quantity = _requiredQuantity(object, _quantity, where);
    final priceMinorUnits = _requiredMoney(object, _price, where);
    final amountMinorUnits = _requiredMoney(object, _amount, where);
    final isServiceGood = _requiredFlag(object, _isServiceGood, where);
    final isParcel = _requiredFlag(object, _isParcel, where);
    if (isServiceGood && isParcel) {
      throw DatasetValidationException(
        DatasetMessages.invalidFlagCombination(where),
      );
    }
    // ParcelTTN is required only for parcel goods. On regular and service
    // goods the field is ignored, even when it has a value.
    final parcelTtn = isParcel
        ? _requiredText(object, _parcelTtn, where)
        : null;
    final meestTtn = _optionalString(object, _meestTtn, where);
    return DatasetGood(
      product: product,
      productId: productId,
      quantity: quantity,
      priceMinorUnits: priceMinorUnits,
      amountMinorUnits: amountMinorUnits,
      isServiceGood: isServiceGood,
      isParcel: isParcel,
      parcelTtn: parcelTtn,
      meestTtn: meestTtn,
    );
  }

  JsonObjectValue _asRecord(JsonValue value, String where) {
    if (value is JsonObjectValue) return value;
    throw DatasetValidationException(DatasetMessages.invalidRecord(where));
  }

  JsonArrayValue _requiredArray(
    JsonObjectValue object,
    String field,
    String where,
  ) {
    final value = _lookup(object, field, where);
    if (value is! JsonArrayValue) {
      throw DatasetValidationException(
        DatasetMessages.invalidField(where, field),
      );
    }
    if (value.items.isEmpty) {
      throw DatasetValidationException(DatasetMessages.emptyList(where, field));
    }
    return value;
  }

  String _requiredText(JsonObjectValue object, String field, String where) {
    final value = _lookup(object, field, where);
    if (value is! JsonStringValue) {
      throw DatasetValidationException(
        DatasetMessages.invalidField(where, field),
        technical: 'Expected a string for $field',
      );
    }
    final trimmed = value.text.trim();
    if (trimmed.isEmpty) {
      throw DatasetValidationException(
        DatasetMessages.blankField(where, field),
      );
    }
    return trimmed;
  }

  /// Preserves a present string, including `""`.
  ///
  /// A missing field and JSON `null` both become `null`.
  String? _optionalString(JsonObjectValue object, String field, String where) {
    if (!object.fields.containsKey(field)) return null;
    final value = object.fields[field];
    if (value is JsonNullValue) return null;
    if (value is! JsonStringValue) {
      throw DatasetValidationException(
        DatasetMessages.invalidField(where, field),
        technical: 'Expected a string for $field',
      );
    }
    return value.text;
  }

  ExactInteger _requiredInteger(
    JsonObjectValue object,
    String field,
    String where,
  ) {
    final value = _lookup(object, field, where);
    final literal = value is JsonNumberValue ? value.literal : null;
    if (literal == null || !_integerLiteral.hasMatch(literal)) {
      throw DatasetValidationException(
        DatasetMessages.invalidInteger(where, field),
        technical: 'Rejected integer token for $field: $value',
      );
    }
    return ExactInteger(literal);
  }

  int _requiredQuantity(JsonObjectValue object, String field, String where) {
    final value = _lookup(object, field, where);
    final literal = value is JsonNumberValue ? value.literal : null;
    final quantity = literal == null ? null : _quantityOf(literal);
    if (quantity == null) {
      throw DatasetValidationException(
        DatasetMessages.invalidQuantity(where, field),
        technical: 'Rejected quantity for $field: $value',
      );
    }
    return quantity;
  }

  int _requiredMoney(JsonObjectValue object, String field, String where) {
    final value = _lookup(object, field, where);
    final literal = value is JsonNumberValue ? value.literal : null;
    final minorUnits = literal == null ? null : _minorUnitsOf(literal);
    if (minorUnits == null) {
      throw DatasetValidationException(
        DatasetMessages.invalidMoney(where, field),
        technical: 'Rejected money for $field: $value',
      );
    }
    return minorUnits;
  }

  bool _requiredFlag(JsonObjectValue object, String field, String where) {
    final value = _lookup(object, field, where);
    final literal = value is JsonNumberValue ? value.literal : null;
    return switch (literal) {
      '0' => false,
      '1' => true,
      _ => throw DatasetValidationException(
        DatasetMessages.invalidFlagValue(where, field),
        technical: 'Rejected flag for $field: $value',
      ),
    };
  }

  DateTime _requiredDate(JsonObjectValue object, String field, String where) {
    final value = _lookup(object, field, where);
    if (value is! JsonStringValue) {
      throw DatasetValidationException(
        DatasetMessages.invalidDate(where, field),
        technical: 'Expected a yyyyMMddHHmmss string for $field',
      );
    }
    // The original characters are checked. Spaces and other padding are
    // not removed, unlike ordinary required strings.
    final date = _parseCompactDateTime(value.text);
    if (date == null) {
      throw DatasetValidationException(
        DatasetMessages.invalidDate(where, field),
        technical: 'Rejected date for $field: ${value.text}',
      );
    }
    return date;
  }

  JsonValue _lookup(JsonObjectValue object, String field, String where) {
    if (!object.fields.containsKey(field) ||
        object.fields[field] is JsonNullValue) {
      throw DatasetValidationException(
        DatasetMessages.missingField(where, field),
      );
    }
    return object.fields[field]!;
  }
}

/// Adds goods amounts in kopecks without passing [DatasetLimits.maxSafeMinorUnits].
///
/// The comparison happens before the addition, so the sum is never an
/// intermediate value that JavaScript would round.
int _totalMinorUnits(List<DatasetGood> goods, String orderId) {
  var total = 0;
  for (final good in goods) {
    final amount = good.amountMinorUnits;
    if (amount > DatasetLimits.maxSafeMinorUnits - total) {
      throw DatasetValidationException(
        DatasetMessages.orderTotalTooLarge(orderId),
        technical: 'Order $orderId total would exceed the safe integer limit',
      );
    }
    total += amount;
  }
  return total;
}

class _StockIdentity {
  const _StockIdentity({
    required this.productId,
    required this.address,
    required this.serialNumber,
  });

  final ExactInteger productId;
  final String address;
  final String serialNumber;

  @override
  bool operator ==(Object other) =>
      other is _StockIdentity &&
      other.productId == productId &&
      other.address == address &&
      other.serialNumber == serialNumber;

  @override
  int get hashCode => Object.hash(productId, address, serialNumber);
}

int? _quantityOf(String literal) {
  if (!_quantityLiteral.hasMatch(literal) || literal.length > 9) return null;
  final value = int.parse(literal);
  if (value < 1 || value > DatasetLimits.maxQuantity) return null;
  return value;
}

/// Converts a JSON number literal to kopecks using only digit text.
///
/// `324` → `32400`, `324.5` → `32450`, `324.50` → `32450`. A third decimal
/// digit is rejected even when it is zero, and exponent text is rejected.
/// The result has at most 14 digits, which fits in a safe JavaScript
/// integer, so the final `int.parse` does not round.
int? _minorUnitsOf(String literal) {
  final match = _moneyLiteral.firstMatch(literal);
  if (match == null) return null;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.length > 12 || fraction.length > 2) return null;
  final minorText = '$whole${fraction.padRight(2, '0')}';
  final minorUnits = int.parse(minorText);
  if (minorUnits > DatasetLimits.maxMinorUnits) return null;
  return minorUnits;
}

DateTime? _parseCompactDateTime(String raw) {
  final match = _dateLiteral.firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final date = DateTime(year, month, day, hour, minute, second);
  final valid =
      date.year == year &&
      date.month == month &&
      date.day == day &&
      date.hour == hour &&
      date.minute == minute &&
      date.second == second;
  return valid ? date : null;
}
