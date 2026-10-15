import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';

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

  group('FulfilmentTabCoordinator remote reload', () {
    test('a newer notice reloads once', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final hold = _LoadHold();
      repo.nextHold = hold;

      opened.transport.deliver(_remote('2', opened.fingerprint));
      await hold.entered.future;

      expect(repo.loads, 1);
      hold.release.complete();
      await _turns(4);
      expect(opened.application.revision, 1);
      expect(repo.loads, 1);
    });

    test('the local sender id is ignored', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);

      opened.transport.deliver(_remote('2', opened.fingerprint, opened.sender));
      await _turns(4);

      expect(repo.loads, 0);
      expect(opened.application.revision, 1);
    });

    test('an older notice is ignored', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      expect(await reserve(opened.application), isA<FulfilmentCommitted>());

      opened.transport.deliver(_remote('1', opened.fingerprint));
      await _turns(4);

      expect(repo.loads, 0);
      expect(opened.application.revision, 2);
    });

    test('an equal revision and fingerprint is ignored', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);

      opened.transport.deliver(_remote('1', opened.fingerprint));
      await _turns(4);

      expect(repo.loads, 0);
    });

    test(
      'a fingerprint mismatch is verified once and then suppressed',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        expect(opened.fingerprint, isNot(_otherFingerprint));
        final hold = _LoadHold();
        repo.nextHold = hold;

        opened.transport.deliver(_remote('1', _otherFingerprint));
        await hold.entered.future;
        hold.release.complete();
        await _turns(4);
        expect(repo.loads, 1);
        expect(opened.application.fingerprint, opened.fingerprint);

        opened.transport.deliver(_remote('1', _otherFingerprint));
        await _turns(4);
        expect(repo.loads, 1);

        final again = _LoadHold();
        repo.nextHold = again;
        opened.transport.deliver(_remote('2', opened.fingerprint));
        await again.entered.future;
        expect(repo.loads, 2);
        again.release.complete();
      },
    );

    test(
      'an unresolved revision is suppressed until a higher one arrives',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;

        opened.transport.deliver(_remote('9', opened.fingerprint));
        await hold.entered.future;
        hold.release.complete();
        await _turns(4);
        expect(opened.application.revision, 1);
        expect(repo.loads, 1);

        opened.transport.deliver(_remote('9', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 1);

        final higher = _LoadHold();
        repo.nextHold = higher;
        opened.transport.deliver(_remote('10', opened.fingerprint));
        await higher.entered.future;
        expect(repo.loads, 2);
        higher.release.complete();
      },
    );

    test('a burst before the load starts is one reload', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final hold = _LoadHold();
      repo.nextHold = hold;

      opened.transport.deliver(_remote('2', opened.fingerprint));
      opened.transport.deliver(_remote('3', opened.fingerprint));
      opened.transport.deliver(_remote('4', _otherFingerprint));
      await hold.entered.future;

      expect(repo.loads, 1);
      hold.release.complete();
      await _turns(4);
      expect(repo.loads, 1);
      expect(opened.application.revision, 1);
    });

    test('a notice during a reload is handled by one follow-up', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final first = _LoadHold();
      repo.nextHold = first;
      opened.transport.deliver(_remote('2', opened.fingerprint));
      await first.entered.future;

      final second = _LoadHold();
      repo.nextHold = second;
      opened.transport.deliver(_remote('8', opened.fingerprint));
      opened.transport.deliver(_remote('9', opened.fingerprint));
      first.release.complete();
      await second.entered.future;

      expect(repo.loads, 2);
      second.release.complete();
      await _turns(4);
      expect(repo.loads, 2);
    });

    test('a notice during the follow-up schedules one more load', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final first = _LoadHold();
      repo.nextHold = first;
      opened.transport.deliver(_remote('2', opened.fingerprint));
      await first.entered.future;
      final second = _LoadHold();
      repo.nextHold = second;
      opened.transport.deliver(_remote('3', opened.fingerprint));
      first.release.complete();
      await second.entered.future;

      final third = _LoadHold();
      repo.nextHold = third;
      opened.transport.deliver(_remote('4', opened.fingerprint));
      second.release.complete();
      await third.entered.future;

      expect(repo.loads, 3);
      third.release.complete();
    });

    test(
      'a notice during a local command waits and does not retry it',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final commit = repo.holdNextCommit();
        final reserving = reserve(opened.application);
        await commit.started;
        final load = _LoadHold();
        repo.nextHold = load;

        opened.transport.deliver(_remote('9', opened.fingerprint));
        commit.release();
        final reserved = await reserving;

        expect(reserved, isA<FulfilmentCommitted<ReserveResult>>());
        final attempts = repo.commitAttempts;
        await load.entered.future;
        expect(repo.loads, 1);
        expect(repo.commitAttempts, attempts);
        load.release.complete();
        await _turns(4);
        expect(opened.application.revision, 2);
        expect(repo.commitAttempts, attempts);
      },
    );

    test('explicit reload returns the load it started', () async {
      final opened = await _imported(_LoadGateRepository());

      final result = await opened.coordinator.reload();

      expect(result, isA<LoadReady>());
      expect((result as LoadReady).state.revision, 1);
      expect(opened.application.revision, 1);
    });

    test(
      'an explicit reload during a load waits for the next result',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final firstHold = _LoadHold();
        repo.nextHold = firstHold;
        final first = opened.coordinator.reload();
        await firstHold.entered.future;
        final secondHold = _LoadHold();
        repo.nextHold = secondHold;
        final second = opened.coordinator.reload();

        firstHold.release.complete();
        await secondHold.entered.future;
        expect(repo.loads, 2);
        final other = FulfilmentApplication(repository: repo);
        expect(await other.load(), isA<LoadReady>());
        expect(await reserve(other), isA<FulfilmentCommitted<ReserveResult>>());
        secondHold.release.complete();

        expect((await first as LoadReady).state.revision, 1);
        expect((await second as LoadReady).state.revision, 2);
      },
    );

    test(
      'a failed reload stops the drain and a later notice can recover',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;
        repo.failNext = true;
        opened.transport.deliver(_remote('4', opened.fingerprint));
        await hold.entered.future;
        final during = _LoadHold();
        repo.nextHold = during;
        opened.transport.deliver(_remote('5', opened.fingerprint));
        hold.release.complete();
        await _turns(4);

        expect(repo.loads, 1);
        expect(during.entered.isCompleted, isFalse);
        expect(opened.application.block, PersistenceBlock.storageFailed);
        expect(opened.application.revision, 1);
        repo.nextHold = null;

        opened.transport.deliver(_remote('4', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 2);
        expect(opened.application.block, isNull);
        expect(opened.application.revision, 1);
      },
    );

    test(
      'close lets the current load finish and skips the follow-up',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;
        final current = opened.coordinator.reload();
        await hold.entered.future;
        final queued = opened.coordinator.reload();
        final queuedError = expectLater(queued, throwsA(isA<StateError>()));

        opened.coordinator.close();
        opened.coordinator.close();
        hold.release.complete();

        expect(await current, isA<LoadReady>());
        await queuedError;
        expect(repo.loads, 1);
        opened.transport.deliver(_remote('3', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 1);
        expect(opened.coordinator.isClosed, isTrue);
      },
    );

    test('a throwing close stays closed', () async {
      final opened = _Opened(senderId: _senderId, throwOnClose: true);
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
      expect(opened.transport.notices, hasLength(1));
      await expectLater(
        opened.coordinator.reload(),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'an unexpected reload error finishes that caller and the next reload',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;
        repo.throwNext = true;
        final failed = opened.coordinator.reload();
        final failedError = expectLater(
          failed,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'reload failed',
            ),
          ),
        );
        await hold.entered.future;
        final attempts = repo.commitAttempts;
        final queuedHold = _LoadHold();
        repo.nextHold = queuedHold;
        final queued = opened.coordinator.reload();
        opened.transport.deliver(_remote('8', opened.fingerprint));

        hold.release.complete();
        await failedError;
        await queuedHold.entered.future;
        expect(repo.loads, 2);
        queuedHold.release.complete();

        final queuedResult = await queued;
        expect(queuedResult, isA<LoadReady>());
        expect((queuedResult as LoadReady).state.revision, 1);
        expect(opened.application.revision, 1);
        expect(repo.commitAttempts, attempts);
        await _turns(4);
        expect(repo.loads, 2);

        final recovered = await opened.coordinator.reload();
        expect(recovered, isA<LoadReady>());
        expect(repo.loads, 3);
        expect(repo.commitAttempts, attempts);
      },
    );

    test('a notice that throws inside reload does not retry', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      repo.throwNext = true;

      opened.transport.deliver(_remote('4', opened.fingerprint));
      await _turns(6);

      expect(repo.loads, 1);
      expect(opened.application.revision, 1);
      expect(opened.application.block, isNull);
      expect(await opened.coordinator.reload(), isA<LoadReady>());
      expect(repo.loads, 2);
      expect(repo.commitAttempts, 1);
    });

    test(
      'an explicit empty load lets a new revision 1 notice reload',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;

        opened.transport.deliver(_remote('9', opened.fingerprint));
        await hold.entered.future;
        hold.release.complete();
        await _turns(4);
        expect(repo.loads, 1);

        opened.transport.deliver(_remote('5', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 1);

        repo.emptyNext = true;
        final emptied = await opened.coordinator.reload();
        expect(emptied, isA<LoadEmpty>());
        expect(opened.application.revision, isNull);
        expect(repo.loads, 2);

        final again = _LoadHold();
        repo.nextHold = again;
        opened.transport.deliver(_remote('1', opened.fingerprint));
        await again.entered.future;
        expect(repo.loads, 3);
        again.release.complete();
        await _turns(4);
        expect(opened.application.revision, 1);
      },
    );

    test('an explicit empty load clears a stale fingerprint check', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);

      opened.transport.deliver(_remote('1', _otherFingerprint));
      await _turns(4);
      expect(repo.loads, 1);
      opened.transport.deliver(_remote('1', _otherFingerprint));
      await _turns(4);
      expect(repo.loads, 1);

      repo.emptyNext = true;
      expect(await opened.coordinator.reload(), isA<LoadEmpty>());
      expect(await opened.coordinator.reload(), isA<LoadReady>());
      expect(opened.application.revision, 1);

      final again = _LoadHold();
      repo.nextHold = again;
      opened.transport.deliver(_remote('1', _otherFingerprint));
      await again.entered.future;
      expect(repo.loads, 4);
      again.release.complete();
    });

    test(
      'a notice that reads empty storage still suppresses that revision',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        repo.emptyNext = true;

        opened.transport.deliver(_remote('4', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 1);
        expect(opened.application.revision, isNull);

        opened.transport.deliver(_remote('4', opened.fingerprint));
        await _turns(4);
        expect(repo.loads, 1);

        final higher = _LoadHold();
        repo.nextHold = higher;
        opened.transport.deliver(_remote('5', opened.fingerprint));
        await higher.entered.future;
        expect(repo.loads, 2);
        higher.release.complete();
      },
    );

    test('a conflict stays failed while reload catches up', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final other = FulfilmentApplication(repository: repo);
      expect(await other.load(), isA<LoadReady>());
      expect(await reserve(other), isA<FulfilmentCommitted<ReserveResult>>());

      final conflict = await reserve(opened.application);
      final attempts = repo.commitAttempts;

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(opened.application.block, PersistenceBlock.revisionConflict);
      opened.transport.deliver(_remote('2', opened.fingerprint));
      await _turns(6);

      expect(conflict, isA<FulfilmentBlocked<ReserveResult>>());
      expect(opened.application.revision, 2);
      expect(opened.application.block, isNull);
      expect(repo.commitAttempts, attempts);
    });
  });

  group('FulfilmentTabCoordinator page resume', () {
    test('a resume reloads without a notice', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final before = opened.transport.notices.length;
      final hold = _LoadHold();
      repo.nextHold = hold;

      opened.visibility.resume();
      await hold.entered.future;

      expect(repo.loads, 1);
      hold.release.complete();
      await _turns(4);
      expect(repo.loads, 1);
      expect(opened.application.revision, 1);
      expect(opened.transport.notices, hasLength(before));
      expect(repo.commitAttempts, 1);
    });

    test('a hidden visibility change does not reload', () async {
      expect(resumesWhenVisible('hidden'), isFalse);
      expect(resumesWhenVisible('prerender'), isFalse);
      expect(resumesWhenVisible('visible'), isTrue);

      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      await _turns(4);

      expect(opened.visibility.listened, isTrue);
      expect(repo.loads, 0);
    });

    test('the initial visible state does not reload', () async {
      expect(resumesWhenRestored(false), isFalse);
      expect(resumesWhenRestored(true), isTrue);

      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      expect(opened.visibility.listened, isTrue);
      await _turns(4);

      expect(repo.loads, 0);
      expect(opened.application.revision, 1);
    });

    test('two resumes before the load starts are one reload', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final hold = _LoadHold();
      repo.nextHold = hold;

      opened.visibility.resume();
      opened.visibility.resume();
      await hold.entered.future;

      expect(repo.loads, 1);
      hold.release.complete();
      await _turns(4);
      expect(repo.loads, 1);
    });

    test('a resume during a reload schedules one follow-up', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final first = _LoadHold();
      repo.nextHold = first;
      opened.visibility.resume();
      await first.entered.future;

      final second = _LoadHold();
      repo.nextHold = second;
      opened.visibility.resume();
      opened.visibility.resume();
      first.release.complete();
      await second.entered.future;

      expect(repo.loads, 2);
      second.release.complete();
      await _turns(4);
      expect(repo.loads, 2);
    });

    test('a resume during the follow-up is not lost', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final first = _LoadHold();
      repo.nextHold = first;
      opened.visibility.resume();
      await first.entered.future;

      final second = _LoadHold();
      repo.nextHold = second;
      opened.visibility.resume();
      first.release.complete();
      await second.entered.future;

      final third = _LoadHold();
      repo.nextHold = third;
      opened.visibility.resume();
      second.release.complete();
      await third.entered.future;

      expect(repo.loads, 3);
      third.release.complete();
      await _turns(4);
      expect(repo.loads, 3);
    });

    test('a resume bypasses an unresolved revision', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final hold = _LoadHold();
      repo.nextHold = hold;
      opened.transport.deliver(_remote('9', opened.fingerprint));
      await hold.entered.future;
      hold.release.complete();
      await _turns(4);
      expect(repo.loads, 1);

      opened.transport.deliver(_remote('9', opened.fingerprint));
      await _turns(4);
      expect(repo.loads, 1);

      final resume = _LoadHold();
      repo.nextHold = resume;
      opened.visibility.resume();
      await resume.entered.future;
      expect(repo.loads, 2);
      resume.release.complete();
      await _turns(4);

      opened.transport.deliver(_remote('9', opened.fingerprint));
      await _turns(4);
      expect(repo.loads, 2);
      expect(opened.application.revision, 1);
    });

    test('a resume bypasses a fingerprint mismatch check', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      opened.transport.deliver(_remote('1', _otherFingerprint));
      await _turns(4);
      expect(repo.loads, 1);
      opened.transport.deliver(_remote('1', _otherFingerprint));
      await _turns(4);
      expect(repo.loads, 1);

      final resume = _LoadHold();
      repo.nextHold = resume;
      opened.visibility.resume();
      await resume.entered.future;
      expect(repo.loads, 2);
      resume.release.complete();
      await _turns(4);

      opened.transport.deliver(_remote('1', _otherFingerprint));
      await _turns(4);
      expect(repo.loads, 2);
      expect(opened.application.fingerprint, opened.fingerprint);
    });

    test(
      'a resume during a local command waits and does not retry it',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final commit = repo.holdNextCommit();
        final reserving = reserve(opened.application);
        await commit.started;
        final load = _LoadHold();
        repo.nextHold = load;

        opened.visibility.resume();
        commit.release();
        final reserved = await reserving;

        expect(reserved, isA<FulfilmentCommitted<ReserveResult>>());
        final attempts = repo.commitAttempts;
        await load.entered.future;
        expect(repo.loads, 1);
        expect(repo.commitAttempts, attempts);
        load.release.complete();
        await _turns(4);
        expect(opened.application.revision, 2);
        expect(repo.commitAttempts, attempts);
        expect(opened.transport.notices, hasLength(2));
      },
    );

    test('close stops resume reloads and closes visibility once', () async {
      final repo = _LoadGateRepository();
      final opened = await _imported(repo);
      final hold = _LoadHold();
      repo.nextHold = hold;
      opened.visibility.resume();
      await hold.entered.future;
      opened.visibility.resume();

      opened.coordinator.close();
      opened.coordinator.close();
      hold.release.complete();
      await _turns(4);

      expect(repo.loads, 1);
      expect(opened.visibility.closeCount, 1);
      expect(opened.transport.closeCount, 1);
      opened.visibility.resume();
      await _turns(4);
      expect(repo.loads, 1);
      expect(opened.coordinator.isClosed, isTrue);
    });

    test('a throwing visibility close stays closed', () async {
      final visibility = _FakePageVisibility(throwOnClose: true);
      final repo = _LoadGateRepository();
      final opened = _Opened(
        senderId: _senderId,
        repository: repo,
        visibility: visibility,
      );
      expect(
        await opened.application.importDataset(datasetBytes()),
        isA<FulfilmentImported>(),
      );

      expect(opened.coordinator.close, returnsNormally);
      opened.coordinator.close();

      expect(opened.coordinator.isClosed, isTrue);
      expect(visibility.closeCount, 1);
      expect(opened.transport.closeCount, 1);
      visibility.resume();
      await _turns(4);
      expect(repo.loads, 0);
      await expectLater(
        opened.coordinator.reload(),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a notice and an explicit reload still run with visibility attached',
      () async {
        final repo = _LoadGateRepository();
        final opened = await _imported(repo);
        final hold = _LoadHold();
        repo.nextHold = hold;

        opened.transport.deliver(_remote('2', opened.fingerprint));
        await hold.entered.future;
        expect(repo.loads, 1);
        hold.release.complete();
        await _turns(4);
        expect(repo.loads, 1);

        final result = await opened.coordinator.reload();
        expect(result, isA<LoadReady>());
        expect((result as LoadReady).state.revision, 1);
        expect(repo.loads, 2);
        expect(opened.transport.notices, hasLength(1));
      },
    );
  });
}

const _senderId = '0123456789abcdef0123456789abcdef';

const _otherFingerprint =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

StorageChangeNotice _remote(
  String revision,
  String fingerprint, [
  String senderId = 'remote-tab',
]) {
  return StorageChangeNotice(
    revision: revision,
    fingerprint: fingerprint,
    senderId: senderId,
  );
}

Future<void> _turns(int count) async {
  for (var index = 0; index < count; index++) {
    await Future<void>.value();
  }
}

Future<_Opened> _imported(_LoadGateRepository repository) async {
  final opened = _Opened(repository: repository, senderId: _senderId);
  expect(
    await opened.application.importDataset(datasetBytes()),
    isA<FulfilmentImported>(),
  );
  opened.fingerprint = opened.application.fingerprint!;
  opened.sender = opened.coordinator.senderId;
  return opened;
}

final class _LoadHold {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
}

final class _LoadGateRepository extends MemoryFulfilmentRepository {
  _LoadHold? nextHold;
  var loads = 0;
  var failNext = false;
  var throwNext = false;
  var emptyNext = false;

  @override
  Future<LoadResult> load() async {
    loads++;
    final hold = nextHold;
    nextHold = null;
    if (hold != null && !hold.entered.isCompleted) hold.entered.complete();
    if (hold != null) await hold.release.future;
    if (throwNext) {
      throwNext = false;
      throw StateError('reload failed');
    }
    if (emptyNext) {
      emptyNext = false;
      return const LoadEmpty();
    }
    if (failNext) {
      failNext = false;
      return const LoadStorageFailed();
    }
    return super.load();
  }
}

final class _Opened {
  _Opened({
    bool available = true,
    bool throwOnPublish = false,
    bool throwOnClose = false,
    String? senderId,
    MemoryFulfilmentRepository? repository,
    _FakePageVisibility? visibility,
  }) : transport = _RecordingTransport(
         available: available,
         throwOnPublish: throwOnPublish,
         throwOnClose: throwOnClose,
       ),
       repository = repository ?? MemoryFulfilmentRepository(),
       visibility = visibility ?? _FakePageVisibility() {
    coordinator = FulfilmentTabCoordinator.open(
      repository: this.repository,
      databaseName: 'retail-offline-test',
      transport: transport,
      visibility: this.visibility,
      senderId: senderId,
    );
  }

  final MemoryFulfilmentRepository repository;
  final _RecordingTransport transport;
  final _FakePageVisibility visibility;
  late final FulfilmentTabCoordinator coordinator;
  late String fingerprint;
  late String sender;

  FulfilmentApplication get application => coordinator.application;
}

final class _FakePageVisibility implements PageVisibility {
  _FakePageVisibility({this.throwOnClose = false});

  final bool throwOnClose;
  var closeCount = 0;
  var listened = false;
  var _closed = false;
  void Function()? _onResume;

  @override
  bool get isAvailable => !_closed;

  @override
  void listen(void Function() onResume) {
    if (_closed) return;
    listened = true;
    _onResume = onResume;
  }

  void resume() {
    final listener = _onResume;
    if (listener != null) listener();
  }

  @override
  void close() {
    closeCount++;
    _closed = true;
    _onResume = null;
    if (throwOnClose) throw StateError('visibility close failed');
  }
}

final class _RecordingTransport implements StorageChangeTransport {
  _RecordingTransport({
    required this.available,
    required this.throwOnPublish,
    required this.throwOnClose,
  });

  final bool available;
  final bool throwOnPublish;
  final bool throwOnClose;
  final List<StorageChangeNotice> notices = [];
  var closeCount = 0;
  void Function(StorageChangeNotice notice)? _listener;

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
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    _listener = onNotice;
  }

  void deliver(StorageChangeNotice notice) {
    final listener = _listener;
    if (listener != null) listener(notice);
  }

  @override
  void close() {
    closeCount++;
    _listener = null;
    if (throwOnClose) throw StateError('close failed');
  }
}
