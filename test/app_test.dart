import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/app.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/store_selection/store_selection_screen.dart';

import 'support/memory_fulfilment_repository.dart';

void main() {
  group('RetailOfflineApp', () {
    testWidgets('renders store selection', (tester) async {
      final repository = _CountingRepository();

      await tester.pumpWidget(_app(repository));

      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(find.byType(FulfilmentScope), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('starts loading and settles to empty', (tester) async {
      final repository = _CountingRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(tester, () => repository.loads == 1);
      await _showPhase(tester);

      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(find.text('phase:loading'), findsOneWidget);
      expect(_controller(tester).phase, FulfilmentUiPhase.loading);

      gate.complete();
      await _pumpUntil(
        tester,
        () => find.text('phase:empty').evaluate().isNotEmpty,
      );

      expect(find.text('phase:empty'), findsOneWidget);
      expect(_controller(tester).phase, FulfilmentUiPhase.empty);
      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(repository.loads, 1);
    });

    testWidgets('a descendant reads the controller with FulfilmentScope.of', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      late FulfilmentUiController seen;

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(tester, () => repository.loads == 1);
      _insertOverlay(tester, (context) {
        seen = FulfilmentScope.of(context);
        return const Text('from-descendant');
      });
      await tester.pump();

      expect(find.text('from-descendant'), findsOneWidget);
      expect(seen, same(_controller(tester)));
      expect(seen.phase, FulfilmentUiPhase.loading);

      gate.complete();
      await _pumpUntil(tester, () => seen.phase == FulfilmentUiPhase.empty);

      expect(seen.phase, FulfilmentUiPhase.empty);
      expect(seen, same(_controller(tester)));
    });

    testWidgets('a pushed route reads the same controller', (tester) async {
      final repository = _CountingRepository();
      late FulfilmentUiController seen;

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(
        tester,
        () => _controller(tester).phase == FulfilmentUiPhase.empty,
      );
      final beforePush = _controller(tester);

      Navigator.of(tester.element(find.byType(StoreSelectionScreen))).push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            seen = FulfilmentScope.of(context);
            return const Text('from-route');
          },
        ),
      );
      await tester.pump();

      expect(find.text('from-route'), findsOneWidget);
      expect(seen, same(beforePush));
      expect(
        find.byType(StoreSelectionScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        FulfilmentScope.read(
          tester.element(
            find.byType(StoreSelectionScreen, skipOffstage: false),
          ),
        ),
        same(seen),
      );
    });

    testWidgets('rebuilding the root keeps the same controller', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final transport = _Transport();
      final visibility = _Pages();

      await tester.pumpWidget(
        _app(repository, transport: transport, visibility: visibility),
      );
      await _pumpUntil(
        tester,
        () => _controller(tester).phase == FulfilmentUiPhase.empty,
      );
      final first = _controller(tester);
      final coordinator = first.coordinator;

      await tester.pumpWidget(
        _app(repository, transport: transport, visibility: visibility),
      );

      expect(_controller(tester), same(first));
      expect(_controller(tester).coordinator, same(coordinator));
      expect(coordinator.isClosed, isFalse);
      expect(repository.loads, 1);
      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(find.byType(FulfilmentScope), findsOneWidget);
    });

    testWidgets('unmounting the root closes the coordinator', (tester) async {
      final repository = _CountingRepository();

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(
        tester,
        () => _controller(tester).phase == FulfilmentUiPhase.empty,
      );
      final controller = _controller(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(find.byType(StoreSelectionScreen), findsNothing);
      expect(find.byType(FulfilmentScope), findsNothing);
      expect(controller.coordinator.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unavailable storage leaves store selection on screen', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final gate = Completer<void>();
      repository.debugStorageUnavailable(true);
      repository.loadGate = gate;

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(tester, () => repository.loads == 1);

      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(_controller(tester).phase, FulfilmentUiPhase.loading);

      gate.complete();
      await _pumpUntil(
        tester,
        () => _controller(tester).phase == FulfilmentUiPhase.blocked,
      );

      expect(_controller(tester).phase, FulfilmentUiPhase.blocked);
      expect(_controller(tester).canMutate, isFalse);
      expect(find.byType(StoreSelectionScreen), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

const _databaseName = 'retail-offline-app-test';

RetailOfflineApp _app(
  _CountingRepository repository, {
  StorageChangeTransport? transport,
  PageVisibility? visibility,
}) {
  return RetailOfflineApp(
    repository: repository,
    databaseName: _databaseName,
    transport: transport ?? _Transport(),
    visibility: visibility ?? _Pages(),
  );
}

FulfilmentUiController _controller(WidgetTester tester) {
  return FulfilmentScope.read(
    tester.element(find.byType(StoreSelectionScreen)),
  );
}

Future<void> _showPhase(WidgetTester tester) async {
  _insertOverlay(tester, (context) {
    final phase = FulfilmentScope.of(context).phase;
    return Text('phase:${phase.name}');
  });
  await tester.pump();
}

void _insertOverlay(WidgetTester tester, WidgetBuilder builder) {
  final context = tester.element(find.byType(StoreSelectionScreen));
  Navigator.of(context).overlay!.insert(OverlayEntry(builder: builder));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (done()) return;
    await tester.pump();
  }
  fail('timed out waiting for the app');
}

final class _CountingRepository extends MemoryFulfilmentRepository {
  Completer<void>? loadGate;
  var loads = 0;

  @override
  Future<LoadResult> load() async {
    loads++;
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    return super.load();
  }
}

final class _Pages implements PageVisibility {
  @override
  bool get isAvailable => true;

  @override
  void listen(void Function() onResume) {}

  @override
  void close() {}
}

final class _Transport implements StorageChangeTransport {
  @override
  bool get isAvailable => true;

  @override
  bool publish(StorageChangeNotice notice) => true;

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {}

  @override
  void close() {}
}
