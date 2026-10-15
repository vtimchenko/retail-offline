import 'package:flutter/foundation.dart';

import 'storage_change_notice.dart';

export 'storage_change_notice.dart';

/// VM stand-in for the browser storage-change channel.
///
/// The browser library compiles instead of this file. This object reports
/// the channel as unavailable. It does not store notices or pass them to
/// another instance.
final class StorageChangeChannel {
  /// Creates a channel that never delivers.
  ///
  /// [databaseName] is validated by [storageChangeChannelName]. [openChannel]
  /// is accepted so this constructor matches the browser library. It is not
  /// called.
  StorageChangeChannel({
    required this.databaseName,
    @visibleForTesting Object Function(String channelName)? openChannel,
  }) : channelName = storageChangeChannelName(databaseName);

  /// Database name supplied by the caller.
  final String databaseName;

  /// Browser channel name for [databaseName].
  final String channelName;

  /// Whether a browser channel is open.
  ///
  /// This library always returns false.
  bool get isAvailable => false;

  /// Drops [notice].
  ///
  /// Returns false. No other instance observes the call.
  bool publish(StorageChangeNotice notice) => false;

  /// Discards [onNotice].
  ///
  /// The callback is not retained and is not called.
  void listen(void Function(StorageChangeNotice notice) onNotice) {}

  /// Marks the channel closed.
  ///
  /// A second call does nothing.
  void close() {}
}
