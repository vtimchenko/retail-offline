import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/import_messages.dart';
import '../../core/errors/import_exception.dart';
import '../../models/imported_file.dart';
import 'google_drive_url.dart';

/// Downloads a PUBLIC Google Drive file or Google Sheet as XLSX directly from
/// the browser.
///
/// No OAuth, no API key, no proxy, no backend. The single request is
/// `GET https://docs.google.com/spreadsheets/d/{id}/export?format=xlsx`
/// ([GoogleDriveUrl.exportUri]). Checked in a real browser, it is the public
/// Google endpoint that answers anonymous cross-site requests with CORS
/// headers: for an uploaded XLSX it returns the original bytes, for a native
/// Google Sheet a converted workbook. `drive.usercontent.google.com/download`
/// is deliberately not used: Google refuses it with a header-less 403 for any
/// request marked `Sec-Fetch-Site: cross-site`, which a browser cannot avoid.
///
/// The response is never trusted by status alone: it must be a ZIP container.
/// A CORS or network failure, a timeout, a non-200 status, a sign-in or
/// permission page (HTML) and non-XLSX content all surface as one
/// [ImportException] telling the user to download the file and choose it
/// locally. The rest of the application only sees an [ImportedFile].
class GoogleDriveFileService {
  GoogleDriveFileService({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Downloads the file behind the share link [url].
  Future<ImportedFile> download(String url) async {
    final id = GoogleDriveUrl.parseFileId(url);
    final uri = GoogleDriveUrl.exportUri(id);

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on Object catch (e) {
      // In the browser a CORS block, a network error, a sign-in redirect
      // without CORS headers and a timeout all look like a failed fetch.
      debugPrint('Google export request failed (CORS/network/timeout?): $e');
      throw ImportException(
        ImportMessages.driveDownloadBlocked,
        technical: 'Request to $uri failed',
        cause: e,
      );
    }

    if (response.statusCode != 200) {
      debugPrint('Google export HTTP ${response.statusCode} for $uri');
      throw ImportException(
        ImportMessages.driveDownloadBlocked,
        technical: 'HTTP ${response.statusCode}',
      );
    }

    final bytes = response.bodyBytes;
    if (!_looksLikeZip(bytes)) {
      debugPrint(
        'Google export returned non-XLSX content '
        '(${response.headers['content-type']}, ${bytes.length} B)',
      );
      throw ImportException(
        ImportMessages.driveDownloadBlocked,
        technical: _looksLikeHtml(bytes)
            ? 'HTML page (sign-in/permission) instead of a file'
            : 'Response is not a ZIP/XLSX',
      );
    }

    return ImportedFile(
      name: _fileName(response.headers['content-disposition']) ?? '$id.xlsx',
      bytes: bytes,
      source: FileSource.googleDrive,
    );
  }

  void close() => _client.close();

  /// Local-file-header signature `PK\x03\x04` of a non-empty ZIP archive.
  static bool _looksLikeZip(Uint8List b) =>
      b.length >= 4 &&
      b[0] == 0x50 &&
      b[1] == 0x4B &&
      b[2] == 0x03 &&
      b[3] == 0x04;

  static bool _looksLikeHtml(Uint8List b) {
    final head = String.fromCharCodes(b.take(256)).trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }

  /// `attachment; filename="a.xlsx"; filename*=UTF-8''a.xlsx` → `a.xlsx`.
  /// `filename*` wins over `filename`. Returns null when the header is absent
  /// (Google may not expose it), unparsable or empty — the name is never
  /// required for a successful import.
  static String? _fileName(String? contentDisposition) {
    if (contentDisposition == null) return null;
    final encoded = RegExp(
      r"filename\*\s*=\s*UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    if (encoded != null) {
      try {
        final name = Uri.decodeComponent(encoded.group(1)!.trim()).trim();
        if (name.isNotEmpty) return name;
      } on Object {
        // fall through to the plain filename
      }
    }
    final plain = RegExp(
      r'filename\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    final name = plain?.group(1)?.trim();
    return name == null || name.isEmpty ? null : name;
  }
}
