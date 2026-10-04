// Web-only picker options behind a conditional export, so VM tests (which
// cannot compile `package:file_picker_web`) keep working.
export 'web_picker_options_stub.dart'
    if (dart.library.js_interop) 'web_picker_options_web.dart';
