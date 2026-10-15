@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/persistence/browser/storage_change_channel.dart';
import 'package:web/web.dart';

/// Chrome checks for [StorageChangeChannel].
///
/// Two objects in this page exercise the same BroadcastChannel path as two
/// tabs. A passing run does not establish Safari or installed-PWA behavior.

const _fingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _revision = '9007199254740991';

void main() {
  var sequence = 0;
  late String databaseName;
  final channels = <StorageChangeChannel>[];
  final rawChannels = <BroadcastChannel>[];

  setUp(() {
    sequence += 1;
    databaseName =
        'retail-offline-test-channel-$sequence-'
        '${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() {
    for (final channel in channels) {
      channel.close();
    }
    channels.clear();
    for (final raw in rawChannels) {
      raw.close();
    }
    rawChannels.clear();
  });

  test('a constructed channel is available until close', () {
    final channel = _open(channels, databaseName);

    expect(channel.isAvailable, isTrue);
    expect(channel.databaseName, databaseName);
    expect(channel.channelName, 'retail-offline:$databaseName');

    channel.close();
    channel.close();

    expect(channel.isAvailable, isFalse);
  });

  test('an empty database name is rejected before the browser opens', () {
    var opened = 0;

    expect(
      () => StorageChangeChannel(
        databaseName: '',
        openChannel: (_) {
          opened++;
          throw StateError('should not open');
        },
      ),
      throwsArgumentError,
    );
    expect(opened, 0);
  });

  test('delivers one notice with its exact fields', () async {
    final sender = _open(channels, databaseName);
    final receiver = _open(channels, databaseName);
    final echoed = <StorageChangeNotice>[];
    final delivered = _listenOne(receiver);
    sender.listen(echoed.add);

    final notice = _notice(senderId: 'left-tab');
    expect(sender.isAvailable, isTrue);
    expect(sender.publish(notice), isTrue);

    final received = await delivered.future;
    expect(received, notice);
    expect(received.version, '1');
    expect(received.revision, _revision);
    expect(received.fingerprint, _fingerprint);
    expect(received.senderId, 'left-tab');
    expect(echoed, isEmpty);
  });

  test(
    'the sending BroadcastChannel does not receive its own notice',
    () async {
      final sender = _open(channels, databaseName);
      final receiver = _open(channels, databaseName);
      final echoed = <StorageChangeNotice>[];
      final delivered = _listenOne(receiver);
      sender.listen(echoed.add);

      expect(sender.publish(_notice()), isTrue);

      await delivered.future;
      expect(echoed, isEmpty);
    },
  );

  test('delivers the same notice again', () async {
    final sender = _open(channels, databaseName);
    final receiver = _open(channels, databaseName);
    final received = <StorageChangeNotice>[];
    final done = _listenCount(receiver, received, 2);
    final notice = _notice();

    expect(sender.publish(notice), isTrue);
    expect(sender.publish(notice), isTrue);

    await done.future;
    expect(received, [notice, notice]);
  });

  test('a different database name receives nothing', () async {
    final sender = _open(channels, databaseName);
    final other = _open(channels, '$databaseName-other');
    final peer = _open(channels, databaseName);
    final otherReceived = <StorageChangeNotice>[];
    final delivered = _listenOne(peer);
    other.listen(otherReceived.add);

    final notice = _notice(senderId: 'left-tab');
    expect(sender.publish(notice), isTrue);

    expect(await delivered.future, notice);
    expect(otherReceived, isEmpty);
    expect(other.channelName, isNot(sender.channelName));
  });

  test(
    'drops invalid messages and still delivers a later valid notice',
    () async {
      final sender = _open(channels, databaseName);
      final receiver = _open(channels, databaseName);
      final received = <StorageChangeNotice>[];
      final delivered = _listenOne(receiver, received);
      final raw = BroadcastChannel(sender.channelName);
      rawChannels.add(raw);

      raw.postMessage('not-json'.toJS);
      raw.postMessage(1.toJS);
      raw.postMessage(
        '{"version":"9","revision":"1","fingerprint":"$_fingerprint",'
                '"senderId":"tab-a"}'
            .toJS,
      );
      raw.postMessage(
        '{"version":"1","revision":$_revision,"fingerprint":"$_fingerprint",'
                '"senderId":"tab-a"}'
            .toJS,
      );
      raw.postMessage(
        '{"version":"1","revision":"1","fingerprint":"$_fingerprint",'
                '"senderId":"tab-a","note":"x"}'
            .toJS,
      );
      final notice = _notice();
      expect(sender.publish(notice), isTrue);

      expect(await delivered.future, notice);
      expect(received, [notice]);
    },
  );

  test('a closed receiver does not get a later notice', () async {
    final sender = _open(channels, databaseName);
    final receiver = _open(channels, databaseName);
    final probe = _open(channels, databaseName);
    final received = <StorageChangeNotice>[];
    final seenByProbe = <StorageChangeNotice>[];
    final done = _listenCount(probe, seenByProbe, 2);
    receiver.listen(received.add);
    receiver.close();

    final first = _notice(senderId: 'closed-receiver');
    final second = _notice(senderId: 'probe');
    expect(sender.publish(first), isTrue);
    expect(sender.publish(second), isTrue);

    await done.future;
    expect(seenByProbe, [first, second]);
    expect(received, isEmpty);
  });

  test('publish after close returns false and sends nothing', () async {
    final sender = _open(channels, databaseName);
    final receiver = _open(channels, databaseName);
    final announcer = _open(channels, databaseName);
    final received = <StorageChangeNotice>[];
    final delivered = _listenOne(receiver, received);
    sender.close();
    sender.close();

    expect(sender.isAvailable, isFalse);
    expect(sender.publish(_notice(senderId: 'after-close')), isFalse);
    final probeNotice = _notice(senderId: 'probe');
    expect(announcer.publish(probeNotice), isTrue);

    expect(await delivered.future, probeNotice);
    expect(received, [probeNotice]);
  });

  test('a failed open stays unavailable', () {
    final thrown = StorageChangeChannel(
      databaseName: databaseName,
      openChannel: (_) => throw StateError('BroadcastChannel missing'),
    );
    channels.add(thrown);
    final foreign = StorageChangeChannel(
      databaseName: databaseName,
      openChannel: (_) => Object(),
    );
    channels.add(foreign);
    final received = <StorageChangeNotice>[];

    expect(thrown.isAvailable, isFalse);
    expect(foreign.isAvailable, isFalse);
    thrown.listen(received.add);
    foreign.listen(received.add);
    expect(thrown.publish(_notice()), isFalse);
    expect(foreign.publish(_notice()), isFalse);
    expect(received, isEmpty);

    thrown.close();
    thrown.close();
    foreign.close();
    expect(thrown.isAvailable, isFalse);
    expect(thrown.publish(_notice()), isFalse);
  });
}

StorageChangeChannel _open(List<StorageChangeChannel> channels, String name) {
  final channel = StorageChangeChannel(databaseName: name);
  channels.add(channel);
  return channel;
}

StorageChangeNotice _notice({String senderId = 'tab-a'}) {
  return StorageChangeNotice(
    revision: _revision,
    fingerprint: _fingerprint,
    senderId: senderId,
  );
}

Completer<StorageChangeNotice> _listenOne(
  StorageChangeChannel channel, [
  List<StorageChangeNotice>? received,
]) {
  final done = Completer<StorageChangeNotice>();
  channel.listen((notice) {
    received?.add(notice);
    if (!done.isCompleted) done.complete(notice);
  });
  return done;
}

Completer<void> _listenCount(
  StorageChangeChannel channel,
  List<StorageChangeNotice> received,
  int count,
) {
  final done = Completer<void>();
  channel.listen((notice) {
    received.add(notice);
    if (received.length == count && !done.isCompleted) done.complete();
  });
  return done;
}
