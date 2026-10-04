// TEMPORARY DIAGNOSTICS. Picks the browser implementation on the web and a
// no-op everywhere else (VM tests).
export 'browser_event_observer_stub.dart'
    if (dart.library.js_interop) 'browser_event_observer_web.dart';
