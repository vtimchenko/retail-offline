import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/app.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/core/constants/app_constants.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/services/file/json_file_service.dart';
import 'package:retail_offline/services/file/picked_bytes.dart';

import '../application/fulfilment_application_test.dart';
import '../support/memory_fulfilment_repository.dart';

void main() {
  group('JSON import screen', () {
    testWidgets('is the app root under one scope', (tester) async {
      final repository = MemoryFulfilmentRepository();

      await tester.pumpWidget(_app(repository));
      await _until(tester, () {
        if (find.byType(JsonImportScreen).evaluate().isEmpty) return false;
        return _controllerOf(tester, find.byType(JsonImportScreen)).phase ==
            FulfilmentUiPhase.empty;
      });

      expect(find.byType(JsonImportScreen), findsOneWidget);
      expect(find.byType(FulfilmentScope), findsOneWidget);
      expect(find.text(AppStrings.jsonScreenTitle), findsOneWidget);
      expect(find.text('JSON-режим'), findsNothing);
      expect(find.text('Вибір магазину'), findsNothing);
      expect(find.byKey(const Key('json-mode-entry')), findsNothing);
      expect(find.text('Імпортувати JSON'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).canMutate,
        isFalse,
      );
    });

    testWidgets('shows a loading message while saved data is read', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.pumpWidget(_host(repository));
      await _until(tester, () => repository.loads == 1);

      expect(find.byKey(const Key('json-import-loading')), findsOneWidget);
      expect(find.text('Завантаження збережених даних…'), findsOneWidget);
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(find.byKey(const Key('json-store-name')), findsNothing);

      gate.complete();
      await _until(
        tester,
        () => find.text('Імпортувати JSON').evaluate().isNotEmpty,
      );
    });

    testWidgets('offers JSON import when storage is empty', (tester) async {
      final repository = MemoryFulfilmentRepository();

      await tester.pumpWidget(_host(repository));
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      expect(find.text('Немає збережених даних'), findsOneWidget);
      expect(find.text('Імпортувати JSON'), findsOneWidget);
      expect(_importEnabled(tester), isTrue);
      expect(find.byKey(const Key('json-import-error')), findsNothing);
      expect(find.byKey(const Key('json-store-name')), findsNothing);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).session,
        isNull,
      );
    });

    testWidgets('imports a local JSON file and shows dataset metadata', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();

      await tester.pumpWidget(
        _host(repository, picker: _file('dataset.json', datasetBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      _expectDataset(tester);
      _expectReadyHierarchy(tester);
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(find.byKey(const Key('json-import-error')), findsNothing);
      final controller = _controllerOf(tester, find.byType(JsonImportScreen));
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.dataset.orders, hasLength(2));
      expect(controller.session!.dataset.dbName, 'Store_01-A');
      expect(repository.commitAttempts, 1);
      expect(repository.debugRevision, 1);
    });

    testWidgets('issued count follows issued and exported orders', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await tester.pumpWidget(
        _host(repository, picker: _file('dataset.json', datasetBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);
      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.byKey(const Key('json-issued-count')).evaluate().isNotEmpty,
      );
      final controller = _controllerOf(tester, find.byType(JsonImportScreen));
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '0',
      );
      expect(_issuedAmount(tester), '0,00');

      expect(
        await controller.reserve(
          orderId: 'ORD-1',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 2,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await controller.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '1',
      );
      expect(_issuedAmount(tester), '649,00');

      expect(
        await controller.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 12),
        ),
        isA<FulfilmentExported>(),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '1',
      );
      expect(_issuedAmount(tester), '649,00');
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);

      expect(
        await controller.reserve(
          orderId: 'ORD-2',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();
      expect(_issuedAmount(tester), '649,00');
      expect(
        await controller.issueOrder('ORD-2'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '2',
      );
      expect(_issuedAmount(tester), '973,50');
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.issued);

      expect(await controller.refresh(), isA<LoadReady>());
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '2',
      );
      expect(_issuedAmount(tester), '973,50');
      expect(
        tester.widget<Text>(find.byKey(const Key('json-order-count'))).data,
        '2',
      );
    });

    testWidgets('issued amount adds order totals in kopecks', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await tester.pumpWidget(
        _host(repository, picker: _file('dataset.json', _precisionBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);
      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.byKey(const Key('json-issued-amount')).evaluate().isNotEmpty,
      );
      final controller = _controllerOf(tester, find.byType(JsonImportScreen));
      expect(find.text(AppStrings.jsonOrdersLabel), findsOneWidget);
      expect(find.text(AppStrings.jsonIssuedCountLabel), findsOneWidget);
      expect(find.text(AppStrings.jsonIssuedAmountLabel), findsOneWidget);
      expect(_issuedAmount(tester), '0,00');
      expect(
        controller.session!.dataset.orders
            .firstWhere((order) => order.orderId == 'ORD-R')
            .totalMinorUnits,
        1999,
      );

      expect(
        await controller.issueOrder('ORD-R'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      await tester.pump();
      expect(_issuedAmount(tester), '19,99');

      expect(
        await controller.issueOrder('ORD-P'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      await tester.pump();
      expect(_issuedAmount(tester), '20,09');
      expect(controller.session!.statusOf('ORD-Q'), isNot(OrderStatus.issued));

      expect(
        await controller.issueOrder('ORD-Q'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      await tester.pump();
      expect(_issuedAmount(tester), '20,29');
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '3',
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_issuedAmount(tester), '20,29');
      for (final key in const [
        'json-order-count',
        'json-issued-count',
        'json-issued-amount',
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.width, greaterThan(8));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
      }
    });

    testWidgets('issued amount follows a remote tab and a restore', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _NotifyingTransport();
      await tester.pumpWidget(
        _host(
          repository,
          picker: _file('dataset.json', datasetBytes()),
          transport: transport,
        ),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);
      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.byKey(const Key('json-issued-amount')).evaluate().isNotEmpty,
      );
      expect(_issuedAmount(tester), '0,00');
      final controller = _controllerOf(tester, find.byType(JsonImportScreen));

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.reserve(
          orderId: 'ORD-1',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 2,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      expect(
        await other.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(tester, () => _issuedAmount(tester) == '649,00');
      expect(
        tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
        '1',
      );

      expect(await controller.refresh(), isA<LoadReady>());
      await tester.pump();
      expect(_issuedAmount(tester), '649,00');
    });

    testWidgets('shows a restored session without asking to import again', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);
      var picks = 0;

      await tester.pumpWidget(
        _host(
          repository,
          picker: () async {
            picks++;
            return null;
          },
        ),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      _expectDataset(tester);
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(picks, 0);
      expect(repository.commitAttempts, 1);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).phase,
        FulfilmentUiPhase.ready,
      );
    });

    testWidgets('a blocked load explains the failure and retries only on tap', (
      tester,
    ) async {
      final repository = _GatedRepository();
      repository.debugStorageUnavailable(true);

      await tester.pumpWidget(_host(repository));
      await _until(
        tester,
        () => find
            .text('Не вдалося відкрити збережені дані.')
            .evaluate()
            .isNotEmpty,
      );

      expect(find.byKey(const Key('json-import-blocked')), findsOneWidget);
      expect(find.text('Роботу призупинено'), findsOneWidget);
      expect(find.text('Спробувати ще раз'), findsOneWidget);
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(repository.loads, 1);
      expect(repository.commitAttempts, 0);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, 1);

      repository.debugStorageUnavailable(false);
      await tester.tap(find.byKey(const Key('json-import-retry')));
      await _until(
        tester,
        () => find.text('Імпортувати JSON').evaluate().isNotEmpty,
      );

      expect(repository.loads, 2);
      expect(repository.commitAttempts, 0);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).phase,
        FulfilmentUiPhase.empty,
      );
    });

    testWidgets('a revision conflict is not retried and does not overwrite', (
      tester,
    ) async {
      final repository = _ConflictRepository();

      await tester.pumpWidget(
        _host(repository, picker: _file('dataset.json', datasetBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.textContaining('іншій вкладці').evaluate().isNotEmpty,
      );

      expect(find.textContaining('не перезаписано'), findsOneWidget);
      expect(find.text('Імпортувати JSON'), findsNothing);
      expect(repository.imports, 1);
      expect(repository.loads, 1);
      expect(repository.debugRevision, isNull);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).session,
        isNull,
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.imports, 1);
      expect(repository.loads, 1);

      await tester.tap(find.byKey(const Key('json-import-retry')));
      await _until(
        tester,
        () => find.text('Імпортувати JSON').evaluate().isNotEmpty,
      );

      expect(repository.loads, 2);
      expect(repository.imports, 1);
      expect(repository.debugRevision, isNull);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).phase,
        FulfilmentUiPhase.empty,
      );
    });

    testWidgets('a rejected file shows an error and keeps storage empty', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();

      await tester.pumpWidget(
        _host(
          repository,
          picker: _file('broken.json', Uint8List.fromList(utf8.encode('{'))),
        ),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.byKey(const Key('json-import-error')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('Некоректний JSON'), findsOneWidget);
      expect(find.text('Імпортувати JSON'), findsOneWidget);
      expect(_importEnabled(tester), isTrue);
      expect(find.byKey(const Key('json-store-name')), findsNothing);
      final controller = _controllerOf(tester, find.byType(JsonImportScreen));
      expect(controller.phase, FulfilmentUiPhase.empty);
      expect(controller.session, isNull);
      expect(repository.commitAttempts, 0);
      expect(repository.debugRevision, isNull);
    });

    testWidgets('cancelling the file chooser shows no error', (tester) async {
      final repository = MemoryFulfilmentRepository();
      var picks = 0;

      await tester.pumpWidget(
        _host(
          repository,
          picker: () async {
            picks++;
            return null;
          },
        ),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await tester.pump();

      expect(picks, 1);
      expect(find.byKey(const Key('json-import-error')), findsNothing);
      expect(find.text('Імпортувати JSON'), findsOneWidget);
      expect(_importEnabled(tester), isTrue);
      expect(repository.commitAttempts, 0);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).phase,
        FulfilmentUiPhase.empty,
      );
    });

    testWidgets('a second import is not started while the first is running', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final hold = repository.holdNextCommit();
      addTearDown(hold.release);

      await tester.pumpWidget(
        _host(repository, picker: _file('dataset.json', datasetBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-import-progress')).evaluate().isNotEmpty,
      );

      expect(find.text('Імпорт JSON…'), findsOneWidget);
      expect(_importEnabled(tester), isFalse);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.descendant(
                of: find.byKey(const Key('json-import-progress')),
                matching: find.byType(CircularProgressIndicator),
              ),
            )
            .color,
        Colors.white,
      );
      expect(repository.commitAttempts, 1);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.commitAttempts, 1);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).phase,
        FulfilmentUiPhase.empty,
      );

      hold.release();
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      _expectDataset(tester);
      expect(repository.commitAttempts, 1);
      expect(find.text('Імпортувати JSON'), findsNothing);
    });

    testWidgets('leaving during file selection does not import', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final gate = Completer<PickedBytes?>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete(null);
      });

      await tester.pumpWidget(_host(repository, picker: () => gate.future));
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await tester.pump();
      expect(_importEnabled(tester), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete((name: 'dataset.json', bytes: datasetBytes()));
      await tester.pump();

      expect(repository.commitAttempts, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file that is not JSON is not imported', (tester) async {
      final repository = MemoryFulfilmentRepository();

      await tester.pumpWidget(
        _host(repository, picker: _file('notes.txt', datasetBytes())),
      );
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      await tester.tap(find.byKey(const Key('json-import-button')));
      await _until(
        tester,
        () => find.byKey(const Key('json-import-error')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('Потрібен файл JSON'), findsOneWidget);
      expect(_importEnabled(tester), isTrue);
      expect(repository.commitAttempts, 0);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)).session,
        isNull,
      );
    });
  });
}

const _databaseName = 'retail-offline-json-import-test';

RetailOfflineApp _app(MemoryFulfilmentRepository repository) {
  return RetailOfflineApp(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
  );
}

Widget _host(
  FulfilmentRepository repository, {
  Future<PickedBytes?> Function()? picker,
  Widget? child,
  StorageChangeTransport? transport,
}) {
  return _JsonHost(
    repository: repository,
    picker: picker,
    transport: transport,
    child: child,
  );
}

Future<PickedBytes?> Function() _file(String name, Uint8List bytes) {
  return () async => (name: name, bytes: bytes);
}

void _expectReadyHierarchy(WidgetTester tester) {
  final storeSize = tester
      .widget<Text>(find.byKey(const Key('json-store-name')))
      .style
      ?.fontSize;
  final countSize = tester
      .widget<Text>(find.byKey(const Key('json-order-count')))
      .style
      ?.fontSize;
  final issuedSize = tester
      .widget<Text>(find.byKey(const Key('json-issued-count')))
      .style
      ?.fontSize;
  final amountSize = tester
      .widget<Text>(find.byKey(const Key('json-issued-amount')))
      .style
      ?.fontSize;
  expect(storeSize, isNotNull);
  expect(countSize, isNotNull);
  expect(issuedSize, countSize);
  expect(amountSize, countSize);
  expect(storeSize!, greaterThan(countSize!));
  expect(find.byKey(const Key('json-db-name')), findsNothing);
  expect(find.text(AppStrings.jsonDbNameLabel), findsNothing);
  expect(
    tester.getTopLeft(find.byKey(const Key('json-order-count'))).dy,
    tester.getTopLeft(find.byKey(const Key('json-issued-count'))).dy,
  );
  expect(
    tester.getTopLeft(find.byKey(const Key('json-issued-amount'))).dy,
    tester.getTopLeft(find.byKey(const Key('json-issued-count'))).dy,
  );
  expect(
    tester.getTopLeft(find.byKey(const Key('json-view-orders'))).dy,
    lessThan(
      tester.getTopLeft(find.byKey(const Key('json-replace-dataset'))).dy,
    ),
  );
  expect(
    tester.getSize(find.byKey(const Key('json-replace-dataset'))).height,
    greaterThanOrEqualTo(52),
  );
}

void _expectDataset(WidgetTester tester) {
  expect(find.byKey(const Key('json-store-name')), findsOneWidget);
  expect(
    tester.widget<Text>(find.byKey(const Key('json-store-name'))).data,
    'Магазин Тест',
  );
  expect(find.byKey(const Key('json-db-name')), findsNothing);
  expect(
    tester.widget<Text>(find.byKey(const Key('json-date-create'))).data,
    '03.10.2026 11:46',
  );
  expect(
    tester.widget<Text>(find.byKey(const Key('json-order-count'))).data,
    '2',
  );
  expect(
    tester.widget<Text>(find.byKey(const Key('json-issued-count'))).data,
    '0',
  );
  expect(_issuedAmount(tester), '0,00');
  expect(find.text(AppStrings.jsonIssuedAmountLabel), findsOneWidget);
}

bool _importEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(const Key('json-import-button')))
          .onPressed !=
      null;
}

FulfilmentUiController _controllerOf(WidgetTester tester, Finder finder) {
  return FulfilmentScope.read(tester.element(finder));
}

Future<void> _untilPhase(WidgetTester tester, FulfilmentUiPhase phase) {
  return _until(
    tester,
    () => _controllerOf(tester, find.byType(JsonImportScreen)).phase == phase,
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (done()) {
      // The phase can change after the frame that observed it.
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for the JSON import screen');
}

Future<void> _seed(MemoryFulfilmentRepository repository) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-import-seed',
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

class _JsonHost extends StatefulWidget {
  const _JsonHost({
    required this.repository,
    this.picker,
    this.transport,
    this.child,
  });

  final FulfilmentRepository repository;
  final Future<PickedBytes?> Function()? picker;
  final StorageChangeTransport? transport;
  final Widget? child;

  @override
  State<_JsonHost> createState() => _JsonHostState();
}

class _JsonHostState extends State<_JsonHost> {
  late final FulfilmentUiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FulfilmentUiController.open(
      repository: widget.repository,
      databaseName: _databaseName,
      transport: widget.transport ?? _Transport(),
      visibility: _Pages(),
      senderId: 'json-import-test',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FulfilmentScope(
      controller: _controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home:
            widget.child ??
            JsonImportScreen(
              fileService: widget.picker == null
                  ? null
                  : JsonFileService(picker: widget.picker),
            ),
      ),
    );
  }
}

final class _GatedRepository extends MemoryFulfilmentRepository {
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

final class _ConflictRepository extends MemoryFulfilmentRepository {
  var loads = 0;
  var imports = 0;

  @override
  Future<LoadResult> load() async {
    loads++;
    return super.load();
  }

  @override
  Future<CommitResult> importDataset({
    required Uint8List bytes,
    required String fingerprint,
    required SessionSnapshot snapshot,
  }) async {
    imports++;
    return const CommitRevisionConflict();
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

final class _NotifyingTransport implements StorageChangeTransport {
  void Function(StorageChangeNotice notice)? _listener;

  void deliver(StorageChangeNotice notice) {
    _listener?.call(notice);
  }

  @override
  bool get isAvailable => true;

  @override
  bool publish(StorageChangeNotice notice) => true;

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    _listener = onNotice;
  }

  @override
  void close() {
    _listener = null;
  }
}

String _issuedAmount(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(const Key('json-issued-amount'))).data!;
}

Uint8List _precisionBytes() {
  const json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
      '"ProductID":1290564103789190763,"SerialNumber":"SN-0001","Quantity":5}],'
      '"orders":['
      '{"OrderID":"ORD-R","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-R","OrderNumber":1,'
      '"Customer":"Клієнт","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Товар","ProductID":1290564103789190763,"Quantity":2,'
      '"Price":10.00,"Amount":19.99,"isServiceGood":1,"isParcel":0}]},'
      '{"OrderID":"ORD-P","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-P","OrderNumber":2,'
      '"Customer":"Клієнт","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Товар","ProductID":1290564103789190763,"Quantity":1,'
      '"Price":0.10,"Amount":0.10,"isServiceGood":1,"isParcel":0}]},'
      '{"OrderID":"ORD-Q","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-Q","OrderNumber":3,'
      '"Customer":"Клієнт","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Товар","ProductID":1290564103789190763,"Quantity":1,'
      '"Price":0.20,"Amount":0.20,"isServiceGood":1,"isParcel":0}]}]}';
  return Uint8List.fromList(utf8.encode(json));
}
