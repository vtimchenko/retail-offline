import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/persistence/browser/storage_change_channel.dart';

const _fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _senderId = 'tab-a';
const _maximumRevision = '9007199254740991';

void main() {
  group('StorageChangeNotice', () {
    test('round-trips a valid notice as JSON text', () {
      final notice = _notice(revision: '12');

      final parsed = StorageChangeNotice.tryParse(notice.toJsonText());

      expect(parsed, notice);
      expect(parsed!.version, '1');
      expect(parsed.revision, '12');
      expect(parsed.fingerprint, _fingerprint);
      expect(parsed.senderId, _senderId);
    });

    test('preserves decimal revision text, including the maximum', () {
      final notice = _notice(revision: _maximumRevision);

      expect(
        notice.toJsonText(),
        '{"version":"1","revision":"$_maximumRevision",'
        '"fingerprint":"$_fingerprint","senderId":"$_senderId"}',
      );
      expect(
        StorageChangeNotice.tryParse(notice.toJsonText())!.revision,
        _maximumRevision,
      );
    });

    test('rejects a revision above the safe integer range', () {
      expect(() => _notice(revision: '9007199254740992'), throwsArgumentError);
      expect(_parse(revision: '9007199254740992'), isNull);
      expect(_parse(revision: '90071992547409910'), isNull);
    });

    test('rejects revision text that is not a canonical decimal', () {
      for (final revision in ['', '0', '01', '1.0', '1e2', '-1', ' 1', '+1']) {
        expect(() => _notice(revision: revision), throwsArgumentError);
        expect(_parse(revision: revision), isNull);
      }
    });

    test('rejects a revision that is a JSON number', () {
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","revision":$_maximumRevision,'
          '"fingerprint":"$_fingerprint","senderId":"$_senderId"}',
        ),
        isNull,
      );
    });

    test('rejects an invalid fingerprint', () {
      for (final fingerprint in [
        '',
        'a' * 63,
        'a' * 65,
        'A' * 64,
        'g' * 64,
      ]) {
        expect(() => _notice(fingerprint: fingerprint), throwsArgumentError);
        expect(_parse(fingerprint: fingerprint), isNull);
      }
    });

    test('rejects an invalid sender id', () {
      for (final senderId in ['', 'A', '-tab', 'tab_a', 'a' * 65, 'tab a']) {
        expect(() => _notice(senderId: senderId), throwsArgumentError);
        expect(_parse(senderId: senderId), isNull);
      }
      final longest = StorageChangeNotice(
        revision: '1',
        fingerprint: _fingerprint,
        senderId: 'a' * 64,
      );
      expect(longest.senderId, 'a' * 64);
    });

    test('rejects an unsupported message version', () {
      expect(_parse(version: '2'), isNull);
      expect(_parse(version: '1 '), isNull);
      expect(
        StorageChangeNotice.tryParse(
          '{"version":1,"revision":"1",'
          '"fingerprint":"$_fingerprint","senderId":"$_senderId"}',
        ),
        isNull,
      );
    });

    test('rejects a missing field', () {
      expect(
        StorageChangeNotice.tryParse(
          '{"revision":"1","fingerprint":"$_fingerprint",'
          '"senderId":"$_senderId"}',
        ),
        isNull,
      );
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","fingerprint":"$_fingerprint",'
          '"senderId":"$_senderId"}',
        ),
        isNull,
      );
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","revision":"1","senderId":"$_senderId"}',
        ),
        isNull,
      );
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","revision":"1","fingerprint":"$_fingerprint"}',
        ),
        isNull,
      );
    });

    test('rejects an unexpected field', () {
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","revision":"1","fingerprint":"$_fingerprint",'
          '"senderId":"$_senderId","note":"x"}',
        ),
        isNull,
      );
    });

    test('rejects the wrong JSON shape', () {
      expect(StorageChangeNotice.tryParse(''), isNull);
      expect(StorageChangeNotice.tryParse('{'), isNull);
      expect(StorageChangeNotice.tryParse('null'), isNull);
      expect(StorageChangeNotice.tryParse('[]'), isNull);
      expect(StorageChangeNotice.tryParse('"1"'), isNull);
      expect(
        StorageChangeNotice.tryParse(
          '{"version":"1","revision":"1","fingerprint":true,'
          '"senderId":"$_senderId"}',
        ),
        isNull,
      );
    });

    test('equal notices share a hashCode', () {
      final first = _notice();
      final second = _notice();
      final other = _notice(senderId: 'tab-b');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect({first, second}, hasLength(1));
      expect(first, isNot(other));
    });
  });

  group('StorageChangeChannel stub', () {
    test('names the channel from the database name', () {
      final channel = StorageChangeChannel(databaseName: 'store-a');

      expect(channel.databaseName, 'store-a');
      expect(channel.channelName, 'retail-offline:store-a');
      expect(channel.isAvailable, isFalse);
    });

    test('rejects an empty database name', () {
      expect(() => StorageChangeChannel(databaseName: ''), throwsArgumentError);
    });

    test('does not deliver, including after repeated close', () {
      final first = StorageChangeChannel(databaseName: 'store-a');
      final second = StorageChangeChannel(databaseName: 'store-a');
      final received = <StorageChangeNotice>[];
      var openerCalls = 0;

      final ignored = StorageChangeChannel(
        databaseName: 'store-a',
        openChannel: (_) {
          openerCalls++;
          throw StateError('no browser');
        },
      );
      second.listen(received.add);
      first.listen(received.add);

      expect(first.publish(_notice()), isFalse);
      expect(second.publish(_notice()), isFalse);
      expect(received, isEmpty);
      expect(openerCalls, 0);
      expect(ignored.isAvailable, isFalse);

      first.close();
      first.close();
      second.listen(received.add);
      expect(first.publish(_notice()), isFalse);
      expect(first.isAvailable, isFalse);
      expect(received, isEmpty);

      ignored.close();
      ignored.close();
      second.close();
    });
  });
}

StorageChangeNotice _notice({
  String revision = '1',
  String fingerprint = _fingerprint,
  String senderId = _senderId,
}) {
  return StorageChangeNotice(
    revision: revision,
    fingerprint: fingerprint,
    senderId: senderId,
  );
}

StorageChangeNotice? _parse({
  String version = '1',
  String revision = '1',
  String fingerprint = _fingerprint,
  String senderId = _senderId,
}) {
  return StorageChangeNotice.tryParse(
    '{"version":"$version","revision":"$revision",'
    '"fingerprint":"$fingerprint","senderId":"$senderId"}',
  );
}
