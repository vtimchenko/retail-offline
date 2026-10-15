import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_schema.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_records.dart';
import 'package:retail_offline/persistence/session_snapshot_codec.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';

const productId = '1290564103789190763';

const _dataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$productId,"SerialNumber":"SN-0001","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":9007199254740993,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$productId,"Quantity":2,'
    '"Price":324.50,"Amount":649.00,"isServiceGood":0,"isParcel":0}]}]}';

void main() {
  group('revision text', () {
    test('accepts 1 and the safe maximum', () {
      expect(IndexedDbFulfilmentSchema.tryParseRevision('1'), 1);
      expect(
        IndexedDbFulfilmentSchema.tryParseRevision('9007199254740991'),
        StorageRevision.maximum,
      );
      expect(
        IndexedDbFulfilmentSchema.revisionText(StorageRevision.maximum),
        '9007199254740991',
      );
    });

    test('rejects zero, leading zeros, and values above the ceiling', () {
      expect(IndexedDbFulfilmentSchema.tryParseRevision('0'), isNull);
      expect(IndexedDbFulfilmentSchema.tryParseRevision('01'), isNull);
      expect(
        IndexedDbFulfilmentSchema.tryParseRevision('9007199254740992'),
        isNull,
      );
      expect(
        IndexedDbFulfilmentSchema.tryParseRevision('90071992547409910'),
        isNull,
      );
      expect(IndexedDbFulfilmentSchema.tryParseRevision(null), isNull);
    });
  });

  group('schema kind', () {
    test('treats 1 as current and other canonical integers as unsupported', () {
      expect(
        IndexedDbFulfilmentSchema.schemaKind('1'),
        IndexedDbSchemaKind.current,
      );
      expect(
        IndexedDbFulfilmentSchema.schemaKind('0'),
        IndexedDbSchemaKind.unsupported,
      );
      expect(
        IndexedDbFulfilmentSchema.schemaKind('2'),
        IndexedDbSchemaKind.unsupported,
      );
    });

    test('treats a non-canonical token as malformed', () {
      expect(
        IndexedDbFulfilmentSchema.schemaKind('01'),
        IndexedDbSchemaKind.malformed,
      );
      expect(
        IndexedDbFulfilmentSchema.schemaKind(null),
        IndexedDbSchemaKind.malformed,
      );
    });
  });

  group('interpretIndexedDbRecords', () {
    test('an absent database is empty', () {
      expect(interpretIndexedDbRecords(), isA<LoadEmpty>());
    });

    test('a missing required record is corrupted', () {
      final image = _image();
      expect(
        interpretIndexedDbRecords(
          dataset: image.dataset,
          metadata: image.metadata,
        ),
        isA<LoadCorrupted>(),
      );
    });

    test('an unsupported record schema wins over bad content', () {
      final image = _image();
      expect(
        interpretIndexedDbRecords(
          dataset: _datasetRecord(
            bytes: Uint8List.fromList([1]),
            fingerprint: 'not-a-hash',
            schema: '2',
          ),
          session: image.session,
          metadata: image.metadata,
        ),
        isA<LoadUnsupportedVersion>(),
      );
    });

    test('a malformed schema token is corrupted', () {
      final image = _image();
      expect(
        interpretIndexedDbRecords(
          dataset: image.dataset,
          session: image.session,
          metadata: _metadataRecord(
            revision: '1',
            fingerprint: image.fingerprint,
            schema: '01',
          ),
        ),
        isA<LoadCorrupted>(),
      );
    });

    test('a fingerprint mismatch is corrupted', () {
      final image = _image();
      expect(
        interpretIndexedDbRecords(
          dataset: image.dataset,
          session: image.session,
          metadata: _metadataRecord(revision: '1', fingerprint: 'a' * 64),
        ),
        isA<LoadCorrupted>(),
      );
    });

    test('a valid import image restores revision 1', () {
      final image = _image();

      final result = interpretIndexedDbRecords(
        dataset: image.dataset,
        session: image.session,
        metadata: image.metadata,
      );

      expect(result, isA<LoadReady>());
      final ready = result as LoadReady;
      expect(ready.state.revision, 1);
      expect(ready.state.fingerprint, image.fingerprint);
      expect(
        ready.state.dataset.orders.single.orderNumber.literal,
        '9007199254740993',
      );
      expect(ready.state.dataset.stocks.single.productId.literal, productId);
      expect(ready.state.export, isNull);
    });

    test('a digest mismatch is corrupted and a real export restores', () {
      final image = _issued();
      final digest = DatasetFingerprint.of(image.document.bytes);
      expect(
        interpretIndexedDbRecords(
          dataset: image.dataset,
          session: image.session,
          export: _exportRecord(image.document, digest: 'a' * 64),
          metadata: image.metadata,
        ),
        isA<LoadCorrupted>(),
      );

      final result = interpretIndexedDbRecords(
        dataset: image.dataset,
        session: image.session,
        export: _exportRecord(image.document, digest: digest),
        metadata: image.metadata,
      );

      expect(result, isA<LoadReady>());
      final ready = result as LoadReady;
      expect(ready.state.export!.bytes, image.document.bytes);
      expect(ready.state.session.statusOf('ORD-1'), OrderStatus.exported);
    });

    test('an unsupported snapshot schema is not reported as corruption', () {
      final image = _image();
      final snapshot = image.snapshotJson.replaceFirst(
        '"schemaVersion": 1',
        '"schemaVersion": 2',
      );

      expect(
        interpretIndexedDbRecords(
          dataset: image.dataset,
          session: _sessionRecord(snapshot),
          metadata: image.metadata,
        ),
        isA<LoadUnsupportedVersion>(),
      );
    });
  });
}

IndexedDbRecord _datasetRecord({
  required Uint8List bytes,
  required String fingerprint,
  String schema = '1',
}) {
  return IndexedDbRecord(
    fields: {
      IndexedDbFulfilmentSchema.schemaVersionField: IndexedDbField.text(schema),
      IndexedDbFulfilmentSchema.bytesField: IndexedDbField.bytes(bytes),
      IndexedDbFulfilmentSchema.fingerprintField: IndexedDbField.text(
        fingerprint,
      ),
    },
    unexpectedKeys: false,
  );
}

IndexedDbRecord _sessionRecord(String snapshot, {String schema = '1'}) {
  return IndexedDbRecord(
    fields: {
      IndexedDbFulfilmentSchema.schemaVersionField: IndexedDbField.text(schema),
      IndexedDbFulfilmentSchema.snapshotField: IndexedDbField.text(snapshot),
    },
    unexpectedKeys: false,
  );
}

IndexedDbRecord _metadataRecord({
  required String revision,
  required String fingerprint,
  String schema = '1',
}) {
  return IndexedDbRecord(
    fields: {
      IndexedDbFulfilmentSchema.schemaVersionField: IndexedDbField.text(schema),
      IndexedDbFulfilmentSchema.revisionField: IndexedDbField.text(revision),
      IndexedDbFulfilmentSchema.fingerprintField: IndexedDbField.text(
        fingerprint,
      ),
    },
    unexpectedKeys: false,
  );
}

IndexedDbRecord _exportRecord(
  ExportDocument document, {
  required String digest,
}) {
  return IndexedDbRecord(
    fields: {
      IndexedDbFulfilmentSchema.schemaVersionField: const IndexedDbField.text(
        '1',
      ),
      IndexedDbFulfilmentSchema.filenameField: IndexedDbField.text(
        document.filename,
      ),
      IndexedDbFulfilmentSchema.dateCreateField: IndexedDbField.text(
        document.dateCreate,
      ),
      IndexedDbFulfilmentSchema.bytesField: IndexedDbField.bytes(
        document.bytes,
      ),
      IndexedDbFulfilmentSchema.digestField: IndexedDbField.text(digest),
    },
    unexpectedKeys: false,
  );
}

({
  IndexedDbRecord dataset,
  IndexedDbRecord session,
  IndexedDbRecord metadata,
  String fingerprint,
  String snapshotJson,
})
_image() {
  final bytes = Uint8List.fromList(utf8.encode(_dataset));
  final fingerprint = DatasetFingerprint.of(bytes);
  final restored = const DatasetByteRestore().restore(
    bytes: bytes,
    expectedFingerprint: fingerprint,
  );
  final dataset = (restored as DatasetRestored).dataset;
  final opened = FulfilmentSession.open(dataset) as DatasetOpened;
  final snapshot = opened.session.capture(datasetFingerprint: fingerprint);
  final snapshotJson = const SessionSnapshotCodec().encode(snapshot);
  return (
    dataset: _datasetRecord(bytes: bytes, fingerprint: fingerprint),
    session: _sessionRecord(snapshotJson),
    metadata: _metadataRecord(revision: '1', fingerprint: fingerprint),
    fingerprint: fingerprint,
    snapshotJson: snapshotJson,
  );
}

({
  IndexedDbRecord dataset,
  IndexedDbRecord session,
  IndexedDbRecord metadata,
  ExportDocument document,
})
_issued() {
  final bytes = Uint8List.fromList(utf8.encode(_dataset));
  final fingerprint = DatasetFingerprint.of(bytes);
  final restored = const DatasetByteRestore().restore(
    bytes: bytes,
    expectedFingerprint: fingerprint,
  );
  final dataset = (restored as DatasetRestored).dataset;
  final opened = FulfilmentSession.open(dataset) as DatasetOpened;
  final reserved = opened.session.reserve(
    orderId: 'ORD-1',
    productId: productId,
    address: 'A-01',
    serialNumber: 'SN-0001',
    quantity: 2,
  ) as ReserveApplied;
  final issued = reserved.session.issueOrder('ORD-1') as OrderIssued;
  final prepared = const CumulativeJsonExport().prepare(
    issued.session,
    now: () => DateTime(2026, 10, 14, 15, 7, 22),
  ) as CumulativeExportPrepared;
  final snapshot = prepared.pendingSession.capture(
    datasetFingerprint: fingerprint,
  );
  return (
    dataset: _datasetRecord(bytes: bytes, fingerprint: fingerprint),
    session: _sessionRecord(const SessionSnapshotCodec().encode(snapshot)),
    metadata: _metadataRecord(revision: '4', fingerprint: fingerprint),
    document: prepared.document,
  );
}
