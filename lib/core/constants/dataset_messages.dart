import '../../models/retail_dataset.dart';

/// User-facing (Ukrainian) errors for the JSON dataset parser.
///
/// Stock and goods positions are 1-based, in the order they appear in the
/// file. The first invalid required field fails the whole dataset.
abstract final class DatasetMessages {
  static const String inDataset = 'У наборі даних';

  static String stockAt(int index) => 'У залишку $index';

  static String orderAt(int index) => 'У замовленні $index';

  static String orderId(String orderId) => 'У замовленні «$orderId»';

  static String goodAt(String orderWhere, int index) =>
      '$orderWhere у товарі $index';

  static String missingField(String where, String field) =>
      '$where відсутнє обов’язкове поле «$field».';

  static String blankField(String where, String field) =>
      '$where не заповнено значення «$field».';

  static String invalidField(String where, String field) =>
      '$where некоректне значення «$field».';

  static String invalidDate(String where, String field) =>
      '$where некоректна дата «$field» '
      '(очікується формат ррррММддГГххсс, наприклад 20261003114618).';

  static String invalidDbName(String where) =>
      '$where некоректне значення «dbName» '
      '(дозволені лише латинські літери, цифри, «_» та «-»).';

  static String emptyList(String where, String field) =>
      '$where список «$field» порожній.';

  static String invalidInteger(String where, String field) =>
      '$where некоректне значення «$field» '
      '(потрібне невід’ємне ціле JSON-число без лапок, дробової частини '
      'та експоненти).';

  static String duplicateKey(
    String key, {
    required int line,
    required int column,
  }) =>
      'У JSON-об’єкті повторюється поле «$key» '
      '(рядок $line, позиція $column).';

  static String orderTotalTooLarge(String orderId) =>
      'У замовленні «$orderId» сума «Amount» перевищує '
      '${DatasetLimits.maxSafeMinorUnits} копійок.';

  static String invalidQuantity(String where, String field) =>
      '$where некоректна кількість «$field» '
      '(потрібне ціле число від 1 до 999999999).';

  static String invalidMoney(String where, String field) =>
      '$where некоректна сума «$field» '
      '(потрібне невід’ємне число не більше ніж з двома знаками після '
      'коми, до 999999999999.99, без округлення).';

  static String invalidFlagValue(String where, String field) =>
      '$where некоректне значення «$field» (потрібне ціле число 0 або 1).';

  static String invalidFlagCombination(String where) =>
      '$where некоректне поєднання «isServiceGood» та «isParcel».';

  static String duplicateOrderId(String orderId) =>
      'У наборі даних повторюється «OrderID» «$orderId».';

  static String duplicateProductId(String where, String productId) =>
      '$where повторюється «ProductID» $productId.';

  static String notAnObject() => 'Набір даних має бути JSON-об’єктом.';

  static String invalidRecord(String where) =>
      '$where некоректний запис (очікувався об’єкт).';

  static String syntax({required int line, required int column}) =>
      'Некоректний JSON (рядок $line, позиція $column). '
      'Перевірте файл і спробуйте ще раз.';
}
