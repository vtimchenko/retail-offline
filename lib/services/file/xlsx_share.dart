// Browser file sharing behind a conditional export, so VM tests (which
// cannot compile `package:web`) keep working.
export 'xlsx_share_stub.dart'
    if (dart.library.js_interop) 'xlsx_share_web.dart';
