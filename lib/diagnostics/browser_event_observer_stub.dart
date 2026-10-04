// TEMPORARY DIAGNOSTICS - non-web no-op.

/// Browser-level observer; does nothing outside the web.
class BrowserEventObserver {
  void start(void Function(String message) log) {
    log('browser observer: not available on this platform');
  }

  void stop() {}
}
