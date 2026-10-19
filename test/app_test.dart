import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/app.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/screens/json_orders/json_orders_screen.dart';

import 'application/fulfilment_application_test.dart';
import 'support/memory_fulfilment_repository.dart';

void main() {
  group('RetailOfflineApp', () {
    testWidgets('renders the JSON import screen', (tester) async {
      final repository = _CountingRepository();

      await tester.pumpWidget(_app(repository));

      expect(find.byType(JsonImportScreen), findsOneWidget);
      expect(find.byType(FulfilmentScope), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Вибір магазину'), findsNothing);
      expect(find.byKey(const Key('json-mode-entry')), findsNothing);
    });

    testWidgets('starts loading and settles to empty', (tester) async {
      final repository = _CountingRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(tester, () => repository.loads == 1);

      expect(find.byKey(const Key('json-import-loading')), findsOneWidget);
      expect(find.text('Завантаження збережених даних…'), findsOneWidget);
      expect(find.byKey(const Key('json-import-button')), findsNothing);
      expect(_controller(tester).phase, FulfilmentUiPhase.loading);
      expect(_controller(tester).canMutate, isFalse);

      gate.complete();
      await _pumpUntil(
        tester,
        () => find.text('Імпортувати JSON').evaluate().isNotEmpty,
      );

      expect(find.text('Немає збережених даних'), findsOneWidget);
      expect(find.byKey(const Key('json-import-button')), findsOneWidget);
      expect(_controller(tester).phase, FulfilmentUiPhase.empty);
      expect(_controller(tester).canMutate, isFalse);
      expect(find.byType(JsonImportScreen), findsOneWidget);
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

      Navigator.of(tester.element(find.byType(JsonImportScreen))).push(
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
        find.byType(JsonImportScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        FulfilmentScope.read(
          tester.element(find.byType(JsonImportScreen, skipOffstage: false)),
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
      expect(find.byType(JsonImportScreen), findsOneWidget);
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

      expect(find.byType(JsonImportScreen), findsNothing);
      expect(find.byType(FulfilmentScope), findsNothing);
      expect(controller.coordinator.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unavailable storage shows the blocked import screen', (
      tester,
    ) async {
      final repository = _CountingRepository();
      await _seed(repository);
      final revision = repository.debugRevision;
      repository.debugStorageUnavailable(true);
      final gate = Completer<void>();
      repository.loadGate = gate;

      final loadsBefore = repository.loads;
      await tester.pumpWidget(_app(repository));
      await _pumpUntil(tester, () => repository.loads == loadsBefore + 1);

      expect(find.byKey(const Key('json-import-loading')), findsOneWidget);
      expect(_controller(tester).phase, FulfilmentUiPhase.loading);
      expect(_controller(tester).canMutate, isFalse);

      gate.complete();
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('json-import-blocked')).evaluate().isNotEmpty,
      );

      expect(_controller(tester).phase, FulfilmentUiPhase.blocked);
      expect(_controller(tester).canMutate, isFalse);
      expect(find.text('Роботу призупинено'), findsOneWidget);
      expect(find.text('Не вдалося відкрити збережені дані.'), findsOneWidget);
      expect(find.byKey(const Key('json-import-button')), findsNothing);
      expect(find.text('Вибір магазину'), findsNothing);
      expect(repository.debugRevision, revision);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a restored dataset stays on the ready screen', (tester) async {
      final repository = _CountingRepository();
      await _seed(repository);

      await tester.pumpWidget(_app(repository));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('json-view-orders')).evaluate().isNotEmpty,
      );
      final controller = _controller(tester);

      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(find.text('Магазин Тест'), findsOneWidget);
      expect(find.text('Store_01-A'), findsNothing);
      expect(controller.session!.dataset.dbName, 'Store_01-A');
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Вибір магазину'), findsNothing);
      expect(repository.loads, greaterThan(0));

      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _pumpUntil(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
        step: const Duration(milliseconds: 50),
      );

      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(
        FulfilmentScope.read(tester.element(find.byType(JsonOrdersScreen))),
        same(controller),
      );
      expect(
        find.byType(JsonImportScreen, skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(find.byType(BackButton));
      await _pumpUntil(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isEmpty,
        step: const Duration(milliseconds: 50),
      );

      expect(find.byKey(const Key('json-view-orders')), findsOneWidget);
      expect(find.byType(JsonImportScreen), findsOneWidget);
      expect(_controller(tester), same(controller));
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
  return FulfilmentScope.read(tester.element(find.byType(JsonImportScreen)));
}

void _insertOverlay(WidgetTester tester, WidgetBuilder builder) {
  final context = tester.element(find.byType(JsonImportScreen));
  Navigator.of(context).overlay!.insert(OverlayEntry(builder: builder));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration step = Duration.zero,
}) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (done()) return;
    await tester.pump(step);
  }
  fail('timed out waiting for the app');
}

Future<void> _seed(_CountingRepository repository) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'app-test-seed',
  );
  try {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (controller.phase == FulfilmentUiPhase.empty) break;
      await Future<void>.value();
    }
    expect(controller.phase, FulfilmentUiPhase.empty);
    expect(
      await controller.importDataset(datasetBytes()),
      isA<FulfilmentImported>(),
    );
  } finally {
    controller.dispose();
  }
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
