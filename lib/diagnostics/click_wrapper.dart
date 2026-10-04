// TEMPORARY A/B DIAGNOSTICS (iOS local file picker). Delete the whole
// `lib/diagnostics/` folder when the investigation is over.
//
// Web: wraps `HTMLInputElement.prototype.click`. Everywhere else: a no-op.
export 'click_wrapper_stub.dart'
    if (dart.library.js_interop) 'click_wrapper_web.dart';
