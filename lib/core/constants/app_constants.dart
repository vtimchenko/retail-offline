/// Application-wide constants and user-facing strings.
abstract final class AppConstants {
  static const String appName = 'Retail Offline';
  static const String storesAssetPath = 'stores.json';

  /// Maximum width of centered content on wide screens.
  static const double formMaxWidth = 560;
}

abstract final class AppStrings {
  static const String storeSelectionTitle = 'Вибір магазину';
  static const String storeSelectionSubtitle =
      'Оберіть магазин, у якому ви зараз працюєте';
  static const String storeFieldLabel = 'Магазин';
  static const String storeFieldHint = 'Пошук магазину…';
  static const String storeNotFound = 'Магазинів за вашим запитом не знайдено';
  static const String continueButton = 'Продовжити';
  static const String clear = 'Очистити';
  static const String retry = 'Спробувати ще раз';
  static const String loadingStores = 'Завантаження списку магазинів…';
  static const String storesEmptyTitle = 'Список магазинів порожній';
  static const String storesEmptyMessage =
      'У файлі stores.json не знайдено жодного магазину.';
  static const String storesErrorTitle = 'Не вдалося завантажити магазини';
  static const String storesErrorMessage =
      'Перевірте файл stores.json та спробуйте ще раз.';
}
