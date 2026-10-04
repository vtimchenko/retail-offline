import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
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
    final PickedBytes? picked;
    try {
      picked = await _picker();
    } on Object catch (e) {
      debugPrint('File picker failed: $e');
      throw ImportException(
        ImportMessages.fileReadFailed,
        technical: 'Picker failure',
        cause: e,
      );
    }
    if (picked == null) return null;
    return validate(picked.name, picked.bytes);
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
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      // Without this, iOS Safari/PWA selections are lost; see
      // `pickerWebOptions`.
      webOptions: pickerWebOptions(),
    );
    if (file == null) return null;
    return (name: file.name, bytes: await file.readAsBytes());
  }
}
