import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart';

import 'storage_change_notice.dart';

export 'storage_change_notice.dart';

/// [BroadcastChannel] transport for [StorageChangeNotice] values.
///
/// A notice is a hint that another tab committed a revision. This class does
/// not read IndexedDB, compare revisions, or reload a session. The browser
/// does not deliver a message to the [BroadcastChannel] object that sent it.
/// Other objects on [channelName] receive it, including the sender id.
final class StorageChangeChannel {
  /// Opens the channel for [databaseName].
  ///
  /// The browser name comes from [storageChangeChannelName]. When
  /// `BroadcastChannel` throws, or [openChannel] throws or returns something
  /// other than a [BroadcastChannel], [isAvailable] stays false and later
  /// calls do not throw. [openChannel] is for tests. Production callers omit
  /// it.
  StorageChangeChannel({
    required this.databaseName,
    @visibleForTesting Object Function(String channelName)? openChannel,
  }) : channelName = storageChangeChannelName(databaseName) {
    _attach(openChannel ?? _browserChannel);
  }

  /// Database name supplied by the caller.
  final String databaseName;

  /// Browser channel name for [databaseName].
  final String channelName;

  BroadcastChannel? _browser;
  JSFunction? _onMessage;
  JSFunction? _onMessageError;
  void Function(StorageChangeNotice notice)? _listener;
  var _closed = false;
  var _available = false;

  /// Whether the browser channel is open.
  ///
  /// False when construction failed and after [close].
  bool get isAvailable => _available && !_closed;

  /// Sends [notice] as one JSON string.
  ///
  /// Returns false when this channel is unavailable, already closed, or
  /// `postMessage` throws. A false return does not describe the receiver.
  bool publish(StorageChangeNotice notice) {
    final browser = _browser;
    if (!_available || _closed || browser == null) return false;
    try {
      browser.postMessage(notice.toJsonText().toJS);
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Registers [onNotice] as the only listener.
  ///
  /// A later call replaces the previous callback. Invalid messages are
  /// ignored. Does nothing when [isAvailable] is false. The callback is not
  /// invoked for this object's own [publish].
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    if (!_available || _closed) return;
    _listener = onNotice;
  }

  /// Closes the browser channel and drops the listener.
  ///
  /// A second call does nothing. [publish] after this returns false, and a
  /// later browser event does not call the listener.
  void close() {
    if (_closed) return;
    _closed = true;
    _available = false;
    _listener = null;
    final browser = _browser;
    final onMessage = _onMessage;
    final onMessageError = _onMessageError;
    _browser = null;
    _onMessage = null;
    _onMessageError = null;
    if (browser != null) {
      try {
        browser.onmessage = null;
        browser.onmessageerror = null;
      } catch (_) {}
      try {
        browser.close();
      } catch (_) {}
    }
    // These locals keep the JS callbacks reachable until the handlers above
    // have been cleared.
    assert(onMessage == onMessage && onMessageError == onMessageError);
  }

  static Object _browserChannel(String channelName) =>
      BroadcastChannel(channelName);

  void _attach(Object Function(String channelName) openChannel) {
    BroadcastChannel? opened;
    try {
      final browser = openChannel(channelName) as BroadcastChannel;
      opened = browser;
      final onMessage = _handleMessage.toJS;
      final onMessageError = _ignoreMessageError.toJS;
      browser.onmessage = onMessage;
      browser.onmessageerror = onMessageError;
      _browser = browser;
      _onMessage = onMessage;
      _onMessageError = onMessageError;
      _available = true;
      assert(_onMessage != null && _onMessageError != null);
    } catch (_) {
      _available = false;
      _browser = null;
      _onMessage = null;
      _onMessageError = null;
      final failed = opened;
      if (failed == null) return;
      try {
        failed.onmessage = null;
        failed.onmessageerror = null;
        failed.close();
      } catch (_) {}
    }
  }

  void _handleMessage(Event event) {
    if (_closed) return;
    final listener = _listener;
    if (listener == null) return;
    try {
      if (!event.isA<MessageEvent>()) return;
      final data = (event as MessageEvent).data;
      if (!_isJsString(data)) return;
      final notice = StorageChangeNotice.tryParse((data as JSString).toDart);
      if (notice == null || _closed) return;
      listener(notice);
    } catch (_) {
      return;
    }
  }

  void _ignoreMessageError(Event _) {
    // A clone that the browser cannot deserialize has no notice to deliver.
  }
}

bool _isJsString(JSAny? data) {
  if (data == null) return false;
  if (data.isNull || data.isUndefined) return false;
  return data.isA<JSString>();
}
