import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';

/// Synthetic catalogue only. No real customers, phones, or products.
const bigProductId = '1290564103789190763';
const largeOrderNumber = '9007199254740993';

const _emptySha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const _abcSha256 =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
const _longSha256 =
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1';

const _compactDataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$bigProductId,"SerialNumber":"SN-0001","Quantity":1}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":$largeOrderNumber,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$bigProductId,"Quantity":1,'
    '"Price":324.50,"Amount":324.50,"isServiceGood":0,"isParcel":0}]}]}';

void main() {
  const reader = DatasetByteRestore();

  group('sha256', () {
    test('matches known test vectors', () {
      expect(DatasetFingerprint.of(Uint8List(0)), _emptySha256);
      expect(
        DatasetFingerprint.of(Uint8List.fromList(const [0x61, 0x62, 0x63])),
        _abcSha256,
      );
      expect(
        DatasetFingerprint.of(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
        _longSha256,
      );
    });

    test('is deterministic for the same bytes', () {
      final first = Uint8List.fromList(const [0x61, 0x62, 0x63]);
      final second = Uint8List.fromList(const [0x61, 0x62, 0x63]);

      expect(DatasetFingerprint.of(first), DatasetFingerprint.of(first));
      expect(DatasetFingerprint.of(first), DatasetFingerprint.of(second));
      expect(DatasetFingerprint.matches(second, _abcSha256), isTrue);
    });

    test('changes when any byte changes', () {
      final original = utf8.encode('abc');
      final changed = Uint8List.fromList(original)..[2] = 0x64;

      expect(
        DatasetFingerprint.of(original),
        isNot(DatasetFingerprint.of(changed)),
      );
      expect(DatasetFingerprint.of(changed), isNot(_abcSha256));
    });

    test('whitespace in the original bytes changes the fingerprint', () {
      final compact = utf8.encode(_compactDataset);
      final spaced = utf8.encode(_compactDataset.replaceFirst('{', '{ '));
      final trailingName = utf8.encode(
        _compactDataset.replaceFirst('"Магазин Тест"', '"Магазин Тест "'),
      );

      expect(
        DatasetFingerprint.of(compact),
        isNot(DatasetFingerprint.of(spaced)),
      );
      expect(
        DatasetFingerprint.of(compact),
        isNot(DatasetFingerprint.of(trailingName)),
      );
    });

    test('returns lowercase hex and rejects other forms', () {
      final fingerprint = DatasetFingerprint.of(utf8.encode('abc'));

      expect(fingerprint, hasLength(DatasetFingerprint.hexLength));
      expect(DatasetFingerprint.hasValidFormat(fingerprint), isTrue);
      expect(fingerprint, fingerprint.toLowerCase());
      expect(fingerprint, isNot(contains(RegExp('[A-Z]'))));

      expect(
        DatasetFingerprint.hasValidFormat(fingerprint.toUpperCase()),
        isFalse,
      );
      expect(
        DatasetFingerprint.hasValidFormat(fingerprint.substring(1)),
        isFalse,
      );
      expect(DatasetFingerprint.hasValidFormat('${fingerprint}0'), isFalse);
      expect(DatasetFingerprint.hasValidFormat('$fingerprint '), isFalse);
      expect(DatasetFingerprint.hasValidFormat(''), isFalse);
      expect(
        DatasetFingerprint.hasValidFormat(fingerprint.replaceFirst('a', 'g')),
        isFalse,
      );
      expect(
        DatasetFingerprint.matches(
          utf8.encode('abc'),
          fingerprint.toUpperCase(),
        ),
        isFalse,
      );
      expect(DatasetFingerprint.matches(utf8.encode('abc'), 'abc'), isFalse);
    });

    test('uses the same format as a session snapshot fingerprint', () {
      final fingerprint = DatasetFingerprint.of(Uint8List(0));

      expect(
        SessionSnapshot.hasFingerprintFormat(fingerprint),
        DatasetFingerprint.hasValidFormat(fingerprint),
      );
      expect(
        SessionSnapshot.hasFingerprintFormat(fingerprint.toUpperCase()),
        DatasetFingerprint.hasValidFormat(fingerprint.toUpperCase()),
      );
      expect(
        SessionSnapshot.hasFingerprintFormat('abc'),
        DatasetFingerprint.hasValidFormat('abc'),
      );
    });
  });

  group('restore', () {
    test('restores a valid dataset and keeps a 19-digit product id', () {
      final bytes = utf8.encode(_compactDataset);
      final fingerprint = DatasetFingerprint.of(bytes);
      final restored = accepted(
        reader.restore(bytes: bytes, expectedFingerprint: fingerprint),
      );

      expect(restored.fingerprint, fingerprint);
      expect(restored.dataset.storeName, 'Магазин Тест');
      expect(restored.dataset.dbName, 'Store_01-A');
      expect(restored.dataset.stocks.single.productId.literal, bigProductId);
      expect(restored.dataset.stocks.single.productId.literal, hasLength(19));
      expect(
        restored.dataset.orders.single.goods.single.productId.literal,
        bigProductId,
      );
      expect(
        restored.dataset.orders.single.orderNumber.literal,
        largeOrderNumber,
      );
    });

    test('different whitespace still parses when each fingerprint matches', () {
      final compact = utf8.encode(_compactDataset);
      final spaced = utf8.encode(_compactDataset.replaceFirst('{', '{ '));
      final compactDataset = accepted(
        reader.restore(
          bytes: compact,
          expectedFingerprint: DatasetFingerprint.of(compact),
        ),
      ).dataset;
      final spacedDataset = accepted(
        reader.restore(
          bytes: spaced,
          expectedFingerprint: DatasetFingerprint.of(spaced),
        ),
      ).dataset;

      expect(
        DatasetFingerprint.of(compact),
        isNot(DatasetFingerprint.of(spaced)),
      );
      expect(spacedDataset.stocks.single.productId.literal, bigProductId);
      expect(spacedDataset, compactDataset);
    });

    test('a trimmed store name does not change the hashed bytes', () {
      final original = utf8.encode(_compactDataset);
      final padded = utf8.encode(
        _compactDataset.replaceFirst('"Магазин Тест"', '"Магазин Тест "'),
      );
      final originalDataset = accepted(
        reader.restore(
          bytes: original,
          expectedFingerprint: DatasetFingerprint.of(original),
        ),
      ).dataset;
      final paddedDataset = accepted(
        reader.restore(
          bytes: padded,
          expectedFingerprint: DatasetFingerprint.of(padded),
        ),
      ).dataset;

      expect(
        DatasetFingerprint.of(original),
        isNot(DatasetFingerprint.of(padded)),
      );
      expect(paddedDataset.storeName, originalDataset.storeName);
      expect(paddedDataset.stocks.single.productId.literal, bigProductId);
    });

    test('rejects an invalid fingerprint before comparing the hash', () {
      final bytes = utf8.encode(_compactDataset);

      expect(
        reason(reader.restore(bytes: bytes, expectedFingerprint: 'ABC')),
        DatasetRestoreReason.invalidFingerprint,
      );
      expect(
        reason(
          reader.restore(
            bytes: Uint8List.fromList(const [0xFF]),
            expectedFingerprint: 'nope',
          ),
        ),
        DatasetRestoreReason.invalidFingerprint,
      );
    });

    test('rejects a fingerprint mismatch without decoding', () {
      final bytes = utf8.encode(_compactDataset);
      final rejected = rejection(
        reader.restore(bytes: bytes, expectedFingerprint: _emptySha256),
      );

      expect(rejected.reason, DatasetRestoreReason.fingerprintMismatch);
      expect(rejected.message, isNull);
      expect(
        reason(
          reader.restore(
            bytes: Uint8List.fromList(const [0xFF]),
            expectedFingerprint: _emptySha256,
          ),
        ),
        DatasetRestoreReason.fingerprintMismatch,
      );
    });

    test('rejects malformed utf-8 after the fingerprint matches', () {
      final bytes = Uint8List.fromList(const [0x61, 0xC3, 0x28]);
      final rejected = rejection(
        reader.restore(
          bytes: bytes,
          expectedFingerprint: DatasetFingerprint.of(bytes),
        ),
      );

      expect(rejected.reason, DatasetRestoreReason.malformedUtf8);
      expect(rejected.message, isNull);
    });

    test('rejects malformed json', () {
      final bytes = utf8.encode('{');
      final rejected = rejection(
        reader.restore(
          bytes: bytes,
          expectedFingerprint: DatasetFingerprint.of(bytes),
        ),
      );

      expect(rejected.reason, DatasetRestoreReason.malformedJson);
      expect(rejected.message, isNotNull);
      expect(rejected.message, isNot(contains('{')));
    });

    test('rejects a dataset the parser does not accept', () {
      final source = _compactDataset.replaceFirst(
        '"stocks":[',
        '"stocks":[],"unused":[',
      );
      final bytes = utf8.encode(source);
      final rejected = rejection(
        reader.restore(
          bytes: bytes,
          expectedFingerprint: DatasetFingerprint.of(bytes),
        ),
      );

      expect(rejected.reason, DatasetRestoreReason.invalidDataset);
      expect(rejected.message, isNotNull);
      expect(rejected.message, isNot(contains(source)));
      expect(rejected.message, isNot(contains(bigProductId)));
    });
  });
}

DatasetRestored accepted(DatasetRestoreResult result) {
  return switch (result) {
    DatasetRestored() && final restored => restored,
    DatasetRestoreRejected(:final reason) => fail('restore rejected: $reason'),
  };
}

DatasetRestoreRejected rejection(DatasetRestoreResult result) {
  return switch (result) {
    DatasetRestoreRejected() && final rejected => rejected,
    DatasetRestored() => fail('restore succeeded'),
  };
}

DatasetRestoreReason reason(DatasetRestoreResult result) =>
    rejection(result).reason;
