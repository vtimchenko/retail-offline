import 'dart:typed_data';

/// How a generated workbook left the browser.
enum XlsxShareResult {
  /// The system share sheet accepted the file.
  shared,

  /// The browser saved the file because file sharing is unavailable.
  downloaded,

  /// The user closed the share sheet. Nothing was downloaded.
  cancelled,
}

/// Shares or downloads one already-built workbook.
///
/// Implementations must reach the share call or the download click before
/// their first `await`, because the browser ties both to the user's tap.
typedef ShareXlsx = Future<XlsxShareResult> Function({
  required String filename,
  required Uint8List bytes,
});
