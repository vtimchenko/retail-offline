// Browser JSON sharing behind a conditional export, so VM tests (which
// cannot compile `package:web`) keep working.
export 'export_share_stub.dart'
    if (dart.library.js_interop) 'export_share_web.dart';
