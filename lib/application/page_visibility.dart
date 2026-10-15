// Browser page-resume notifications behind a conditional export, so VM
// tests (which cannot compile `package:web`) keep working.
export 'page_visibility_stub.dart'
    if (dart.library.js_interop) 'page_visibility_web.dart';
