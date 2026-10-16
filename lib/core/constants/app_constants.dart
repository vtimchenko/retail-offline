/// Application-wide constants and user-facing strings.
abstract final class AppConstants {
  static const String appName = 'Retail Offline';
  static const String storesAssetPath = 'stores.json';

  /// Maximum width of centered content on wide screens.
  static const double formMaxWidth = 560;

  /// Width at which stacked cards give way to a side-by-side or table layout.
  static const double wideLayoutBreakpoint = 720;

  /// Maximum width of the orders list and order details on wide screens.
  static const double ordersMaxWidth = 1100;
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

  // ---- Home screen: data import ----
  static const String homeTitle = 'Підготовка даних';
  static const String homeSubtitle =
      'Додайте два файли Excel (.xlsx): замовлення та залишки. Кожен файл '
      'можна обрати на пристрої або вказати посилання Google Drive.';
  static const String ordersCardTitle = 'Файл замовлень';
  static const String inventoryCardTitle = 'Файл залишків';
  static const String selectFile = 'Обрати файл';
  static const String googleDriveLink = 'Посилання Google Drive';
  static const String noFileSelected = 'Файл не обрано';
  static const String fileLabel = 'Файл';
  static const String sourceLabel = 'Джерело';
  static const String sourceLocal = 'Локальний файл';
  static const String sourceGoogleDrive = 'Google Drive';
  static const String statusEmpty = 'Не обрано';
  static const String statusReady = 'Обрано';
  static const String statusLoading = 'Обробка…';
  static const String statusLoaded = 'Завантажено';
  static const String statusError = 'Помилка';
  static const String loadData = 'Завантажити дані';
  static const String loadDataHint = 'Щоб продовжити, додайте обидва файли.';
  static const String importing = 'Обробка файлів…';
  static const String importDoneTitle = 'Дані завантажено';
  static const String ordersCount = 'Замовлень';
  static const String orderItemsCount = 'Товарних позицій';
  static const String inventoryRecordsCount = 'Записів залишків';
  static const String driveDialogTitle = 'Посилання Google Drive';
  static const String driveDialogLabel = 'Посилання на файл';
  static const String driveDialogHint = 'https://drive.google.com/file/d/…';
  static const String driveDialogNote =
      'Файл або таблиця Google мають бути відкриті для всіх, хто має '
      'посилання. Якщо Google не дозволить завантажити файл у браузері, '
      'завантажте його на пристрій '
      'і оберіть кнопкою «Обрати файл».';
  static const String cancel = 'Скасувати';
  static const String getFile = 'Отримати файл';
  static const String viewOrders = 'Переглянути замовлення';

  // ---- JSON import. Temporary entry beside the Excel workflow. ----
  static const String jsonModeEntry = 'Новий JSON-режим';
  static const String jsonScreenTitle = 'JSON-режим';
  static const String jsonLoading = 'Завантаження збережених даних…';
  static const String jsonEmptyTitle = 'Немає збережених даних';
  static const String jsonEmptyMessage =
      'Імпортуйте локальний файл JSON, щоб почати роботу.';
  static const String jsonImport = 'Імпортувати JSON';
  static const String jsonImporting = 'Імпорт JSON…';
  static const String jsonReadyTitle = 'Дані завантажено';
  static const String jsonStoreNameLabel = 'Магазин';
  static const String jsonDbNameLabel = 'База даних';
  static const String jsonDateCreateLabel = 'Дата створення';
  static const String jsonOrdersLabel = 'Замовлень';
  static const String jsonBlockedTitle = 'Роботу призупинено';
  static const String jsonReadFailed = 'Не вдалося прочитати збережені дані.';
  static const String jsonImportRejected =
      'Не вдалося імпортувати файл JSON. Перевірте файл і спробуйте ще раз.';
  static const String jsonMalformedUtf8 =
      'Файл не є текстом JSON у кодуванні UTF-8.';
  static const String jsonImportOccupied =
      'Імпорт не виконано, бо дані вже завантажені.';
  static const String jsonRevisionConflict =
      'Дані змінилися в іншій вкладці. Збережене не перезаписано. '
      'Оновіть дані, щоб побачити актуальний стан.';
  static const String jsonStorageUnavailable =
      'Не вдалося відкрити збережені дані.';
  static const String jsonStorageFailed =
      'Не вдалося прочитати або записати дані.';
  static const String jsonCorrupted = 'Збережені дані пошкоджені.';
  static const String jsonUnsupportedVersion =
      'Збережені дані мають непідтримувану версію.';
  static const String jsonRevisionOverflow =
      'Неможливо продовжити: вичерпано номер версії даних.';

  // ---- Orders ----
  static const String ordersScreenTitle = 'Замовлення';
  static const String invoiceDateLabel = 'Дата';
  static const String invoiceNumberLabel = 'Накладна';
  static const String orderNumberLabel = 'Номер замовлення';
  static const String customerLabel = 'Клієнт';
  static const String customerPhoneLabel = 'Телефон';
  static const String orderNumberSearchLabel = 'Номер замовлення';
  static const String orderNumberSearchHint = 'Пошук за номером…';
  static const String phoneSearchLabel = 'Телефон клієнта';
  static const String phoneSearchHint = 'Пошук за телефоном…';
  static const String ordersEmptyTitle = 'Замовлень немає';
  static const String ordersEmptyMessage =
      'У завантажених даних немає жодного замовлення.';
  static const String ordersNoMatchTitle = 'Нічого не знайдено';
  static const String ordersNoMatchMessage =
      'Жодне замовлення не відповідає пошуку.';
  static const String orderItemsTitle = 'Товари';
  static const String productLabel = 'Товар';
  static const String quantityLabel = 'Кількість';
  static const String priceLabel = 'Ціна';
  static const String amountLabel = 'Сума';

  // ---- Serial selection ----
  static const String completeService = 'Завершити обслуговування';
  static const String shareFile = 'Поширити файл';
  static const String excelFileCreated = 'Файл Excel успішно сформовано';
  static const String excelGenerationFailed =
      'Не вдалося сформувати файл Excel';
  static const String excelShareFailed = 'Не вдалося поширити файл';
  static const String orderStatusLabel = 'Статус';
  static const String orderStatusNone = 'Без вибору';
  static const String orderStatusInProgress = 'В процесі';
  static const String orderStatusReady = 'Готово';
  static const String orderStatusFileReady = 'Файл сформовано';
  static const String fulfilmentIncompleteTitle = 'Обслуговування не завершено';
  static const String fulfilmentIncompleteIntro =
      'Не для всіх товарів обрано потрібну кількість серійних номерів:';
  static const String dialogOk = 'Гаразд';
  static const String availableInventoryTitle = 'Доступні залишки';
  static const String selectedSerialsTitle = 'Обрані серійні номери';
  static const String addressLabel = 'Адреса';
  static const String serialNumberLabel = 'Серійний номер';
  static const String availableQuantityLabel = 'Доступно';
  static const String selectedQuantityLabel = 'Обрано';
  static const String requiredQuantityLabel = 'Потрібна кількість';
  static const String serialSearchLabel = 'Пошук серійного номера';
  static const String serialSearchHint = 'Пошук за серійним номером…';
  static const String addSerial = 'Додати';
  static const String removeSerial = 'Прибрати';
  static const String noAvailableInventory =
      'Немає доступних залишків для цього товару';
  static const String serialNoMatch =
      'Жоден серійний номер не відповідає пошуку.';
  static const String noSelectedSerials = 'Серійні номери ще не обрані';

  static String selectedOfRequired(int selected, int requiredQuantity) =>
      'Обрано $selected з $requiredQuantity';

  static String fulfilmentGapLine(
    String product,
    int requiredQuantity,
    int selectedQuantity,
  ) => '$product — потрібно $requiredQuantity, обрано $selectedQuantity';

  static String jsonDuplicateStock({
    required String? productId,
    required String? address,
    required String? serialNumber,
  }) =>
      'У наборі даних повторюється залишок '
      '«ProductID» $productId, «Address» «$address», '
      '«SerialNumber» «$serialNumber».';
}
