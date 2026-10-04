import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../diagnostics/picker_diagnostics.dart';
import '../../models/imported_file.dart';
import 'web_picker_options.dart';

/// A file chosen in the picker: name plus contents (no filesystem path).
typedef PickedBytes = ({String name, Uint8List bytes});

/// Lets the user choose an `.xlsx` file on the device and returns it as an
/// [ImportedFile].
///
/// Web-first: works with bytes only, never with paths or `dart:io`.
class LocalFileService {
  /// [picker] can be replaced in tests; it returns `null` when the user
  /// cancels.
  const LocalFileService({Future<PickedBytes?> Function()? picker})
    : _picker = picker ?? _pickWithFilePicker;

  final Future<PickedBytes?> Function() _picker;

  /// Returns `null` when the user cancels (not an error). Throws
  /// [ImportException] if the chosen file is obviously not an `.xlsx`.
  Future<ImportedFile?> pickXlsx() async {
    // TEMPORARY DIAGNOSTICS: everything before `_picker()` is synchronous so
    // the browser still sees the tap's user gesture.
    final diag = PickerDiagnostics.instance..beginAttempt();
    final PickedBytes? picked;
    try {
      picked = await _picker();
    } on Object catch (e) {
      debugPrint('File picker failed: $e');
      diag.log('picker failed: ${e.runtimeType}: $e');
      throw ImportException(
        ImportMessages.fileReadFailed,
        technical: 'Picker failure',
        cause: e,
      );
    }
    if (picked == null) {
      diag.log(
        'pickXlsx: picker returned null -> treated as cancel, UI unchanged',
      );
      return null;
    }
    try {
      final file = validate(picked.name, picked.bytes);
      diag.log('validate OK: ${file.name}, ${file.bytes.length} bytes');
      return file;
    } on ImportException catch (e) {
      diag.log('validate REJECTED: ${e.technical ?? e.message}');
      rethrow;
    }
  }

  /// Checks the extension and that the content has the ZIP signature every
  /// `.xlsx` has. Deeper structure is verified by `ExcelImportService`.
  @visibleForTesting
  static ImportedFile validate(String name, Uint8List bytes) {
    if (!name.toLowerCase().endsWith('.xlsx')) {
      throw ImportException(
        ImportMessages.notXlsxExtension,
        technical: 'Wrong extension: $name',
      );
    }
    if (bytes.isEmpty) {
      throw const ImportException(ImportMessages.emptyFile);
    }
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw ImportException(
        ImportMessages.notXlsxContent,
        technical: 'No ZIP signature in $name',
      );
    }
    return ImportedFile(name: name, bytes: bytes, source: FileSource.local);
  }

  static Future<PickedBytes?> _pickWithFilePicker() async {
    // TEMPORARY DIAGNOSTICS: logging only; the call below is unchanged.
    final diag = PickerDiagnostics.instance;
    diag.log(
      "FilePicker.pickFile called (custom, allowedExtensions=['xlsx'], "
      '$pickerWebOptionsLabel)',
    );
    final stopWatching = diag.watchPending('FilePicker.pickFile');
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        webOptions: pickerWebOptions(),
      );
    } on Object catch (e) {
      diag.log('FilePicker.pickFile THREW ${e.runtimeType}: $e');
      rethrow;
    } finally {
      stopWatching();
    }
    diag.log('FilePicker.pickFile completed');
    if (file == null) {
      diag.log('result = null');
      return null;
    }
    diag.log(
      'result != null: PlatformFile name=${file.name} '
      'ext=${file.extension} lengthSync=${file.lengthSync()} '
      'uri.scheme=${file.uri.scheme}',
    );
    diag.log('readAsBytes started');
    try {
      final bytes = await file.readAsBytes();
      diag.log('readAsBytes completed: bytes length=${bytes.length}');
      return (name: file.name, bytes: bytes);
    } on Object catch (e) {
      diag.log('readAsBytes THREW ${e.runtimeType}: $e');
      rethrow;
    }
  }
}
