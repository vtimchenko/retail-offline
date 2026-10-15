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

/// VM stand-in for [BrowserPageVisibility].
///
/// The browser library compiles instead of this file. This object never
/// calls the resume callback and does not keep it.
final class BrowserPageVisibility implements PageVisibility {
  var _closed = false;

  /// Whether a browser listener is attached.
  ///
  /// This library always returns false.
  @override
  bool get isAvailable => false;

  /// Discards [onResume].
  ///
  /// The callback is not retained and is not called.
  @override
  void listen(void Function() onResume) {}

  /// Marks this object closed.
  ///
  /// A second call does nothing.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
  }
}

/// Whether a `visibilitychange` should ask for a reload.
///
/// Only the literal `visible` state does. This function is duplicated in the
/// browser library.
bool resumesWhenVisible(String visibilityState) => visibilityState == 'visible';

/// Whether a `pageshow` should ask for a reload.
///
/// [persisted] is true when the page was restored from the back-forward
/// cache. An ordinary first load reports false. This function is duplicated
/// in the browser library.
bool resumesWhenRestored(bool persisted) => persisted;
