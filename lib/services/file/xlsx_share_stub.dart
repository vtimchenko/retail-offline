import 'dart:typed_data';

import 'xlsx_share_types.dart';

export 'xlsx_share_types.dart';

/// Outside the browser there is no share sheet. The app is Web/PWA-first
/// and tests inject their own [ShareXlsx].
Future<XlsxShareResult> shareOrDownloadXlsx({
  required String filename,
  required Uint8List bytes,
}) => Future<XlsxShareResult>.error(
  UnsupportedError('Sharing a file is only supported in the browser.'),
);
