@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';
import 'package:retail_offline/persistence/browser/storage_change_channel.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_schema.dart';
import 'package:web/web.dart';

import '../persistence/indexeddb_probe.dart';
import 'fulfilment_application_test.dart';

/// Chrome checks for two coordinators sharing IndexedDB and BroadcastChannel.
///
/// Both coordinators run in this page. A passing run does not establish
/// Safari or installed-PWA behavior. Yields use a zero delay so the browser
/// can deliver a channel message and finish IndexedDB; they are not a timer.

const _otherFingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  var sequence = 0;
  late String databaseName;
  final coordinators = <FulfilmentTabCoordinator>[];
  final spies = <StorageChangeChannel>[];

  setUp(() {
    sequence += 1;
    databaseName =
        'retail-offline-test-coordinator-$sequence-'
        '${DateTime.now().microsecondsSinceEpoch}';
    requireTestDatabase(databaseName);
  });

  tearDown(() async {
    for (final coordinator in coordinators) {
      coordinator.close();
    }
    coordinators.clear();
    for (final spy in spies) {
      spy.close();
    }
    spies.clear();
    await IndexedDbProbe(databaseName).deleteDatabase();
  });

  test('an import reloads the other coordinator from IndexedDB', () async {
    final leftRepository = _ObservedRepository(_repository(databaseName));
    final rightRepository = _ObservedRepository(_repository(databaseName));
    final seen = <StorageChangeNotice>[];
    _spy(spies, databaseName).listen(seen.add);
    final left = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-left',
      repository: leftRepository,
    );
    final right = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-right',
      repository: rightRepository,
    );

    expect(
      await left.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    await _until(
      () => right.application.revision == 1,
      'The other coordinator did not reload the import.',
    );

    expect(right.application.fingerprint, left.application.fingerprint);
    expect(
      right.application.session!.statusOf('ORD-1'),
      OrderStatus.noSelection,
    );
    expect(right.application.block, isNull);
    expect(rightRepository.loads, 1);
    expect(leftRepository.loads, 0);
    expect(seen, hasLength(1));
    expect(seen.single.revision, '1');
    expect(seen.single.senderId, 'tab-left');
    expect(seen.single.fingerprint, left.application.fingerprint);
    await _yields(30);
    expect(seen, hasLength(1));
    expect(rightRepository.loads, 1);
    expect(leftRepository.loads, 0);
  });

  test('a reservation reloads the other coordinator from IndexedDB', () async {
    final leftRepository = _ObservedRepository(_repository(databaseName));
    final rightRepository = _ObservedRepository(_repository(databaseName));
    final seen = <StorageChangeNotice>[];
    _spy(spies, databaseName).listen(seen.add);
    final left = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-left',
      repository: leftRepository,
    );
    final right = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-right',
      repository: rightRepository,
    );
    expect(
      await left.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    await _until(
      () => right.application.revision == 1,
      'The other coordinator did not reload the import.',
    );

    expect(await reserve(left.application), isA<FulfilmentCommitted>());
    await _until(
      () => right.application.revision == 2,
      'The other coordinator did not reload the reservation.',
    );

    expect(_reserved(right.application), 1);
    expect(
      right.application.session!.statusOf('ORD-1'),
      OrderStatus.inProgress,
    );
    expect(rightRepository.loads, 2);
    expect(leftRepository.loads, 0);
    expect(seen, hasLength(2));
    expect(seen.last.revision, '2');
    await _yields(30);
    expect(seen, hasLength(2));
    expect(rightRepository.loads, 2);
  });

  test('a notice from the same sender does not reload', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-self',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );

    transport.deliver(
      StorageChangeNotice(
        revision: '4',
        fingerprint: coordinator.application.fingerprint!,
        senderId: coordinator.senderId,
      ),
    );
    await _yields(40);

    expect(repository.loads, 0);
    expect(coordinator.application.revision, 1);
  });

  test('an older notice does not reload', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-older',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    expect(await reserve(coordinator.application), isA<FulfilmentCommitted>());

    transport.deliver(
      StorageChangeNotice(
        revision: '1',
        fingerprint: coordinator.application.fingerprint!,
        senderId: 'remote-tab',
      ),
    );
    await _yields(40);

    expect(repository.loads, 0);
    expect(coordinator.application.revision, 2);
  });

  test('an equal revision and fingerprint does not reload', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-equal',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );

    transport.deliver(
      StorageChangeNotice(
        revision: '1',
        fingerprint: coordinator.application.fingerprint!,
        senderId: 'remote-tab',
      ),
    );
    await _yields(40);

    expect(repository.loads, 0);
    expect(coordinator.application.revision, 1);
  });

  test('duplicate notices settle after one reload', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-duplicate',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    final fingerprint = coordinator.application.fingerprint!;
    final notice = StorageChangeNotice(
      revision: '4',
      fingerprint: fingerprint,
      senderId: 'remote-tab',
    );

    transport.deliver(notice);
    transport.deliver(notice);
    final first = await repository.firstLoad.future;

    expect(first, isA<LoadReady>());
    expect(repository.loads, 1);
    expect(coordinator.application.revision, 1);
    expect(coordinator.application.fingerprint, fingerprint);

    transport.deliver(notice);
    expect(repository.loads, 1);
  });

  test('a notice does not install its revision into the session', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-hint',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    final fingerprint = coordinator.application.fingerprint!;

    transport.deliver(
      StorageChangeNotice(
        revision: '8',
        fingerprint: _otherFingerprint,
        senderId: 'remote-tab',
      ),
    );
    await _until(
      () => repository.loads == 1,
      'The hint did not cause a storage read.',
    );
    await _yields(40);

    expect(coordinator.application.revision, 1);
    expect(coordinator.application.fingerprint, fingerprint);
    expect(
      coordinator.application.session!.statusOf('ORD-1'),
      OrderStatus.noSelection,
    );
    expect(coordinator.application.fingerprint, isNot(_otherFingerprint));
  });

  test('a newer notice reloads the committed reservation', () async {
    final repository = _ObservedRepository(_repository(databaseName));
    final transport = _ManualTransport();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-newer',
      repository: repository,
      transport: transport,
    );
    expect(
      await coordinator.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    final other = FulfilmentApplication(repository: _repository(databaseName));
    expect(await other.load(), isA<LoadReady>());
    expect(await reserve(other), isA<FulfilmentCommitted>());

    transport.deliver(
      StorageChangeNotice(
        revision: '2',
        fingerprint: other.fingerprint!,
        senderId: 'remote-tab',
      ),
    );
    await _until(
      () => coordinator.application.revision == 2,
      'The newer notice did not reload storage.',
    );

    expect(repository.loads, 1);
    expect(_reserved(coordinator.application), 1);
    expect(transport.notices, hasLength(1));
  });

  test('a stale mutation stays rejected until an explicit reload', () async {
    final leftRepository = _ObservedRepository(_repository(databaseName));
    final rightRepository = _ObservedRepository(_repository(databaseName));
    final left = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-stale',
      repository: leftRepository,
      transport: _ManualTransport(),
    );
    final right = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-fresh',
      repository: rightRepository,
      transport: _ManualTransport(),
    );
    expect(
      await left.application.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
    expect(await right.reload(), isA<LoadReady>());
    expect(await reserve(right.application), isA<FulfilmentCommitted>());

    final conflict = await reserve(left.application);

    expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
    expect(left.application.block, PersistenceBlock.revisionConflict);
    expect(left.application.revision, 1);
    expect(leftRepository.loads, 0);
    final stored = await FulfilmentApplication(
      repository: _repository(databaseName),
    ).load();
    expect(stored, isA<LoadReady>());
    final ready = stored as LoadReady;
    expect(ready.state.revision, 2);
    expect(
      ready.state.session.lineReservedQuantity(
        orderId: 'ORD-1',
        productId: productId,
      ),
      1,
    );
    expect(
      probeText(
        (await IndexedDbProbe(databaseName)
            .read(IndexedDbFulfilmentSchema.metadata))!,
        'revision',
      ),
      '2',
    );

    expect(await left.reload(), isA<LoadReady>());
    expect(left.application.revision, 2);
    expect(left.application.block, isNull);
    expect(_reserved(left.application), 1);
    expect(leftRepository.loads, 1);
  });

  test('registering visibility does not reload', () async {
    await _storeImport(databaseName);
    final visibility = BrowserPageVisibility();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-register',
      visibility: visibility,
      transport: _ManualTransport(),
    );

    expect(visibility.isAvailable, isTrue);
    await _yields(40);

    expect(coordinator.application.revision, isNull);
    expect(visibility.isAvailable, isTrue);
  });

  test('visibilitychange follows the live visibilityState', () async {
    await _storeImport(databaseName);
    final visibility = BrowserPageVisibility();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-visibility',
      visibility: visibility,
      transport: _ManualTransport(),
    );
    await _yields(20);
    expect(coordinator.application.revision, isNull);
    // A dispatched event does not change document.visibilityState.
    final state = document.visibilityState;

    document.dispatchEvent(Event('visibilitychange'));

    if (state == 'visible') {
      await _until(
        () => coordinator.application.revision == 1,
        'A visible visibilitychange did not reload.',
      );
      expect(
        coordinator.application.fingerprint,
        DatasetFingerprint.of(datasetBytes()),
      );
    } else {
      await _yields(40);
      expect(coordinator.application.revision, isNull);
    }
    expect(visibility.isAvailable, isTrue);
  });

  test('an ordinary pageshow does not reload', () async {
    await _storeImport(databaseName);
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-pageshow-open',
      visibility: BrowserPageVisibility(),
      transport: _ManualTransport(),
    );
    await _yields(20);
    expect(coordinator.application.revision, isNull);

    _dispatchPageShow(persisted: false);
    await _yields(40);

    expect(coordinator.application.revision, isNull);
  });

  test('a restored pageshow reloads from IndexedDB', () async {
    await _storeImport(databaseName);
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-pageshow-restore',
      visibility: BrowserPageVisibility(),
      transport: _ManualTransport(),
    );
    await _yields(20);
    expect(coordinator.application.revision, isNull);

    _dispatchPageShow(persisted: true);
    await _until(
      () => coordinator.application.revision == 1,
      'A persisted pageshow did not reload.',
    );

    expect(
      coordinator.application.fingerprint,
      DatasetFingerprint.of(datasetBytes()),
    );
    expect(
      coordinator.application.session!.statusOf('ORD-1'),
      OrderStatus.noSelection,
    );
  });

  test('close removes resume listeners', () async {
    await _storeImport(databaseName);
    final visibility = BrowserPageVisibility();
    final coordinator = _open(
      coordinators,
      databaseName: databaseName,
      senderId: 'tab-closed-visibility',
      visibility: visibility,
      transport: _ManualTransport(),
    );
    _dispatchPageShow(persisted: true);
    await _until(
      () => coordinator.application.revision == 1,
      'The restored pageshow did not reload before close.',
    );
    final other = FulfilmentApplication(repository: _repository(databaseName));
    expect(await other.load(), isA<LoadReady>());
    expect(await reserve(other), isA<FulfilmentCommitted>());

    coordinator.close();
    coordinator.close();
    expect(coordinator.isClosed, isTrue);
    expect(visibility.isAvailable, isFalse);

    document.dispatchEvent(Event('visibilitychange'));
    _dispatchPageShow(persisted: true);
    await _yields(40);

    expect(coordinator.application.revision, 1);
    expect(_reserved(coordinator.application), 0);
  });
}

IndexedDbFulfilmentRepository _repository(String databaseName) {
  return IndexedDbFulfilmentRepository(databaseName: databaseName);
}

FulfilmentTabCoordinator _open(
  List<FulfilmentTabCoordinator> coordinators, {
  required String databaseName,
  required String senderId,
  FulfilmentRepository? repository,
  StorageChangeTransport? transport,
  PageVisibility? visibility,
}) {
  final coordinator = FulfilmentTabCoordinator.open(
    repository: repository ?? _repository(databaseName),
    databaseName: databaseName,
    senderId: senderId,
    transport: transport,
    visibility: visibility ?? _QuietPageVisibility(),
  );
  coordinators.add(coordinator);
  return coordinator;
}

StorageChangeChannel _spy(
  List<StorageChangeChannel> spies,
  String databaseName,
) {
  final channel = StorageChangeChannel(databaseName: databaseName);
  spies.add(channel);
  return channel;
}

Future<void> _storeImport(String databaseName) async {
  final writer = FulfilmentApplication(repository: _repository(databaseName));
  expect(await writer.importDataset(datasetBytes()), isA<FulfilmentImported>());
}

void _dispatchPageShow({required bool persisted}) {
  window.dispatchEvent(
    PageTransitionEvent(
      'pageshow',
      PageTransitionEventInit(persisted: persisted),
    ),
  );
}

int _reserved(FulfilmentApplication application) {
  return application.session!.lineReservedQuantity(
    orderId: 'ORD-1',
    productId: productId,
  );
}

/// Lets IndexedDB and BroadcastChannel tasks run.
///
/// [Duration.zero] queues the next browser task. It does not wait for a clock.
Future<void> _yields(int count) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() ready, String description) async {
  for (var turn = 0; turn < 400; turn++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail(description);
}

final class _ObservedRepository implements FulfilmentRepository {
  _ObservedRepository(this.inner);

  final IndexedDbFulfilmentRepository inner;
  var loads = 0;

  /// Completes after the first [load] has returned and the coordinator has
  /// applied that result.
  ///
  /// The coordinator resumes in microtasks after this method returns. The
  /// completer finishes on the following browser task, which runs after those
  /// microtasks, so a notice delivered then is not part of the active reload.
  final Completer<LoadResult> firstLoad = Completer<LoadResult>();

  @override
  Future<LoadResult> load() async {
    loads += 1;
    final result = await inner.load();
    if (loads == 1) {
      unawaited(
        Future<void>.delayed(Duration.zero).then((_) {
          if (!firstLoad.isCompleted) firstLoad.complete(result);
        }),
      );
    }
    return result;
  }

  @override
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    return inner.importDataset(
      bytes: bytes,
      fingerprint: fingerprint,
      snapshot: snapshot,
    );
  }

  @override
  Future<CommitResult> replaceDataset({
    required int expectedRevision,
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) {
    return inner.replaceDataset(
      expectedRevision: expectedRevision,
      bytes: bytes,
      fingerprint: fingerprint,
      snapshot: snapshot,
    );
  }

  @override
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  }) {
    return inner.commitSession(
      expectedRevision: expectedRevision,
      snapshot: snapshot,
    );
  }

  @override
  Future<CommitResult> commitExport({
    required int expectedRevision,
    required SessionSnapshot snapshot,
    required ExportDocument document,
  }) {
    return inner.commitExport(
      expectedRevision: expectedRevision,
      snapshot: snapshot,
      document: document,
    );
  }
}

final class _ManualTransport implements StorageChangeTransport {
  final List<StorageChangeNotice> notices = [];
  var _closed = false;
  void Function(StorageChangeNotice notice)? _listener;

  @override
  bool get isAvailable => !_closed;

  @override
  bool publish(StorageChangeNotice notice) {
    if (_closed) return false;
    notices.add(notice);
    return true;
  }

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    if (_closed) return;
    _listener = onNotice;
  }

  void deliver(StorageChangeNotice notice) {
    final listener = _listener;
    if (listener != null) listener(notice);
  }

  @override
  void close() {
    _closed = true;
    _listener = null;
  }
}

final class _QuietPageVisibility implements PageVisibility {
  @override
  bool get isAvailable => false;

  @override
  void listen(void Function() onResume) {}

  @override
  void close() {}
}
