import 'package:flutter/foundation.dart';

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import 'picked_bytes.dart';
import 'xlsx_browser_picker.dart';

/// Lets the user choose a local `.json` file and returns its bytes.
///
/// Web-first: works with bytes only, never with paths or `dart:io`. The
/// bytes are not parsed here. Cancellation returns `null` and is not an error.
///
/// Call [pickJsonBytes] synchronously from the user's tap. The browser picker
/// opens its chooser inside that call.
class JsonFileService {
  /// [picker] can be replaced in tests; it returns `null` when the user
  /// cancels. The default is the shared browser file chooser.
  const JsonFileService({Future<PickedBytes?> Function()? picker})
    : _picker = picker ?? pickJsonFromBrowser;

  final Future<PickedBytes?> Function() _picker;

  /// Returns the chosen file's bytes, or `null` when the user cancels.
  ///
  /// Throws [ImportException] when the chooser fails or the chosen name is
  /// not a `.json` file. The bytes themselves are not interpreted.
  Future<Uint8List?> pickJsonBytes() async {
    final PickedBytes? picked;
    try {
      picked = await _picker();
    } on Object catch (error) {
      debugPrint('JSON file picker failed: $error');
      throw ImportException(
        ImportMessages.fileReadFailed,
        technical: 'Picker failure',
        cause: error,
      );
    }
    if (picked == null) return null;
    if (!picked.name.toLowerCase().endsWith('.json')) {
      throw ImportException(
        ImportMessages.notJsonExtension,
        technical: 'Wrong extension: ${picked.name}',
      );
    }
    return picked.bytes;
  }
}
