// Browser-only XLSX picker behind a conditional export, so VM tests (which
// cannot compile `package:web`) keep working.
export 'xlsx_browser_picker_stub.dart'
    if (dart.library.js_interop) 'xlsx_browser_picker_web.dart';
