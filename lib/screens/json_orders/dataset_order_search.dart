import '../../models/retail_dataset.dart';

/// In-memory filtering of orders in the current JSON dataset.
///
/// Matching does not change [DatasetOrder.orderNumber] or
/// [DatasetOrder.customerPhone]. Order identity is [DatasetOrder.orderId];
/// [DatasetOrder.orderNumber] is only a search field.
abstract final class DatasetOrderSearch {
  static final RegExp _phoneNoise = RegExp(r'[+\s()\-]');

  /// Removes phone formatting characters for comparison only.
  ///
  /// Strips `+`, whitespace, `(`, `)` and `-`. Does not add a country code.
  static String normalizePhone(String value) =>
      value.replaceAll(_phoneNoise, '');

  /// Returns orders that match both queries, in the original order.
  ///
  /// [orderNumberQuery] is trimmed, then matched against the order-number
  /// literal with [String.contains]. Comparison is case-sensitive.
  ///
  /// [phoneQuery] and each [DatasetOrder.customerPhone] are compared only
  /// after [normalizePhone]. A blank order query, or a phone query that
  /// normalizes to empty, does not restrict that side. An empty stored phone
  /// does not match a non-empty normalized query. When both sides are
  /// non-empty they combine with AND.
  static List<DatasetOrder> filter(
    List<DatasetOrder> orders, {
    required String orderNumberQuery,
    required String phoneQuery,
  }) {
    final numberQuery = orderNumberQuery.trim();
    final normalizedPhone = normalizePhone(phoneQuery);
    return [
      for (final order in orders)
        if (_matches(order, numberQuery, normalizedPhone)) order,
    ];
  }

  static bool _matches(
    DatasetOrder order,
    String numberQuery,
    String normalizedPhone,
  ) {
    final numberOk =
        numberQuery.isEmpty || order.orderNumber.literal.contains(numberQuery);
    final phoneOk =
        normalizedPhone.isEmpty ||
        normalizePhone(order.customerPhone).contains(normalizedPhone);
    return numberOk && phoneOk;
  }
}
