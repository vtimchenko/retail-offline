import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';

import '../support/memory_fulfilment_repository.dart';
import 'fulfilment_application_test.dart';

void main() {
  group('FulfilmentTabCoordinator publishing', () {
    test('an import publishes one notice', () async {
      final opened = _Opened(senderId: _senderId);
      final fingerprint = DatasetFingerprint.of(datasetBytes());

      final result = await opened.application.importDataset(datasetBytes());

      expect(result, isA<FulfilmentImported>());
      expect(opened.transport.notices, hasLength(1));
      expect(opened.transport.notices.single.revision, '1');
      expect(opened.transport.notices.single.fingerprint, fingerprint);
      expect(opened.transport.notices.single.senderId, _senderId);
      expect(opened.application.revision, 1);
    });

    test('a reservation publishes one more notice', () async {
      final opened = _Opened(senderId: _senderId);
      final fingerprint = DatasetFingerprint.of(datasetBytes());
      expect(
        await opened.application.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      final reserved = await reserve(opened.application);

      expect(reserved, isA<FulfilmentCommitted<ReserveResult>>());
      expect(opened.transport.notices, hasLength(2));
      expect(opened.transport.notices.last.revision, '2');
      expect(opened.transport.notices.last.fingerprint, fingerprint);
      expect(opened.transport.notices.last.senderId, _senderId);
    });

    test('a failed command does not publish', () async {
      final opened = _Opened(senderId: _senderId);
      expect(
        await opened.application.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      opened.repository.failNextCommit();

      final failed = await reserve(opened.application);

      expect(failed, isA<FulfilmentBlocked<ReserveResult>>());
      expect(opened.application.block, PersistenceBlock.storageFailed);
      expect(opened.transport.notices, hasLength(1));
    });

    test('a no-op does not publish', () async {
      final opened = _Opened(senderId: _senderId);
      expect(
        await opened.application.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      final cleared = await opened.application.clearOrder('ORD-1');

      expect(cleared, isA<FulfilmentUnchanged<ClearOrderResult>>());
      expect(opened.transport.notices, hasLength(1));
    });

    test('an unavailable transport does not block a commit', () async {
      final opened = _Opened(available: false);

      final result = await opened.application.importDataset(datasetBytes());

      expect(result, isA<FulfilmentImported>());
      expect(opened.application.revision, 1);
      expect(opened.application.block, isNull);
      expect(opened.application.canMutate, isTrue);
      expect(opened.transport.notices, isEmpty);
    });

    test('a throwing publish does not block a commit', () async {
      final opened = _Opened(throwOnPublish: true);

      final result = await opened.application.importDataset(datasetBytes());

      expect(result, isA<FulfilmentImported>());
      expect(opened.application.revision, 1);
      expect(
        opened.application.fingerprint,
        DatasetFingerprint.of(datasetBytes()),
      );
      expect(opened.application.block, isNull);
      expect(opened.application.canMutate, isTrue);
    });

    test('close stops publishing and can be repeated', () async {
      final opened = _Opened(senderId: _senderId);
      expect(
        await opened.application.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      opened.coordinator.close();
      opened.coordinator.close();
      final reserved = await reserve(opened.application);

      expect(opened.coordinator.isClosed, isTrue);
      expect(opened.transport.closeCount, 1);
      expect(reserved, isA<FulfilmentCommitted<ReserveResult>>());
      expect(opened.application.revision, 2);
      expect(opened.transport.notices, hasLength(1));
    });

    test('two coordinators generate different sender ids', () {
      final first = FulfilmentTabCoordinator.open(
        repository: MemoryFulfilmentRepository(),
        databaseName: 'retail-offline-test',
      );
      final second = FulfilmentTabCoordinator.open(
        repository: MemoryFulfilmentRepository(),
        databaseName: 'retail-offline-test',
      );
      addTearDown(first.close);
      addTearDown(second.close);

      expect(first.senderId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second.senderId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(first.senderId, isNot(second.senderId));
    });
  });
}

const _senderId = '0123456789abcdef0123456789abcdef';

final class _Opened {
  _Opened({
    bool available = true,
    bool throwOnPublish = false,
    String? senderId,
  }) : transport = _RecordingTransport(
         available: available,
         throwOnPublish: throwOnPublish,
       ),
       repository = MemoryFulfilmentRepository() {
    coordinator = FulfilmentTabCoordinator.open(
      repository: repository,
      databaseName: 'retail-offline-test',
      transport: transport,
      senderId: senderId,
    );
  }

  final MemoryFulfilmentRepository repository;
  final _RecordingTransport transport;
  late final FulfilmentTabCoordinator coordinator;

  FulfilmentApplication get application => coordinator.application;
}

final class _RecordingTransport implements StorageChangeTransport {
  _RecordingTransport({required this.available, required this.throwOnPublish});

  final bool available;
  final bool throwOnPublish;
  final List<StorageChangeNotice> notices = [];
  var closeCount = 0;

  @override
  bool get isAvailable => available;

  @override
  bool publish(StorageChangeNotice notice) {
    if (throwOnPublish) throw StateError('publish failed');
    if (!available) return false;
    notices.add(notice);
    return true;
  }

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {}

  @override
  void close() {
    closeCount++;
  }
}
