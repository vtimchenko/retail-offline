import 'dart:typed_data';

/// MIME type of the JSON file passed to the browser.
///
/// Used for both the shared file and the download blob.
const String jsonExportMimeType = 'application/json';

/// Outcome of asking the browser to share or download one JSON file.
///
/// A successful value means the browser accepted the request. It does not
/// mean another application stored the file, or that a download finished.
sealed class ExportShareResult {
  const ExportShareResult();
}

/// The browser accepted the share handoff.
///
/// `navigator.share` resolved. The selected application may still drop the
/// file after that handoff.
final class ExportShareHandedOff extends ExportShareResult {
  /// Creates a resolved-share result.
  const ExportShareHandedOff();
}

/// The browser was asked to download the file.
///
/// The download click ran. The browser may still block it, and the user may
/// still discard the file. [reason] records why the share sheet was not used.
final class ExportShareDownloadStarted extends ExportShareResult {
  /// Creates a download-started result for [reason].
  const ExportShareDownloadStarted(this.reason);

  /// Why the share sheet did not receive the file.
  final ExportShareDownloadReason reason;
}

/// Why [ExportShareDownloadStarted] used the download fallback.
enum ExportShareDownloadReason {
  /// `navigator.canShare` was missing, threw, or rejected the file.
  sharingUnavailable,

  /// `navigator.share` rejected the file for a reason other than cancellation.
  shareRejected,
}

/// The share sheet was dismissed.
///
/// The browser reported `AbortError`. No download was started.
final class ExportShareCancelled extends ExportShareResult {
  /// Creates a cancelled-share result.
  const ExportShareCancelled();
}

/// The browser could not share the file or start a download.
final class ExportShareFailed extends ExportShareResult {
  /// Creates a failed-share result.
  const ExportShareFailed();
}

/// No export document was available to share.
///
/// Reserved for the coordinator that reads the last persisted export.
/// The browser adapter leaves this value unused.
final class ExportShareUnavailable extends ExportShareResult {
  /// Creates an unavailable-export result.
  const ExportShareUnavailable();
}

/// Shares or downloads one already-built JSON file.
///
/// Implementations reach `navigator.share` or the download click before
/// their first `await`, because the browser ties both to the user's tap.
/// [filename] and [bytes] are the persisted file, passed through unchanged.
typedef ShareJson = Future<ExportShareResult> Function({
  required String filename,
  required Uint8List bytes,
});
