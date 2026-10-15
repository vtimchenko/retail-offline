import '../json/cumulative_json_export.dart';
import 'export_share.dart';

/// Shares one persisted [ExportDocument] through [ShareJson].
///
/// Passes [ExportDocument.filename] and [ExportDocument.bytes] through
/// unchanged. A missing document returns [ExportShareUnavailable] without
/// calling the adapter.
class CumulativeExportShare {
  /// [shareJson] replaces [shareOrDownloadJson] in tests.
  const CumulativeExportShare({ShareJson? shareJson})
    : _shareJson = shareJson ?? shareOrDownloadJson;

  final ShareJson _shareJson;

  /// Shares [document], or reports that none was available.
  ///
  /// The adapter runs before this method suspends, so a button handler can
  /// call it directly and still satisfy the browser user-gesture rule.
  Future<ExportShareResult> share(ExportDocument? document) {
    if (document == null) {
      return Future<ExportShareResult>.value(const ExportShareUnavailable());
    }
    return _shareJson(filename: document.filename, bytes: document.bytes);
  }
}
