import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'xlsx_share_types.dart';

export 'xlsx_share_types.dart';

const String _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Shares [bytes] as [filename], or downloads them when this browser cannot
/// share a file.
///
/// Must be called directly from the button handler. [navigator.share] or
/// the download click runs before this function's first `await`.
///
/// Closing the share sheet returns [XlsxShareResult.cancelled] and does not
/// download. Pass files only: a `text` field makes older iOS reject the call.
Future<XlsxShareResult> shareOrDownloadXlsx({
  required String filename,
  required Uint8List bytes,
}) async {
  final file = File(
    <BlobPart>[bytes.toJS].toJS,
    filename,
    FilePropertyBag(type: _xlsxMime),
  );
  final data = ShareData(files: <File>[file].toJS);

  var canShare = false;
  try {
    canShare = window.navigator.canShare(data);
  } on Object {
    canShare = false;
  }

  if (!canShare) {
    _download(filename, bytes);
    return XlsxShareResult.downloaded;
  }

  try {
    await window.navigator.share(data).toDart;
    return XlsxShareResult.shared;
  } on Object catch (error) {
    if (_isAbort(error)) return XlsxShareResult.cancelled;
    _download(filename, bytes);
    return XlsxShareResult.downloaded;
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
/// Safari can start reading it.
void _download(String filename, Uint8List bytes) {
  final blob = Blob(
    <BlobPart>[bytes.toJS].toJS,
    BlobPropertyBag(type: _xlsxMime),
  );
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename;
  final body = document.body;
  if (body == null) {
    URL.revokeObjectURL(url);
    throw StateError('The document has no body to download into.');
  }
  body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => URL.revokeObjectURL(url));
}
