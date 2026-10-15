import 'dart:typed_data';

import 'export_share_types.dart';

export 'export_share_types.dart';

/// Outside the browser there is no share sheet. The app is Web/PWA-first
/// and tests inject their own [ShareJson].
///
/// Completes with an [UnsupportedError]. It does not share, download, or
/// read [bytes] as text.
Future<ExportShareResult> shareOrDownloadJson({
  required String filename,
  required Uint8List bytes,
}) => Future<ExportShareResult>.error(
  UnsupportedError('Sharing a file is only supported in the browser.'),
);
