import 'dart:math';

import '../persistence/browser/storage_change_channel.dart';
import '../persistence/dataset_fingerprint.dart';
import '../persistence/fulfilment_repository.dart';
import '../services/json/cumulative_json_export.dart';
import 'fulfilment_application.dart';

final RegExp _senderIdPattern = RegExp(r'^[0-9a-z][0-9a-z-]*$');

/// Transport for one [StorageChangeNotice] stream.
///
/// [StorageChangeChannel] is the production implementation, behind
/// [ChannelStorageChangeTransport]. Tests supply a fake. This is not a
/// second place to store fulfilment data.
abstract interface class StorageChangeTransport {
  /// Whether [publish] can hand a notice to another instance.
  bool get isAvailable;

  /// Sends [notice]. Returns false when the transport cannot send it.
  ///
  /// A false return does not describe the receiver.
  bool publish(StorageChangeNotice notice);

  /// Registers [onNotice] as the only listener.
  ///
  /// A later call replaces the previous callback.
  void listen(void Function(StorageChangeNotice notice) onNotice);

  /// Releases the transport. A second call does nothing.
  void close();
}

/// [StorageChangeTransport] that delegates to one [StorageChangeChannel].
final class ChannelStorageChangeTransport implements StorageChangeTransport {
  /// Wraps [channel]. The caller owns no other copy of it.
  ChannelStorageChangeTransport(this._channel);

  final StorageChangeChannel _channel;

  @override
  bool get isAvailable => _channel.isAvailable;

  @override
  bool publish(StorageChangeNotice notice) => _channel.publish(notice);

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    _channel.listen(onNotice);
  }

  @override
  void close() {
    _channel.close();
  }
}

/// Publishes a [StorageChangeNotice] after each successful local commit.
///
/// The coordinator owns the transport and the sender id. [application] owns
/// the session. This type does not reload storage and does not retry a
/// command.
final class FulfilmentTabCoordinator {
  /// Creates [application] and connects its commit hook to this coordinator.
  ///
  /// [databaseName] is the IndexedDB name, and it is the name passed to
  /// [StorageChangeChannel] when [transport] is omitted. [senderId] replaces
  /// the generated id in tests. An id that [StorageChangeNotice] would
  /// reject throws [ArgumentError] before the application is created.
  factory FulfilmentTabCoordinator.open({
    required FulfilmentRepository repository,
    required String databaseName,
    DatasetByteRestore? datasets,
    CumulativeJsonExport? exports,
    StorageChangeTransport? transport,
    String? senderId,
  }) {
    final id = senderId ?? _generateSenderId(Random.secure());
    _checkSenderId(id);
    final StorageChangeTransport storage =
        transport ??
        ChannelStorageChangeTransport(
          StorageChangeChannel(databaseName: databaseName),
        );
    late FulfilmentTabCoordinator coordinator;
    final application = FulfilmentApplication(
      repository: repository,
      datasets: datasets,
      exports: exports,
      onCommitted: (revision, fingerprint) {
        coordinator._onCommitted(revision, fingerprint);
      },
    );
    coordinator = FulfilmentTabCoordinator._(
      application: application,
      transport: storage,
      senderId: id,
    );
    return coordinator;
  }

  FulfilmentTabCoordinator._({
    required this.application,
    required this._transport,
    required this.senderId,
  });

  /// Session service created with this coordinator.
  final FulfilmentApplication application;

  /// Sender written into notices from this instance.
  ///
  /// Generated ids are 32 lowercase hexadecimal characters. The value is not
  /// stored.
  final String senderId;

  final StorageChangeTransport _transport;
  var _closed = false;

  /// Whether [close] has run.
  bool get isClosed => _closed;

  /// Closes the transport.
  ///
  /// A second call does nothing. The application and its repository stay
  /// open. Later commits do not publish.
  void close() {
    if (_closed) return;
    _closed = true;
    _transport.close();
  }

  void _onCommitted(String revision, String fingerprint) {
    if (_closed) return;
    try {
      _transport.publish(
        StorageChangeNotice(
          revision: revision,
          fingerprint: fingerprint,
          senderId: senderId,
        ),
      );
    } on Object {
      // The commit already succeeded. Publishing cannot change it.
    }
  }
}

String _generateSenderId(Random random) {
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _checkSenderId(String senderId) {
  if (senderId.length > 64 || !_senderIdPattern.hasMatch(senderId)) {
    throw ArgumentError.value(
      senderId,
      'senderId',
      'Must be 1 to 64 characters of lowercase letters, digits, or hyphens.',
    );
  }
}
