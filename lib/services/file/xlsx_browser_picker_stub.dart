import 'picked_bytes.dart';

/// Outside the browser there is no file input. The app is Web/PWA-first and
/// tests inject their own picker into `LocalFileService` or `JsonFileService`.
Future<PickedBytes?> pickXlsxFromBrowser() => _unsupported();

/// Outside the browser there is no file input. See [pickXlsxFromBrowser].
Future<PickedBytes?> pickJsonFromBrowser() => _unsupported();

Future<PickedBytes?> _unsupported() => Future<PickedBytes?>.error(
  UnsupportedError('Picking a local file is only supported in the browser.'),
);

/// Test-only; see the web implementation.
int get pendingPickCount => 0;

/// Test-only; see the web implementation.
bool isPendingInput(Object input) => false;
