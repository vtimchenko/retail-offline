import 'dart:js_interop';

import 'package:web/web.dart';

/// Notifies when a tab or installed app returns to the foreground.
///
/// The callback is a request to read storage again. It does not describe a
/// revision. This is not a second place to store fulfilment data.
abstract interface class PageVisibility {
  /// Whether [listen] can deliver a resume.
  bool get isAvailable;

  /// Registers [onResume] as the only resume callback.
  ///
  /// A later call replaces the previous callback. Registration itself does
  /// not call it.
  void listen(void Function() onResume);

  /// Stops resume notifications. A second call does nothing.
  void close();
}

/// Listens for a document becoming visible and for a restored `pageshow`.
///
/// Hiding the document does not notify. An ordinary `pageshow` whose
/// persisted flag is false does not notify. Attaching the listeners does not
/// read the current visibility.
final class BrowserPageVisibility implements PageVisibility {
  /// Attaches the document and window listeners.
  ///
  /// When the browser throws, [isAvailable] stays false and later calls do
  /// not throw.
  BrowserPageVisibility() {
    _attach();
  }

  JSFunction? _onVisibility;
  JSFunction? _onPageShow;
  void Function()? _onResume;
  var _closed = false;
  var _available = false;

  /// Whether both listeners are attached.
  ///
  /// False when construction failed and after [close].
  @override
  bool get isAvailable => _available && !_closed;

  /// Stores [onResume].
  ///
  /// Does nothing when [isAvailable] is false. Does not call [onResume].
  @override
  void listen(void Function() onResume) {
    if (!_available || _closed) return;
    _onResume = onResume;
  }

  /// Removes both listeners and drops the callback.
  ///
  /// A second call does nothing. A later browser event does not call the
  /// callback.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _available = false;
    _onResume = null;
    final onVisibility = _onVisibility;
    final onPageShow = _onPageShow;
    _onVisibility = null;
    _onPageShow = null;
    _remove('visibilitychange', onVisibility, () => document);
    _remove('pageshow', onPageShow, () => window);
  }

  void _attach() {
    JSFunction? onVisibility;
    JSFunction? onPageShow;
    try {
      onVisibility = _handleVisibility.toJS;
      onPageShow = _handlePageShow.toJS;
      document.addEventListener('visibilitychange', onVisibility);
      window.addEventListener('pageshow', onPageShow);
      _onVisibility = onVisibility;
      _onPageShow = onPageShow;
      _available = true;
    } catch (_) {
      _available = false;
      _onVisibility = null;
      _onPageShow = null;
      _remove('visibilitychange', onVisibility, () => document);
      _remove('pageshow', onPageShow, () => window);
    }
  }

  void _handleVisibility(Event _) {
    if (_closed) return;
    final notify = _onResume;
    if (notify == null) return;
    try {
      if (!resumesWhenVisible(document.visibilityState)) return;
    } catch (_) {
      return;
    }
    _notify(notify);
  }

  void _handlePageShow(Event event) {
    if (_closed) return;
    final notify = _onResume;
    if (notify == null) return;
    try {
      if (!event.isA<PageTransitionEvent>()) return;
      if (!resumesWhenRestored((event as PageTransitionEvent).persisted)) {
        return;
      }
    } catch (_) {
      return;
    }
    _notify(notify);
  }

  void _notify(void Function() notify) {
    try {
      notify();
    } catch (_) {
      // The coordinator already decided whether to reload.
    }
  }

  void _remove(
    String type,
    JSFunction? listener,
    EventTarget Function() target,
  ) {
    if (listener == null) return;
    try {
      target().removeEventListener(type, listener);
    } catch (_) {}
  }
}

/// Whether a `visibilitychange` should ask for a reload.
///
/// Only the literal `visible` state does. This function is duplicated in the
/// VM library.
bool resumesWhenVisible(String visibilityState) => visibilityState == 'visible';

/// Whether a `pageshow` should ask for a reload.
///
/// [persisted] is true when the page was restored from the back-forward
/// cache. An ordinary first load reports false. This function is duplicated
/// in the VM library.
bool resumesWhenRestored(bool persisted) => persisted;
