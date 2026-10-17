import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';

import '../support/memory_fulfilment_repository.dart';
import 'fulfilment_application_test.dart';

void main() {
  group('FulfilmentUiController', () {
    test('starts in loading and ignores commands', () async {
      final repository = _ScriptedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);

      expect(controller.phase, FulfilmentUiPhase.loading);
      expect(controller.session, isNull);
      expect(controller.block, isNull);
      expect(controller.revision, isNull);
      expect(controller.fingerprint, isNull);
      expect(controller.lastExport, isNull);
      expect(controller.canMutate, isFalse);
      expect(controller.commandInFlight, isFalse);
      expect(controller.refreshInFlight, isFalse);
      expect(controller.operationError, isNull);
      expect(await controller.importDataset(datasetBytes()), isNull);
      expect(await controller.replaceDataset(datasetBytes()), isNull);
      expect(await _reserve(controller), isNull);
      expect(await controller.refresh(), isNull);
      expect(repository.commitAttempts, 0);
      expect(controller.phase, FulfilmentUiPhase.loading);

      gate.complete();
      await _settle(() => controller.phase != FulfilmentUiPhase.loading);
      expect(controller.phase, FulfilmentUiPhase.empty);
    });

    test('loading settles to empty once', () async {
      final repository = _ScriptedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);
      var notifications = 0;
      controller.addListener(() => notifications++);

      gate.complete();
      await _settle(() => controller.phase == FulfilmentUiPhase.empty);

      expect(notifications, 1);
      expect(controller.session, isNull);
      expect(controller.block, isNull);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isFalse);
    });

    test('loading settles to a restored session', () async {
      final repository = MemoryFulfilmentRepository();
      final seed = FulfilmentApplication(repository: repository);
      expect(
        await seed.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );
      final controller = _open(repository);

      expect(controller.phase, FulfilmentUiPhase.loading);
      await _settle(() => controller.phase != FulfilmentUiPhase.loading);

      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.revision, 1);
      expect(controller.fingerprint, seed.fingerprint);
      expect(controller.session, isNotNull);
      expect(controller.session!.dataset.storeName, 'Магазин Тест');
      expect(controller.session!.dataset.dbName, 'Store_01-A');
      expect(controller.block, isNull);
      expect(controller.canMutate, isTrue);
      expect(controller.operationError, isNull);
    });

    test('loading settles to blocked when storage is unavailable', () async {
      final repository = MemoryFulfilmentRepository();
      repository.debugStorageUnavailable(true);
      final controller = _open(repository);

      await _settle(() => controller.phase != FulfilmentUiPhase.loading);

      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.block, PersistenceBlock.storageUnavailable);
      expect(controller.session, isNull);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isFalse);
      expect(await controller.importDataset(datasetBytes()), isNull);
      expect(repository.commitAttempts, 0);
    });

    test('an unexpected startup reload blocks without writing', () async {
      final repository = _ScriptedRepository();
      repository.throwOnLoad = StateError('startup failed');
      final controller = _open(repository);

      await _settle(() => controller.phase != FulfilmentUiPhase.loading);

      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.operationError, isA<StateError>());
      expect(controller.block, isNull);
      expect(controller.session, isNull);
      expect(controller.canMutate, isFalse);
      expect(repository.debugRevision, isNull);
      expect(repository.commitAttempts, 0);
      expect(await controller.importDataset(datasetBytes()), isNull);
      expect(repository.loads, 1);

      final recovered = await controller.refresh();

      expect(recovered, isA<LoadEmpty>());
      expect(controller.phase, FulfilmentUiPhase.empty);
      expect(controller.operationError, isNull);
      expect(controller.refreshInFlight, isFalse);
      expect(repository.commitAttempts, 0);
    });

    test('an unexpected refresh blocks and can be repeated', () async {
      final repository = _ScriptedRepository();
      final transport = _Transport();
      final controller = await _ready(repository, transport: transport);
      final session = controller.session;
      final revision = repository.debugRevision;
      repository.throwOnLoad = StateError('refresh failed');

      await expectLater(controller.refresh(), throwsA(isA<StateError>()));

      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.operationError, isA<StateError>());
      expect(controller.block, isNull);
      expect(controller.session, same(session));
      expect(repository.debugRevision, revision);
      expect(controller.canMutate, isFalse);
      expect(controller.refreshInFlight, isFalse);
      expect(await _reserve(controller), isNull);

      final recovered = await controller.refresh();

      expect(recovered, isA<LoadReady>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isTrue);
      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );
    });

    test('an unexpected command exception blocks without a retry', () async {
      final repository = _ScriptedRepository();
      final controller = await _ready(repository);
      final session = controller.session;
      final loads = repository.loads;
      final attempts = repository.commitAttempts;
      repository.throwOnCommit = StateError('commit exploded');

      await expectLater(_reserve(controller), throwsA(isA<StateError>()));

      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.operationError, isA<StateError>());
      expect(controller.commandInFlight, isFalse);
      expect(controller.block, isNull);
      expect(controller.session, same(session));
      expect(controller.coordinator.application.canMutate, isTrue);
      expect(controller.canMutate, isFalse);
      expect(repository.debugRevision, 1);
      expect(repository.loads, loads);
      expect(repository.commitAttempts, attempts);
      expect(await _reserve(controller), isNull);
      expect(repository.commitAttempts, attempts);
      expect(repository.loads, loads);
    });

    test('a successful reload clears a command exception', () async {
      final repository = _ScriptedRepository();
      final controller = await _ready(repository);
      repository.throwOnCommit = StateError('commit exploded');
      await expectLater(_reserve(controller), throwsA(isA<StateError>()));
      expect(controller.phase, FulfilmentUiPhase.blocked);

      final reloaded = await controller.refresh();

      expect(reloaded, isA<LoadReady>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.operationError, isNull);
      expect(controller.block, isNull);
      expect(controller.canMutate, isTrue);
      expect(controller.revision, 1);
      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );

      final committed = await _reserve(controller);

      expect(committed, isA<FulfilmentCommitted<ReserveResult>>());
      expect(controller.revision, 2);
      expect(controller.phase, FulfilmentUiPhase.ready);
    });

    test('a remote notice publishes the reloaded session', () async {
      final repository = MemoryFulfilmentRepository();
      final transport = _Transport();
      final controller = await _ready(repository, transport: transport);
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(await reserve(other), isA<FulfilmentCommitted<ReserveResult>>());
      var notifications = 0;
      controller.addListener(() => notifications++);

      transport.deliver(
        StorageChangeNotice(
          revision: '2',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _settle(() => controller.revision == 2);

      expect(notifications, 1);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.block, isNull);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isTrue);
      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );
      expect(reservedSession(controller.session!, 'ORD-1'), 1);
    });

    test('a failed reload keeps the session and blocks mutation', () async {
      final repository = _ScriptedRepository();
      final controller = await _ready(repository);
      final session = controller.session!;
      repository.loadResult = const LoadStorageFailed();

      final result = await controller.refresh();

      expect(result, isA<LoadStorageFailed>());
      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.block, PersistenceBlock.storageFailed);
      expect(controller.session, same(session));
      expect(controller.revision, 1);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isFalse);
      expect(controller.refreshInFlight, isFalse);
      expect(await _reserve(controller), isNull);
      expect(await controller.importDataset(datasetBytes()), isNull);
    });

    test('a local reserve commits the next revision', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _ready(repository);
      final before = controller.session;

      final committed = await _reserve(controller, quantity: 1);

      expect(committed, isA<FulfilmentCommitted<ReserveResult>>());
      expect(controller.revision, 2);
      expect(repository.debugRevision, 2);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.commandInFlight, isFalse);
      expect(controller.operationError, isNull);
      expect(controller.session, isNot(same(before)));
      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );
      expect(
        controller.session,
        same((committed! as FulfilmentCommitted<ReserveResult>).session),
      );
    });

    test('a domain rejection does not change the revision', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _ready(repository);
      final session = controller.session;
      final attempts = repository.commitAttempts;

      final rejected = await _reserve(controller, orderId: 'ORD-9');

      expect(rejected, isA<FulfilmentDomainRejected<ReserveResult>>());
      expect(
        (rejected! as FulfilmentDomainRejected<ReserveResult>).result,
        isA<ReserveRejected>(),
      );
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.revision, 1);
      expect(controller.session, same(session));
      expect(controller.block, isNull);
      expect(controller.operationError, isNull);
      expect(controller.canMutate, isTrue);
      expect(controller.commandInFlight, isFalse);
      expect(repository.commitAttempts, attempts);
    });

    test('a revision conflict is returned once and not retried', () async {
      final repository = MemoryFulfilmentRepository();
      final first = await _ready(repository, senderId: 'controller-a');
      final second = _open(repository, senderId: 'controller-b');
      await _settle(() => second.phase == FulfilmentUiPhase.ready);
      expect(second.revision, 1);
      expect(await _reserve(first), isA<FulfilmentCommitted<ReserveResult>>());
      expect(first.revision, 2);
      final attempts = repository.commitAttempts;

      final conflict = await _reserve(second);

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(
        (conflict! as FulfilmentBlocked<ReserveResult>).block,
        PersistenceBlock.revisionConflict,
      );
      expect(second.phase, FulfilmentUiPhase.blocked);
      expect(second.block, PersistenceBlock.revisionConflict);
      expect(second.operationError, isNull);
      expect(second.canMutate, isFalse);
      expect(second.revision, 1);
      expect(repository.commitAttempts, attempts + 1);
      expect(await _reserve(second), isNull);
      expect(repository.commitAttempts, attempts + 1);

      final recovered = await second.refresh();

      expect(recovered, isA<LoadReady>());
      expect(second.phase, FulfilmentUiPhase.ready);
      expect(second.revision, 2);
      expect(second.block, isNull);
      expect(second.canMutate, isTrue);
    });

    test('a second command while one is in flight is ignored', () async {
      final repository = _ScriptedRepository();
      final controller = await _ready(repository);
      final hold = repository.holdNextCommit();
      final first = _reserve(controller);
      await hold.started;

      expect(controller.commandInFlight, isTrue);
      expect(controller.phase, FulfilmentUiPhase.ready);
      final attempts = repository.commitAttempts;
      final loads = repository.loads;

      expect(await _reserve(controller), isNull);
      expect(await controller.refresh(), isNull);
      expect(await controller.importDataset(datasetBytes()), isNull);
      expect(repository.commitAttempts, attempts);
      expect(controller.refreshInFlight, isFalse);

      hold.release();
      final committed = await first;

      expect(committed, isA<FulfilmentCommitted<ReserveResult>>());
      expect(controller.revision, 2);
      expect(controller.commandInFlight, isFalse);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(repository.commitAttempts, attempts);
      expect(repository.loads, loads);
    });

    test(
      'a remote reload during a command wins over the command result',
      () async {
        final repository = MemoryFulfilmentRepository();
        final transport = _Transport();
        final controller = await _ready(repository, transport: transport);
        final hold = repository.holdNextCommit();
        final pending = _reserve(controller);
        await hold.started;
        repository.debugRevision = 5;
        transport.deliver(
          StorageChangeNotice(
            revision: '5',
            fingerprint: controller.fingerprint!,
            senderId: 'remote-tab',
          ),
        );

        hold.release();
        final result = await pending;
        await _settle(() => controller.revision == 5);

        expect(result, isA<FulfilmentBlocked<ReserveResult>>());
        expect(
          (result! as FulfilmentBlocked<ReserveResult>).block,
          PersistenceBlock.revisionConflict,
        );
        expect(controller.phase, FulfilmentUiPhase.ready);
        expect(controller.revision, 5);
        expect(controller.block, isNull);
        expect(controller.operationError, isNull);
        expect(controller.commandInFlight, isFalse);
        expect(controller.canMutate, isTrue);
        expect(
          controller.session,
          same(controller.coordinator.application.session),
        );
      },
    );

    test(
      'a command exception after an in-flight reload stays blocked',
      () async {
        final repository = _ScriptedRepository();
        final transport = _Transport();
        final controller = await _ready(repository, transport: transport);
        final gate = Completer<void>();
        repository.loadGate = gate;
        transport.deliver(
          StorageChangeNotice(
            revision: '2',
            fingerprint: controller.fingerprint!,
            senderId: 'remote-tab',
          ),
        );
        await _settle(() => repository.loads == 2);
        expect(controller.revision, 1);
        expect(repository.commitEntries, 0);

        final pending = _reserve(controller);
        expect(controller.commandInFlight, isTrue);
        expect(repository.commitEntries, 0);

        final other = FulfilmentApplication(repository: repository);
        expect(await other.load(), isA<LoadReady>());
        expect(await reserve(other), isA<FulfilmentCommitted<ReserveResult>>());
        expect(repository.debugRevision, 2);
        repository.throwOnCommit = StateError('commit exploded');
        final attempts = repository.commitAttempts;
        final loads = repository.loads;
        var sawInstalledRead = false;
        controller.addListener(() {
          if (controller.revision == 2 &&
              controller.operationError == null &&
              controller.phase == FulfilmentUiPhase.ready) {
            sawInstalledRead = true;
          }
        });

        gate.complete();
        await expectLater(pending, throwsA(isA<StateError>()));

        expect(sawInstalledRead, isTrue);
        expect(repository.commitEntries, 2);
        expect(controller.phase, FulfilmentUiPhase.blocked);
        expect(controller.canMutate, isFalse);
        expect(controller.operationError, isA<StateError>());
        expect(controller.commandInFlight, isFalse);
        expect(controller.block, isNull);
        expect(controller.session, isNotNull);
        expect(controller.revision, 2);
        expect(
          controller.session,
          same(controller.coordinator.application.session),
        );
        expect(repository.commitAttempts, attempts);
        expect(repository.loads, loads);

        final recovered = await controller.refresh();

        expect(recovered, isA<LoadReady>());
        expect(controller.phase, FulfilmentUiPhase.ready);
        expect(controller.operationError, isNull);
        expect(controller.canMutate, isTrue);
        expect(controller.revision, 2);
      },
    );

    test(
      'an explicit refresh exception after an earlier reload stays blocked',
      () async {
        final repository = _ScriptedRepository();
        final transport = _Transport();
        final controller = await _ready(repository, transport: transport);
        final gate = Completer<void>();
        repository.loadGate = gate;
        repository.suppressNextThrow = true;
        repository.throwOnLoad = StateError('refresh failed');
        transport.deliver(
          StorageChangeNotice(
            revision: '2',
            fingerprint: controller.fingerprint!,
            senderId: 'remote-tab',
          ),
        );
        await _settle(() => repository.loads == 2);
        expect(controller.phase, FulfilmentUiPhase.ready);

        final pending = controller.refresh();
        expect(controller.refreshInFlight, isTrue);
        expect(controller.operationError, isNull);
        final loads = repository.loads;

        gate.complete();
        await expectLater(pending, throwsA(isA<StateError>()));

        expect(controller.phase, FulfilmentUiPhase.blocked);
        expect(controller.canMutate, isFalse);
        expect(controller.operationError, isA<StateError>());
        expect(controller.refreshInFlight, isFalse);
        expect(controller.block, isNull);
        expect(controller.session, isNotNull);
        expect(
          controller.session,
          same(controller.coordinator.application.session),
        );
        expect(repository.loads, loads + 1);
        expect(repository.commitAttempts, 1);

        final recovered = await controller.refresh();

        expect(recovered, isA<LoadReady>());
        expect(controller.phase, FulfilmentUiPhase.ready);
        expect(controller.operationError, isNull);
        expect(controller.canMutate, isTrue);
        expect(controller.refreshInFlight, isFalse);
      },
    );

    test('disposal during startup does not notify', () async {
      final repository = _ScriptedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      final controller = _open(repository);
      await Future<void>.delayed(Duration.zero);
      expect(repository.loads, 1);
      expect(controller.phase, FulfilmentUiPhase.loading);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.dispose();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
      expect(controller.coordinator.isClosed, isTrue);
      expect(repository.debugRevision, isNull);
      expect(await controller.importDataset(datasetBytes()), isNull);
    });

    test('disposal during a command does not notify', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _ready(repository);
      final hold = repository.holdNextCommit();
      final pending = _reserve(controller);
      await hold.started;
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.dispose();
      hold.release();
      final result = await pending;
      await Future<void>.delayed(Duration.zero);

      expect(result, isA<FulfilmentCommitted<ReserveResult>>());
      expect(notifications, 0);
      expect(controller.commandInFlight, isFalse);
      expect(controller.coordinator.isClosed, isTrue);
      expect(repository.debugRevision, 2);
      expect(await _reserve(controller), isNull);
    });

    test('the session getter is the application session', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _ready(repository);

      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );
      expect(
        controller.lastExport,
        same(controller.coordinator.application.lastExport),
      );

      final committed = await _reserve(controller);
      expect(
        controller.session,
        same(controller.coordinator.application.session),
      );
      expect(
        controller.session,
        same((committed! as FulfilmentCommitted<ReserveResult>).session),
      );
    });

    test('import and replacement follow the phase', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = _open(repository);
      await _settle(() => controller.phase == FulfilmentUiPhase.empty);

      expect(await controller.replaceDataset(datasetBytes()), isNull);
      expect(await _reserve(controller), isNull);
      expect(
        await controller.removeUnits(
          orderId: 'ORD-1',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isNull,
      );
      expect(await controller.clearOrder('ORD-1'), isNull);
      expect(await controller.issueOrder('ORD-1'), isNull);
      expect(await controller.cancelIssuance('ORD-1'), isNull);
      expect(await controller.commitCumulativeExport(), isNull);
      expect(repository.commitAttempts, 0);

      final rejected = await controller.importDataset(
        Uint8List.fromList('{'.codeUnits),
      );

      expect(rejected, isA<FulfilmentImportRejected>());
      expect(controller.phase, FulfilmentUiPhase.empty);
      expect(controller.block, isNull);
      expect(controller.operationError, isNull);
      expect(repository.commitAttempts, 0);

      final imported = await controller.importDataset(datasetBytes());

      expect(imported, isA<FulfilmentImported>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.revision, 1);
      expect(
        controller.session,
        same((imported! as FulfilmentImported).session),
      );
      expect(await controller.importDataset(datasetBytes()), isNull);
      expect(repository.commitAttempts, 1);

      final attempts = repository.commitAttempts;
      final replaced = await controller.replaceDataset(
        catalogue(storeName: 'Інший магазин', dbName: 'Store_02-B'),
      );

      expect(replaced, isA<FulfilmentReplaced>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.dataset.dbName, 'Store_02-B');
      expect(controller.session!.dataset.storeName, 'Інший магазин');
      expect(controller.revision, 2);
      expect(controller.block, isNull);
      expect(controller.commandInFlight, isFalse);
      expect(repository.commitAttempts, attempts + 1);

      final forwarded = await controller.replaceDataset(
        catalogue(storeName: 'Третій магазин', dbName: 'Store_03-C'),
        confirmedRevision: controller.revision,
      );

      expect(forwarded, isA<FulfilmentReplaced>());
      expect(controller.session!.dataset.dbName, 'Store_03-C');
      expect(controller.revision, 3);
      expect(repository.commitAttempts, attempts + 2);

      final stale = await controller.replaceDataset(
        datasetBytes(),
        confirmedRevision: 1,
      );

      expect(stale, isA<FulfilmentReplacementStale>());
      expect((stale! as FulfilmentReplacementStale).revision, 3);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.block, isNull);
      expect(controller.session!.dataset.dbName, 'Store_03-C');
      expect(repository.commitAttempts, attempts + 2);

      final invalid = await controller.replaceDataset(
        Uint8List.fromList('{'.codeUnits),
      );

      expect(invalid, isA<FulfilmentReplacementInputRejected>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.revision, 3);
      expect(controller.block, isNull);
      expect(controller.operationError, isNull);
      expect(repository.commitAttempts, attempts + 2);
    });

    test('export forwards the result and clears the in-flight flag', () async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _ready(repository);
      expect(
        await _reserve(controller, quantity: 2),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await controller.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      final attempts = repository.commitAttempts;
      final hold = repository.holdNextCommit();
      final pending = controller.commitCumulativeExport(now: _clock);

      await hold.started;
      expect(controller.commandInFlight, isTrue);
      expect(await controller.commitCumulativeExport(now: _clock), isNull);
      expect(repository.commitAttempts, attempts + 1);

      hold.release();
      final exported = await pending;

      expect(exported, isA<FulfilmentExported>());
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.commandInFlight, isFalse);
      expect(controller.operationError, isNull);
      expect(controller.revision, 4);
      expect(controller.lastExport, isNotNull);
      expect(
        controller.lastExport,
        same(controller.coordinator.application.lastExport),
      );
      expect(
        controller.lastExport,
        same((exported! as FulfilmentExported).document),
      );
      expect(repository.commitAttempts, attempts + 1);
    });
  });
}

const _databaseName = 'retail-offline-test';

DateTime _clock() => DateTime(2026, 10, 14, 15, 7, 22);

FulfilmentUiController _open(
  MemoryFulfilmentRepository repository, {
  _Transport? transport,
  String senderId = 'controller-test',
}) {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: transport ?? _Transport(),
    visibility: _Pages(),
    senderId: senderId,
  );
  addTearDown(controller.dispose);
  return controller;
}

Future<FulfilmentUiController> _ready(
  MemoryFulfilmentRepository repository, {
  _Transport? transport,
  String senderId = 'controller-test',
}) async {
  final controller = _open(
    repository,
    transport: transport,
    senderId: senderId,
  );
  await _settle(() => controller.phase == FulfilmentUiPhase.empty);
  final imported = await controller.importDataset(datasetBytes());
  expect(imported, isA<FulfilmentImported>());
  expect(controller.phase, FulfilmentUiPhase.ready);
  return controller;
}

Future<FulfilmentCommandResult<ReserveResult>?> _reserve(
  FulfilmentUiController controller, {
  String orderId = 'ORD-1',
  int quantity = 1,
}) {
  return controller.reserve(
    orderId: orderId,
    productId: productId,
    address: address,
    serialNumber: serial,
    quantity: quantity,
  );
}

Future<void> _settle(bool Function() done) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('timed out waiting for the controller');
}

final class _ScriptedRepository extends MemoryFulfilmentRepository {
  Completer<void>? loadGate;
  Object? throwOnLoad;
  var suppressNextThrow = false;
  LoadResult? loadResult;
  Object? throwOnCommit;
  var loads = 0;
  var commitEntries = 0;

  @override
  Future<LoadResult> load() async {
    loads++;
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    if (suppressNextThrow) {
      suppressNextThrow = false;
    } else {
      final error = throwOnLoad;
      if (error != null) {
        throwOnLoad = null;
        throw error;
      }
    }
    final scripted = loadResult;
    if (scripted != null) {
      loadResult = null;
      return scripted;
    }
    return super.load();
  }

  @override
  Future<CommitResult> commitSession({
    required int expectedRevision,
    required SessionSnapshot snapshot,
  }) async {
    commitEntries++;
    final error = throwOnCommit;
    if (error != null) {
      throwOnCommit = null;
      throw error;
    }
    return super.commitSession(
      expectedRevision: expectedRevision,
      snapshot: snapshot,
    );
  }
}

final class _Pages implements PageVisibility {
  var _closed = false;

  @override
  bool get isAvailable => !_closed;

  @override
  void listen(void Function() onResume) {}

  @override
  void close() {
    _closed = true;
  }
}

final class _Transport implements StorageChangeTransport {
  void Function(StorageChangeNotice notice)? _listener;
  var _closed = false;

  @override
  bool get isAvailable => !_closed;

  @override
  bool publish(StorageChangeNotice notice) {
    if (_closed) return false;
    return true;
  }

  void deliver(StorageChangeNotice notice) {
    final listener = _listener;
    if (listener != null) listener(notice);
  }

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    _listener = onNotice;
  }

  @override
  void close() {
    _closed = true;
    _listener = null;
  }
}
