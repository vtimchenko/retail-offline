import '../../models/order.dart';

/// In-memory filtering of the orders already loaded for this session.
///
/// Matching is partial and does not use the repository indexes, which are
/// exact. Stored order numbers and phones are never modified.
abstract final class OrderSearch {
  static final RegExp _phoneNoise = RegExp(r'[+\s()\-]');

  /// Removes phone formatting characters for comparison only.
  ///
  /// Strips `+`, whitespace, `(`, `)` and `-`. Does not add a country code.
  static String normalizePhone(String value) =>
      value.replaceAll(_phoneNoise, '');

  /// Returns orders that match both queries, in the original order.
  ///
  /// [orderNumberQuery] is trimmed, then matched with [String.contains].
  /// [phoneQuery] and each [Order.customerPhone] are compared only after
  /// [normalizePhone]. A blank order query, or a phone query that normalizes
  /// to empty, does not restrict that side. When both sides are non-empty
  /// they combine with AND.
  static List<Order> filter(
    List<Order> orders, {
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
    Order order,
    String numberQuery,
    String normalizedPhone,
  ) {
    final numberOk =
        numberQuery.isEmpty || order.orderNumber.contains(numberQuery);
    final phoneOk =
        normalizedPhone.isEmpty ||
        normalizePhone(order.customerPhone).contains(normalizedPhone);
    return numberOk && phoneOk;
  }
}
