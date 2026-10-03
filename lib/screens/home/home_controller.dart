import 'package:flutter/foundation.dart';

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../models/imported_file.dart';
import '../../repositories/session_data_repository.dart';
import '../../services/excel/excel_import_service.dart';
import '../../services/excel/inventory_parser_service.dart';
import '../../services/excel/orders_parser_service.dart';
import '../../services/file/google_drive_file_service.dart';
import '../../services/file/local_file_service.dart';

/// The two files the user has to provide.
enum ImportSlotId { orders, inventory }

/// What the UI shows for one file slot.
enum SlotStatus { empty, ready, loading, loaded, error }

/// State of one file slot.
@immutable
class FileSlot {
  const FileSlot({
    this.file,
    this.isBusy = false,
    this.isLoaded = false,
    this.error,
  });

  /// The chosen file, `null` if none (or if acquiring it failed).
  final ImportedFile? file;

  /// A download or the data import is in progress for this slot.
  final bool isBusy;

  /// The file's data is in the session repository.
  final bool isLoaded;

  /// User-facing (Ukrainian) message of the last failure.
  final String? error;

  SlotStatus get status {
    if (isBusy) return SlotStatus.loading;
    if (error != null) return SlotStatus.error;
    if (file == null) return SlotStatus.empty;
    return isLoaded ? SlotStatus.loaded : SlotStatus.ready;
  }

  /// A file is chosen and nothing is wrong with it.
  bool get isUsable => file != null && error == null && !isBusy;

  FileSlot copyWith({
    ImportedFile? file,
    bool? isBusy,
    bool? isLoaded,
    String? error,
    bool clearError = false,
  }) => FileSlot(
    file: file ?? this.file,
    isBusy: isBusy ?? this.isBusy,
    isLoaded: isLoaded ?? this.isLoaded,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Counts of the data currently in the session repository.
@immutable
class ImportSummary {
  const ImportSummary({
    required this.orders,
    required this.orderItems,
    required this.inventoryRecords,
  });

  factory ImportSummary.of(SessionDataRepository repository) => ImportSummary(
    orders: repository.orderCount,
    orderItems: repository.orderItemCount,
    inventoryRecords: repository.inventoryCount,
  );

  final int orders;
  final int orderItems;
  final int inventoryRecords;
}

/// State and workflow of the import on the home screen:
/// acquire two files → parse and validate BOTH → commit atomically.
class HomeController extends ChangeNotifier {
  HomeController({
    required this.repository,
    LocalFileService? localFiles,
    GoogleDriveFileService? googleDrive,
    this.excel = const ExcelImportService(),
    this.ordersParser = const OrdersParserService(),
    this.inventoryParser = const InventoryParserService(),
  }) : localFiles = localFiles ?? const LocalFileService(),
       googleDrive = googleDrive ?? GoogleDriveFileService(),
       _summary = repository.hasData ? ImportSummary.of(repository) : null;

  final SessionDataRepository repository;
  final LocalFileService localFiles;
  final GoogleDriveFileService googleDrive;
  final ExcelImportService excel;
  final OrdersParserService ordersParser;
  final InventoryParserService inventoryParser;

  FileSlot _orders = const FileSlot();
  FileSlot _inventory = const FileSlot();
  ImportSummary? _summary;
  bool _isImporting = false;
  bool _disposed = false;

  FileSlot get orders => _orders;
  FileSlot get inventory => _inventory;
  FileSlot slot(ImportSlotId id) =>
      id == ImportSlotId.orders ? _orders : _inventory;

  /// Summary of the data in the repository, `null` if nothing was loaded.
  ImportSummary? get summary => _summary;

  bool get isImporting => _isImporting;

  /// Anything in progress (a download or the import itself).
  bool get isBusy => _isImporting || _orders.isBusy || _inventory.isBusy;

  /// "Load data" is allowed only with BOTH files usable, and when there is
  /// something new to load.
  bool get canLoad =>
      !isBusy &&
      _orders.isUsable &&
      _inventory.isUsable &&
      !(_orders.isLoaded && _inventory.isLoaded);

  // ---- Choosing files ---------------------------------------------------

  /// Opens the file picker. Cancelling does nothing.
  Future<void> pickLocalFile(ImportSlotId id) async {
    if (isBusy) return;
    try {
      final file = await localFiles.pickXlsx();
      if (file == null) return;
      _accept(id, file);
    } on ImportException catch (e) {
      _fail(id, e);
    }
  }

  /// Downloads a public Google Drive file. Failures only affect this slot;
  /// local files keep working.
  Future<void> pickGoogleDriveFile(ImportSlotId id, String url) async {
    if (isBusy) return;
    _setSlot(id, slot(id).copyWith(isBusy: true, clearError: true));
    try {
      final file = await googleDrive.download(url);
      _accept(id, file);
    } on ImportException catch (e) {
      _fail(id, e);
    } on Object catch (e, st) {
      debugPrint('Unexpected Google Drive failure: $e\n$st');
      _setSlot(id, const FileSlot(error: ImportMessages.driveDownloadBlocked));
    }
  }

  void _accept(ImportSlotId id, ImportedFile file) {
    try {
      excel.verifyWorkbook(file.bytes);
    } on ImportException catch (e) {
      _fail(id, e);
      return;
    }
    _setSlot(id, FileSlot(file: file));
  }

  void _fail(ImportSlotId id, ImportException e) {
    debugPrint('Import failure (${id.name}): $e');
    _setSlot(id, FileSlot(error: e.message));
  }

  // ---- Import -----------------------------------------------------------

  /// Parses and validates both files completely, and only then updates the
  /// repository. If anything fails, the repository stays exactly as it was.
  Future<void> loadData() async {
    if (!canLoad) return;
    final ordersFile = _orders.file!;
    final inventoryFile = _inventory.file!;

    _isImporting = true;
    _orders = _orders.copyWith(isBusy: true, clearError: true);
    _inventory = _inventory.copyWith(isBusy: true, clearError: true);
    notifyListeners();

    var stage = ImportSlotId.orders;
    try {
      // Let the progress state paint before the synchronous parsing work.
      await _yieldToUi();
      final parsedOrders = ordersParser.parse(
        excel.readFirstSheet(ordersFile.bytes),
      );

      stage = ImportSlotId.inventory;
      await _yieldToUi();
      final parsedInventory = inventoryParser.parse(
        excel.readFirstSheet(inventoryFile.bytes),
      );

      // Both datasets are complete and valid: only now touch the repository.
      repository.commit(orders: parsedOrders, inventory: parsedInventory);
      _summary = ImportSummary.of(repository);
      _orders = _orders.copyWith(isBusy: false, isLoaded: true);
      _inventory = _inventory.copyWith(isBusy: false, isLoaded: true);
    } on ImportException catch (e) {
      debugPrint('Import failed at ${stage.name}: $e');
      _finishWithError(stage, e.message);
    } on Object catch (e, st) {
      debugPrint('Unexpected import failure at ${stage.name}: $e\n$st');
      _finishWithError(stage, ImportMessages.unexpected);
    } finally {
      _isImporting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _finishWithError(ImportSlotId failed, String message) {
    _orders = _orders.copyWith(isBusy: false);
    _inventory = _inventory.copyWith(isBusy: false);
    _setSlot(failed, slot(failed).copyWith(error: message), notify: false);
  }

  void _setSlot(ImportSlotId id, FileSlot value, {bool notify = true}) {
    if (id == ImportSlotId.orders) {
      _orders = value;
    } else {
      _inventory = value;
    }
    if (notify && !_disposed) notifyListeners();
  }

  static Future<void> _yieldToUi() =>
      Future<void>.delayed(const Duration(milliseconds: 16));

  @override
  void dispose() {
    _disposed = true;
    googleDrive.close();
    super.dispose();
  }
}
