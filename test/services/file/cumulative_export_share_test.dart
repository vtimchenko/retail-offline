import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/services/file/cumulative_export_share.dart';
import 'package:retail_offline/services/file/export_share.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';

import '../../support/memory_fulfilment_repository.dart';

const _productId = '1290564103789190763';
const _orderNumber = '9007199254740993';
const _filename = 'export_Store_01-A_20261014150722.json';

/// Synthetic catalogue. Stock covers the first line. No real customer data.
const _dataset =
    '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
    '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
    '"ProductID":$_productId,"SerialNumber":"SN-0001","Quantity":5}],'
    '"orders":[{"OrderID":"ORD-1","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"ТЕСТ000001","OrderNumber":$_orderNumber,'
    '"Customer":"Тестовий Клієнт А","CustomerPhone":"0501112233","Goods":[{'
    '"Product":"Тестовий товар 1","ProductID":$_productId,"Quantity":2,'
    '"Price":324.50,"Amount":649.00,"isServiceGood":0,"isParcel":0}]}]}';

void main() {
  final document = _document();

  group('CumulativeExportShare', () {
    test('a missing document does not call the adapter', () async {
      var calls = 0;
      final coordinator = CumulativeExportShare(
        shareJson: ({required filename, required bytes}) {
          calls++;
          return Future<ExportShareResult>.value(const ExportShareFailed());
        },
      );

      final result = await coordinator.share(null);

      expect(result, isA<ExportShareUnavailable>());
      expect(calls, 0);
    });

    test('passes the filename and byte-identical content', () async {
      late String sharedName;
      late Uint8List sharedBytes;
      final coordinator = _recording((filename, bytes) {
        sharedName = filename;
        sharedBytes = Uint8List.fromList(bytes);
      }, const ExportShareHandedOff());

      await coordinator.share(document);

      expect(sharedName, document.filename);
      expect(sharedBytes, document.bytes);
      expect(sharedBytes, containsAllInOrder(_productId.codeUnits));
      expect(sharedBytes, containsAllInOrder(_orderNumber.codeUnits));
    });

    test('repeats the same filename and bytes', () async {
      final shared = <(String, Uint8List)>[];
      final coordinator = _recording(
        (filename, bytes) => shared.add((filename, Uint8List.fromList(bytes))),
        const ExportShareHandedOff(),
      );

      await coordinator.share(document);
      await coordinator.share(document);

      expect(shared, hasLength(2));
      expect(shared[0].$1, document.filename);
      expect(shared[1].$1, document.filename);
      expect(shared[0].$2, document.bytes);
      expect(shared[1].$2, document.bytes);
    });

    test('returns the adapter result unchanged', () async {
      const results = <ExportShareResult>[
        ExportShareHandedOff(),
        ExportShareDownloadStarted(
          ExportShareDownloadReason.sharingUnavailable,
        ),
        ExportShareDownloadStarted(ExportShareDownloadReason.shareRejected),
        ExportShareCancelled(),
        ExportShareFailed(),
      ];

      for (final result in results) {
        final coordinator = CumulativeExportShare(
          shareJson: ({required filename, required bytes}) {
            return Future<ExportShareResult>.value(result);
          },
        );
        expect(await coordinator.share(document), same(result));
      }
    });

    test('calls the adapter before the returned future is awaited', () async {
      var called = false;
      final gate = Completer<ExportShareResult>();
      final coordinator = CumulativeExportShare(
        shareJson: ({required filename, required bytes}) {
          called = true;
          expect(filename, document.filename);
          expect(bytes, document.bytes);
          return gate.future;
        },
      );

      final pending = coordinator.share(document);

      expect(called, isTrue);
      gate.complete(const ExportShareHandedOff());
      expect(await pending, isA<ExportShareHandedOff>());
    });

    test(
      'leaves the document unchanged when the adapter edits its buffer',
      () async {
        final before = Uint8List.fromList(document.bytes);
        final coordinator = CumulativeExportShare(
          shareJson: ({required filename, required bytes}) {
            bytes[0] ^= 0x01;
            return Future<ExportShareResult>.value(
              const ExportShareCancelled(),
            );
          },
        );

        expect(await coordinator.share(document), isA<ExportShareCancelled>());
        expect(document.filename, _filename);
        expect(document.bytes, before);
      },
    );
  });

  test('sharing a committed export does not change fulfilment state', () async {
    final repository = MemoryFulfilmentRepository();
    final app = FulfilmentApplication(repository: repository);
    expect(
      await app.importDataset(Uint8List.fromList(utf8.encode(_dataset))),
      isA<FulfilmentImported>(),
    );
    expect(
      await app.reserve(
        orderId: 'ORD-1',
        productId: _productId,
        address: 'A-01',
        serialNumber: 'SN-0001',
        quantity: 2,
      ),
      isA<FulfilmentCommitted<ReserveResult>>(),
    );
    expect(
      await app.issueOrder('ORD-1'),
      isA<FulfilmentCommitted<IssueOrderResult>>(),
    );
    expect(
      await app.commitCumulativeExport(
        now: () => DateTime(2026, 10, 14, 15, 7, 22),
      ),
      isA<FulfilmentExported>(),
    );

    final session = app.session!;
    final revision = app.revision;
    final attempts = repository.commitAttempts;
    final stored = app.lastExport!;
    final filename = stored.filename;
    final bytes = Uint8List.fromList(stored.bytes);
    final shared = <(String, Uint8List)>[];
    final coordinator = _recording(
      (name, content) => shared.add((name, Uint8List.fromList(content))),
      const ExportShareHandedOff(),
    );

    expect(
      await coordinator.share(app.lastExport),
      isA<ExportShareHandedOff>(),
    );

    expect(app.session, same(session));
    expect(app.revision, revision);
    expect(repository.commitAttempts, attempts);
    expect(app.lastExport, same(stored));
    expect(session.statusOf('ORD-1'), OrderStatus.exported);
    expect(
      session.lineReservedQuantity(orderId: 'ORD-1', productId: _productId),
      2,
    );
    expect(shared.single.$1, filename);
    expect(shared.single.$2, bytes);
    expect(String.fromCharCodes(shared.single.$2), contains(_productId));
    expect(String.fromCharCodes(shared.single.$2), contains(_orderNumber));

    final restored = FulfilmentApplication(repository: repository);
    expect(await restored.load(), isA<LoadReady>());

    expect(
      await coordinator.share(restored.lastExport),
      isA<ExportShareHandedOff>(),
    );

    expect(restored.revision, revision);
    expect(restored.session!.statusOf('ORD-1'), OrderStatus.exported);
    expect(repository.commitAttempts, attempts);
    expect(shared, hasLength(2));
    expect(shared[1].$1, filename);
    expect(shared[1].$2, bytes);
  });
}

ExportDocument _document() {
  final payload = utf8.encode(
    '{"ProductID":$_productId,"OrderNumber":$_orderNumber}',
  );
  return ExportDocument(
    filename: _filename,
    bytes: Uint8List.fromList([...payload, 0xFF]),
    dateCreate: '20261014150722',
  );
}

CumulativeExportShare _recording(
  void Function(String filename, Uint8List bytes) record,
  ExportShareResult result,
) {
  return CumulativeExportShare(
    shareJson: ({required filename, required bytes}) {
      record(filename, bytes);
      return Future<ExportShareResult>.value(result);
    },
  );
}
