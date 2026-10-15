import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'export_share_types.dart';

export 'export_share_types.dart';

/// Shares [bytes] as [filename], or downloads them when this browser cannot
/// share the file.
///
/// Must be called directly from the button handler. `navigator.share` or
/// the download click runs before this function's first `await`.
///
/// [filename] and [bytes] are passed through unchanged, with
/// [jsonExportMimeType]. The payload contains files only: a `text` field
/// makes older iOS reject the call.
///
/// Closing the share sheet returns [ExportShareCancelled] and does not
/// download. A resolved share returns [ExportShareHandedOff]. A download
/// click returns [ExportShareDownloadStarted]. [ExportShareFailed] means
/// the click did not run.
Future<ExportShareResult> shareOrDownloadJson({
  required String filename,
  required Uint8List bytes,
}) async {
  final file = File(
    <BlobPart>[bytes.toJS].toJS,
    filename,
    FilePropertyBag(type: jsonExportMimeType),
  );
  final data = ShareData(files: <File>[file].toJS);

  var canShare = false;
  try {
    canShare = window.navigator.canShare(data);
  } on Object {
    canShare = false;
  }

  if (!canShare) {
    return _download(
      filename,
      bytes,
      ExportShareDownloadReason.sharingUnavailable,
    );
  }

  try {
    await window.navigator.share(data).toDart;
    return const ExportShareHandedOff();
  } on Object catch (error) {
    if (_isAbort(error)) return const ExportShareCancelled();
    return _download(filename, bytes, ExportShareDownloadReason.shareRejected);
  }
}

bool _isAbort(Object error) {
  if (error.isA<DOMException>()) {
    return (error as DOMException).name == 'AbortError';
  }
  return error.toString().contains('AbortError');
}

/// Saves [bytes] with the browser download attribute.
///
/// The anchor is attached for the click because a detached link does not
/// start a download in Safari. The object URL is revoked on a later turn so
/// Safari can start reading it. A failure revokes the URL immediately and
/// removes the anchor when it was attached.
ExportShareResult _download(
  String filename,
  Uint8List bytes,
  ExportShareDownloadReason reason,
) {
  String? url;
  HTMLAnchorElement? anchor;
  try {
    final blob = Blob(
      <BlobPart>[bytes.toJS].toJS,
      BlobPropertyBag(type: jsonExportMimeType),
    );
    url = URL.createObjectURL(blob);
    final element = HTMLAnchorElement()
      ..href = url
      ..download = filename;
    anchor = element;
    final body = document.body;
    if (body == null) {
      _revoke(url);
      url = null;
      return const ExportShareFailed();
    }
    body.appendChild(element);
    element.click();
    _remove(element);
    final objectUrl = url;
    Timer(const Duration(seconds: 1), () => _revoke(objectUrl));
    url = null;
    anchor = null;
    return ExportShareDownloadStarted(reason);
  } on Object {
    if (anchor != null) _remove(anchor);
    if (url != null) _revoke(url);
    return const ExportShareFailed();
  }
}

void _remove(HTMLAnchorElement anchor) {
  try {
    anchor.remove();
  } on Object {
    // The anchor was already detached.
  }
}

void _revoke(String url) {
  try {
    URL.revokeObjectURL(url);
  } on Object {
    // The URL was already revoked.
  }
}
