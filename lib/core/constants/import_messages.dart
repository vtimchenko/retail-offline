/// User-facing (Ukrainian) error messages of the import workflow.
///
/// Row numbers are the Excel row numbers (1-based, the header is row 1).
abstract final class ImportMessages {
  // ---- File acquisition -------------------------------------------------

  static const String notXlsxExtension =
      'Потрібен файл Excel у форматі .xlsx. '
      'Якщо файл у старому форматі .xls, збережіть його як «Книга Excel '
      '(.xlsx)» і оберіть ще раз.';

  static const String emptyFile = 'Обраний файл порожній.';

  static const String fileReadFailed =
      'Не вдалося прочитати обраний файл. Спробуйте обрати його ще раз.';

  static const String notXlsxContent =
      'Вміст файлу не схожий на Excel-файл (.xlsx). '
      'Можливо, файл пошкоджений або має неправильне розширення.';

  // ---- Google Drive -----------------------------------------------------

  static const String driveEmptyUrl =
      'Вставте посилання на файл Google Drive або таблицю Google.';

  static const String driveInvalidUrl =
      'Це не схоже на посилання на файл Google Drive або таблицю Google. '
      'Скопіюйте посилання через «Надати доступ» → «Копіювати посилання», '
      'воно має виглядати так: https://drive.google.com/file/d/…/view або '
      'https://docs.google.com/spreadsheets/d/…/edit';

  static const String driveFolderUrl =
      'Це посилання на папку Google Drive. Потрібне посилання на сам файл '
      '.xlsx.';

  static const String driveGoogleDocUrl =
      'Це посилання на документ, презентацію або форму Google. Потрібне '
      'посилання на файл .xlsx на Google Drive або на таблицю Google.';

  /// Shared explanation for every kind of failed direct download.
  static const String driveDownloadBlocked =
      'Google не дозволив завантажити файл безпосередньо з браузера. '
      'Переконайтеся, що доступ відкрито для всіх, хто має посилання, або '
      'завантажте файл .xlsx на пристрій і оберіть його кнопкою '
      '«Обрати файл».';

  // ---- Reading the workbook ---------------------------------------------

  static const String workbookUnreadable =
      'Не вдалося відкрити файл. Він пошкоджений або не є файлом Excel '
      '(.xlsx).';

  static const String workbookMissing =
      'У файлі не знайдено книгу Excel. Він пошкоджений або не є файлом '
      'Excel (.xlsx).';

  static const String workbookNoSheets = 'У книзі Excel немає жодного аркуша.';

  static const String worksheetMissing =
      'Не вдалося знайти дані першого аркуша. Файл пошкоджений.';

  static const String worksheetCorrupted =
      'Дані аркуша пошкоджені, файл неможливо прочитати.';

  // ---- Parsing (orders / inventory) -------------------------------------

  static String emptySheet(String fileLabel) =>
      'Перший аркуш файлу $fileLabel порожній.';

  static String missingHeaders(String fileLabel, List<String> headers) =>
      'У файлі $fileLabel відсутні обов’язкові стовпці: '
      '${headers.join(', ')}. Перший рядок аркуша має містити заголовки '
      'стовпців.';

  static String noDataRows(String fileLabel) =>
      'У файлі $fileLabel немає жодного рядка з даними.';

  static String missingValue(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row не заповнено значення «$field».';

  static String invalidValue(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row некоректне значення «$field».';

  static String unsafeIdentifier(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row значення «$field» збережене у вигляді '
      '(наприклад, 1.23E+18), який не гарантує точність цифр. Точне значення '
      'неможливо встановити. Збережіть цей стовпець як текст і спробуйте ще '
      'раз.';

  static String numericPhone(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row значення «$field» збережене як '
      'число, тому початкові нулі могли бути втрачені. Збережіть цей '
      'стовпець як текст і спробуйте ще раз.';

  static String invalidQuantity(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row некоректна кількість «$field» '
      '(потрібне ціле число).';

  static String invalidMoney(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row некоректна сума «$field» '
      '(потрібне невід’ємне число не більше ніж з двома знаками після '
      'коми).';

  static String invalidDate(String fileLabel, int row, String field) =>
      'У файлі $fileLabel у рядку $row некоректна дата «$field» '
      '(очікується формат ррррММддГГххсс, наприклад 20261003114618).';

  static String inconsistentOrder({
    required String orderNumber,
    required String field,
    required int firstRow,
    required int row,
  }) =>
      'У файлі замовлень замовлення $orderNumber має різні значення '
      '«$field» у рядках $firstRow і $row. Виправте файл і спробуйте ще раз.';

  // ---- Generic ----------------------------------------------------------

  static const String unexpected =
      'Під час обробки файлу сталася неочікувана помилка. Перевірте файл і '
      'спробуйте ще раз.';
}

/// Labels used inside messages to name each file ("у файлі замовлень").
abstract final class ImportFileLabels {
  static const String orders = 'замовлень';
  static const String inventory = 'залишків';
}
