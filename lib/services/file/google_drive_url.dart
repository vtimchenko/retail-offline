import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';

/// Parser for public Google Drive / Google Sheets share links and builder of
/// the XLSX export address. Pure and offline.
abstract final class GoogleDriveUrl {
  static final RegExp _fileId = RegExp(r'^[A-Za-z0-9_-]{10,}$');

  /// Google editors that can never be exported as an Excel workbook.
  static const Set<String> _unsupportedDocs = {
    'document',
    'presentation',
    'forms',
  };

  /// Extracts the file id from a Google Drive file or Google Sheets link.
  ///
  /// Supported:
  /// * `https://drive.google.com/file/d/{id}/view?usp=sharing`
  ///   (also `/edit`, `/preview`, `/file/u/0/d/{id}`)
  /// * `https://drive.google.com/open?id={id}`
  /// * `https://drive.google.com/uc?id={id}` / `uc?export=download&id={id}`
  /// * `https://docs.google.com/spreadsheets/d/{id}/edit` (also `/view`,
  ///   `/spreadsheets/u/0/d/{id}`) — uploaded XLSX opened in Google Sheets or
  ///   a native Google Sheet; both are fetched through the same export.
  ///
  /// The query parameters of the link (`usp`, `ouid`, `rtpof`, `sd`, …) are
  /// ignored: nothing is inferred from them.
  ///
  /// Throws [ImportException] with a user-facing message for anything else,
  /// with specific messages for folders and for Docs/Slides/Forms.
  static String parseFileId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ImportException(ImportMessages.driveEmptyUrl);
    }

    final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        !_isGoogleHost(uri.host)) {
      throw const ImportException(ImportMessages.driveInvalidUrl);
    }

    final segments = uri.pathSegments;
    final host = uri.host.toLowerCase();

    if (segments.contains('folders')) {
      throw const ImportException(ImportMessages.driveFolderUrl);
    }
    if (host == 'docs.google.com' &&
        segments.isNotEmpty &&
        _unsupportedDocs.contains(segments.first)) {
      throw const ImportException(ImportMessages.driveGoogleDocUrl);
    }

    String? id;
    if (host == 'docs.google.com' &&
        segments.isNotEmpty &&
        segments.first == 'spreadsheets') {
      id = _segmentAfterD(segments, 0);
    } else {
      final fileIndex = segments.indexOf('file');
      if (fileIndex >= 0) id = _segmentAfterD(segments, fileIndex);
    }
    id ??= uri.queryParameters['id'];

    if (id == null || !_fileId.hasMatch(id)) {
      throw const ImportException(ImportMessages.driveInvalidUrl);
    }
    return id;
  }

  /// The only address the application downloads from:
  /// `https://docs.google.com/spreadsheets/d/{id}/export?format=xlsx`.
  ///
  /// It is the one public Google endpoint that is CORS-enabled for anonymous
  /// cross-site browser requests and returns the original bytes of an
  /// uploaded XLSX (or a converted XLSX for a native Google Sheet).
  static Uri exportUri(String fileId) => Uri.https(
    'docs.google.com',
    '/spreadsheets/d/$fileId/export',
    {'format': 'xlsx'},
  );

  static String? _segmentAfterD(List<String> segments, int from) {
    final d = segments.indexOf('d', from);
    return d >= 0 && d + 1 < segments.length ? segments[d + 1] : null;
  }

  static bool _isGoogleHost(String host) {
    final h = host.toLowerCase();
    return h == 'drive.google.com' ||
        h == 'docs.google.com' ||
        h == 'drive.usercontent.google.com';
  }
}
