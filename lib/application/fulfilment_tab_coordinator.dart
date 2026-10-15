import 'dart:async';
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

/// Publishes a [StorageChangeNotice] after each successful local commit and
/// reloads [application] when a remote notice says storage may be ahead.
///
/// The coordinator owns the transport and the sender id. [application] owns
/// the session. A notice is not copied into the session. A failed command is
/// not run again.
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
    storage.listen(coordinator._onRemote);
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
  var _active = false;
  var _startScheduled = false;
  var _pending = false;
  var _nextId = 0;
  int? _inflightId;
  StorageChangeNotice? _target;
  StorageChangeNotice? _queuedNotice;
  String? _mismatchCheckedRevision;
  String? _unresolvedRevision;
  final Map<int, List<Completer<LoadResult>>> _waiters = {};

  /// Whether [close] has run.
  bool get isClosed => _closed;

  /// Reads storage through [application].
  ///
  /// The result belongs to a load that starts after this call, or to a load
  /// that is already scheduled and has not started. A load that is already
  /// waiting on storage is left to its own caller.
  ///
  /// After [close], the future completes with a [StateError]. A request that
  /// was waiting for a load that had not started also completes with that
  /// error. A load that had already started still returns its [LoadResult].
  Future<LoadResult> reload() {
    if (_closed) return Future<LoadResult>.error(_closedError());
    final completer = Completer<LoadResult>();
    (_waiters[_nextId] ??= <Completer<LoadResult>>[]).add(completer);
    if (_active) {
      _pending = true;
    } else {
      _schedule();
    }
    return completer.future;
  }

  /// Closes the transport and refuses later reloads.
  ///
  /// A second call does nothing. The application and its repository stay
  /// open. An in-flight [reload] is allowed to finish, and no follow-up
  /// starts. A throw from the transport is ignored; this coordinator is
  /// already closed.
  void close() {
    if (_closed) return;
    _closed = true;
    _pending = false;
    _target = null;
    _queuedNotice = null;
    try {
      _transport.close();
    } on Object {
      // Later commits and notices are already ignored.
    }
    _rejectUnstarted(_closedError());
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

  void _onRemote(StorageChangeNotice notice) {
    if (_closed || notice.senderId == senderId) return;
    if (!_accepts(notice)) return;
    if (_active) {
      _queuedNotice = _preferNewer(_queuedNotice, notice);
      _pending = true;
      return;
    }
    _target = _preferNewer(_target, notice);
    _schedule();
  }

  /// Whether [notice] is newer than memory, or an unchecked fingerprint
  /// mismatch at the same revision.
  bool _accepts(StorageChangeNotice notice) {
    final local = application.revision?.toString();
    if (local == null || _compareRevision(notice.revision, local) > 0) {
      final ceiling = _unresolvedRevision;
      if (ceiling != null && _compareRevision(notice.revision, ceiling) <= 0) {
        return false;
      }
      return true;
    }
    if (_compareRevision(notice.revision, local) < 0) return false;
    if (notice.fingerprint == application.fingerprint) return false;
    return _mismatchCheckedRevision != local;
  }

  void _schedule() {
    if (_closed || _active || _startScheduled) return;
    _startScheduled = true;
    scheduleMicrotask(_startDrain);
  }

  void _startDrain() {
    _startScheduled = false;
    if (_closed || _active) return;
    if (_target == null && _waiters.isEmpty) return;
    _active = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (!_closed) {
        _pending = false;
        final trigger = _target;
        _target = null;
        final startId = _nextId++;
        _inflightId = startId;
        final LoadResult result;
        try {
          result = await application.reload();
        } on Object catch (error, stackTrace) {
          _inflightId = null;
          _fail(startId, error, stackTrace);
          if (_closed) return;
          _pending = false;
          _queuedNotice = null;
          _target = null;
          return;
        }
        _inflightId = null;
        _complete(startId, result);
        if (_closed) return;
        if (result is! LoadReady && result is! LoadEmpty) {
          _pending = false;
          _queuedNotice = null;
          _target = null;
          return;
        }
        _remember(result, trigger);
        if (_queuedNotice != null) {
          _target = _preferNewer(_target, _queuedNotice!);
          _queuedNotice = null;
          _pending = true;
        }
        if (!_pending) return;
      }
    } finally {
      _active = false;
      _inflightId = null;
      if (!_closed && (_waiters.isNotEmpty || _target != null)) {
        _schedule();
      }
    }
  }

  void _remember(LoadResult result, StorageChangeNotice? trigger) {
    if (result is LoadEmpty) {
      _mismatchCheckedRevision = null;
      if (trigger == null) {
        _unresolvedRevision = null;
      } else {
        _unresolvedRevision = _maxRevision(
          _unresolvedRevision,
          trigger.revision,
        );
      }
      return;
    }
    if (result is! LoadReady) return;
    final local = application.revision!.toString();
    if (trigger == null) {
      if (_unresolvedRevision != null &&
          _compareRevision(local, _unresolvedRevision!) >= 0) {
        _unresolvedRevision = null;
      }
      if (_mismatchCheckedRevision != null &&
          _mismatchCheckedRevision != local) {
        _mismatchCheckedRevision = null;
      }
      return;
    }
    if (_compareRevision(trigger.revision, local) > 0) {
      _unresolvedRevision = _maxRevision(_unresolvedRevision, trigger.revision);
      return;
    }
    _unresolvedRevision = null;
    if (trigger.revision == local &&
        trigger.fingerprint != application.fingerprint) {
      _mismatchCheckedRevision = local;
    } else if (_mismatchCheckedRevision != local) {
      _mismatchCheckedRevision = null;
    }
  }

  void _complete(int startId, LoadResult result) {
    final waiting = _waiters.remove(startId);
    if (waiting == null) return;
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete(result);
    }
  }

  void _fail(int startId, Object error, StackTrace stackTrace) {
    final waiting = _waiters.remove(startId);
    if (waiting == null) return;
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
    }
  }

  void _rejectUnstarted(StateError error) {
    final inflight = _inflightId;
    final pending = Map<int, List<Completer<LoadResult>>>.of(_waiters);
    for (final entry in pending.entries) {
      if (entry.key == inflight) continue;
      _waiters.remove(entry.key);
      for (final waiter in entry.value) {
        if (!waiter.isCompleted) waiter.completeError(error);
      }
    }
  }
}

StorageChangeNotice _preferNewer(
  StorageChangeNotice? current,
  StorageChangeNotice incoming,
) {
  if (current == null) return incoming;
  final order = _compareRevision(incoming.revision, current.revision);
  if (order >= 0) return incoming;
  return current;
}

String _maxRevision(String? current, String incoming) {
  if (current == null || _compareRevision(incoming, current) > 0) {
    return incoming;
  }
  return current;
}

/// Longer canonical decimal text is greater. Equal lengths use code-unit
/// order, which matches numeric order when there are no leading zeros.
int _compareRevision(String left, String right) {
  if (left.length != right.length) return left.length.compareTo(right.length);
  return left.compareTo(right);
}

StateError _closedError() => StateError('FulfilmentTabCoordinator is closed.');

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
