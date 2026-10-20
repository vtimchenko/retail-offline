/// Application-wide constants and user-facing strings.
abstract final class AppConstants {
  static const String appName = 'Retail Offline';

  /// Maximum width of centered content on wide screens.
  static const double formMaxWidth = 560;

  /// Width at which stacked cards give way to a side-by-side or table layout.
  static const double wideLayoutBreakpoint = 720;

  /// Maximum width of the orders list and order details on wide screens.
  static const double ordersMaxWidth = 1100;

  /// Horizontal gap between columns in the desktop tables.
  static const double tableColumnGap = 8;
}

abstract final class AppStrings {
  static const String retry = 'Спробувати ще раз';
  static const String cancel = 'Скасувати';
  static const String viewOrders = 'Переглянути замовлення';

  // ---- JSON import ----
  static const String jsonScreenTitle = 'Видача замовлень';
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
  static const String jsonIssuedCountLabel = 'Видано';
  static const String jsonIssuedAmountLabel = 'На суму';

  static String ordersWithStore(String storeName) =>
      '$ordersScreenTitle — $storeName';

  static String accountLine(String invoiceNumber, String formattedDate) =>
      'Рахунок №$invoiceNumber від $formattedDate';
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
  static const String jsonCreateExport = 'Сформувати JSON-файл';
  static const String jsonLastSavedExport = 'Останній збережений файл:';
  static const String jsonExportUnchanged =
      'Немає нових виданих замовлень для експорту.';
  static const String jsonExportRejected =
      'Не вдалося сформувати JSON-файл. Перевірте видані замовлення і спробуйте ще раз.';
  static const String jsonReplaceDataset = 'Завантажити новий JSON';
  static const String jsonReplaceExportFirst =
      'Є видані замовлення, які ще не експортовано. Спочатку сформуйте JSON-файл.';
  static const String jsonReplaceTitle = 'Замінити дані?';
  static const String jsonReplaceWarning =
      'Поточні дані та стан роботи буде замінено. Резервування, статуси '
      'замовлень і попередній експорт буде видалено.';
  static const String jsonReplaceCurrent = 'Зараз';
  static const String jsonReplaceIncoming = 'Новий файл';
  static const String jsonReplaceConfirm = 'Замінити';
  static const String jsonReplaceStale =
      'Дані змінилися. Поточний набір не замінено.';

  // ---- Orders ----
  static const String ordersScreenTitle = 'Замовлення';
  static const String invoiceDateLabel = 'Дата';
  static const String invoiceNumberLabel = '№ рахунка';
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
  static const String productIdLabel = 'Код товару';
  static const String quantityLabel = 'Кількість';
  static const String priceLabel = 'Ціна';
  static const String amountLabel = 'Сума';
  static const String orderTotalLabel = 'Сума замовлення';
  static const String parcelGoodLabel = 'Посилка';
  static const String serviceGoodLabel = 'Послуга';
  static const String parcelTtnLabel = 'ТТН посилки';
  static const String meestTtnLabel = 'Meest ТТН';
  static const String serviceLineProgress = 'Не потребує вибору';
  static const String jsonOrderNotFoundTitle = 'Замовлення не знайдено';
  static const String jsonOrderNotFoundMessage =
      'Цього замовлення немає в поточних даних.';
  static const String jsonBackToOrders = 'До списку замовлень';
  static const String jsonGoodNotFoundTitle = 'Товар не знайдено';
  static const String jsonGoodNotFoundMessage =
      'Цього товару немає в поточному замовленні.';
  static const String jsonSerialInsufficientStock = 'Цього залишку вже немає.';
  static const String jsonSerialLineComplete =
      'Для цього товару вже обрано потрібну кількість.';
  static const String jsonSerialInvalidQuantity = 'Некоректна кількість.';
  static const String jsonSerialUnknownStock =
      'Цього залишку немає в поточних даних.';
  static const String jsonSerialServiceLine =
      'Послуга не потребує вибору серійного номера.';
  static const String jsonSerialParcelMismatch =
      'Для посилки можна обрати лише серійний номер її ТТН.';
  static const String jsonSerialOrderLocked =
      'Замовлення вже видано або експортовано. Змінити вибір не можна.';
  static const String jsonSerialInsufficientReserved =
      'Обраної кількості на цій адресі вже немає.';

  // ---- Serial selection ----
  static const String completeService = 'Завершити обслуговування';
  static const String completeServiceNotReady =
      'Кнопка стане доступною, коли для всіх товарів буде обрано потрібну кількість.';
  static const String completeServiceIssued =
      'Обслуговування цього замовлення вже завершено.';
  static const String completeServiceExported =
      'Замовлення вже в експорті. Повторити завершення не можна.';
  static const String shareFile = 'Поширити файл';
  static const String excelShareFailed = 'Не вдалося поширити файл';
  static const String orderStatusLabel = 'Статус';
  static const String dialogOk = 'Гаразд';
  static const String availableInventoryTitle = 'Доступні залишки';
  static const String selectedSerialsTitle = 'Обрані серійні номери';
  static const String addressLabel = 'Адреса';
  static const String serialNumberLabel = 'Серійний номер';
  static const String availableQuantityLabel = 'Доступно';
  static const String selectedQuantityLabel = 'Обрано';
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

  static String jsonDuplicateStock({
    required String? productId,
    required String? address,
    required String? serialNumber,
  }) =>
      'У наборі даних повторюється залишок '
      '«ProductID» $productId, «Address» «$address», '
      '«SerialNumber» «$serialNumber».';
}
