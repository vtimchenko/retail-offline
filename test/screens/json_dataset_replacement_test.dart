import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/core/constants/app_constants.dart';
import 'package:retail_offline/core/constants/import_messages.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/screens/json_orders/json_orders_screen.dart';
import 'package:retail_offline/services/file/json_file_service.dart';
import 'package:retail_offline/services/file/picked_bytes.dart';

import '../application/fulfilment_application_test.dart';
import '../support/memory_fulfilment_repository.dart';

void main() {
  group('JSON dataset replacement', () {
    testWidgets(
      'offers replacement on the ready import screen and hides it on orders',
      (tester) async {
        final repository = MemoryFulfilmentRepository();
        await _seed(repository);

        await tester.pumpWidget(_host(repository));
        await _until(
          tester,
          () => find.text('Магазин Тест').evaluate().isNotEmpty,
        );

        expect(find.byKey(const Key('json-replace-dataset')), findsOneWidget);
        expect(_replaceEnabled(tester, JsonImportScreen), isTrue);
        expect(find.byKey(const Key('json-replace-blocked')), findsNothing);
        expect(find.byKey(const Key('json-view-orders')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('json-date-create'))).data,
          '03.10.2026 11:46',
        );

        await tester.tap(find.byKey(const Key('json-view-orders')));
        await _until(
          tester,
          () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(JsonOrdersScreen), findsOneWidget);
        expect(find.text('Замовлення — Магазин Тест'), findsOneWidget);
        expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
        expect(_onOrders(const Key('json-replace-blocked')), findsNothing);
        expect(find.byKey(const Key('json-orders-date-create')), findsNothing);
      },
    );

    testWidgets('hides replacement while loading, empty, or blocked', (
      tester,
    ) async {
      final loading = _GatedRepository();
      final gate = Completer<void>();
      loading.loadGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.pumpWidget(_host(loading));
      await _until(tester, () => loading.loads == 1);

      expect(find.byKey(const Key('json-import-loading')), findsOneWidget);
      expect(find.byKey(const Key('json-replace-dataset')), findsNothing);

      gate.complete();
      await _untilPhase(tester, FulfilmentUiPhase.empty);

      expect(find.text(AppStrings.jsonImport), findsOneWidget);
      expect(find.byKey(const Key('json-replace-dataset')), findsNothing);

      final blocked = MemoryFulfilmentRepository();
      blocked.debugStorageUnavailable(true);
      await tester.pumpWidget(_host(blocked));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-import-blocked')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('json-replace-dataset')), findsNothing);
      expect(find.text(AppStrings.jsonReplaceDataset), findsNothing);
    });

    testWidgets('disables replacement while an issued order is not exported', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);
      var picks = 0;

      await tester.pumpWidget(
        _host(
          repository,
          child: JsonImportScreen(
            fileService: JsonFileService(
              picker: () async {
                picks++;
                return (name: 'next.json', bytes: _nextBytes());
              },
            ),
          ),
        ),
      );
      await _untilPhase(tester, FulfilmentUiPhase.ready);
      final controller = _controller(tester, find.byType(JsonImportScreen));
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

      expect(_replaceEnabled(tester, JsonImportScreen), isFalse);
      expect(find.byKey(const Key('json-replace-blocked')), findsOneWidget);
      expect(find.text(AppStrings.jsonReplaceExportFirst), findsOneWidget);

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await tester.pump();

      expect(picks, 0);
      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, 3);

      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
      expect(_onOrders(const Key('json-replace-blocked')), findsNothing);
    });

    testWidgets('partial reservations leave replacement enabled', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(repository, child: const JsonImportScreen()),
      );
      await _untilPhase(tester, FulfilmentUiPhase.ready);
      final controller = _controller(tester, find.byType(JsonImportScreen));
      expect(
        await controller.reserve(
          orderId: 'ORD-1',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(_replaceEnabled(tester, JsonImportScreen), isTrue);
      expect(find.byKey(const Key('json-replace-blocked')), findsNothing);

      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(JsonOrdersScreen),
          matching: find.text('В процесі'),
        ),
        findsOneWidget,
      );
      expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
    });

    testWidgets('a cancelled file pick leaves the dataset unchanged', (
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
      final revision = _controller(
        tester,
        find.byType(JsonImportScreen),
      ).revision;

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await tester.pump();

      expect(picks, 1);
      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
      expect(find.byKey(const Key('json-replace-error')), findsNothing);
      expect(
        _controller(tester, find.byType(JsonImportScreen)).revision,
        revision,
      );
      expect(repository.commitAttempts, 1);
    });

    testWidgets('invalid JSON does not open confirmation or write', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(repository, picker: _file('bad.json', utf8.encode('{'))),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () => find.byKey(const Key('json-replace-error')).evaluate().isNotEmpty,
      );

      expect(find.textContaining('Некоректний JSON'), findsOneWidget);
      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('json-store-name'))).data,
        'Магазин Тест',
      );
      expect(repository.commitAttempts, 1);
    });

    testWidgets('a file read error is shown without a dialog', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(
          repository,
          picker: () async {
            throw const ImportException(ImportMessages.fileReadFailed);
          },
        ),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () => find.byKey(const Key('json-replace-error')).evaluate().isNotEmpty,
      );

      expect(find.text(ImportMessages.fileReadFailed), findsOneWidget);
      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
      expect(repository.commitAttempts, 1);
    });

    testWidgets('confirmation shows both datasets and cancel writes nothing', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(repository, picker: _file('next.json', _nextBytes())),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );
      final controller = _controller(tester, find.byType(JsonImportScreen));
      final revision = controller.revision;

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-replace-dialog')).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonReplaceTitle), findsOneWidget);
      expect(find.text(AppStrings.jsonReplaceWarning), findsOneWidget);
      expect(find.text(AppStrings.jsonReplaceCurrent), findsOneWidget);
      expect(find.text(AppStrings.jsonReplaceIncoming), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-replace-current-store')))
            .data,
        'Магазин Тест',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-replace-current-db')))
            .data,
        'Store_01-A',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-replace-new-store')))
            .data,
        'Інший магазин',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('json-replace-new-db'))).data,
        'Store_02-B',
      );

      await tester.tap(find.byKey(const Key('json-replace-cancel')));
      await _until(
        tester,
        () => find.byKey(const Key('json-replace-dialog')).evaluate().isEmpty,
      );

      expect(controller.revision, revision);
      expect(controller.session!.dataset.storeName, 'Магазин Тест');
      expect(repository.commitAttempts, 1);
      expect(
        tester.widget<Text>(find.byKey(const Key('json-date-create'))).data,
        '03.10.2026 11:46',
      );
    });

    testWidgets(
      'replacement from the startup screen refreshes the order list',
      (tester) async {
        final repository = MemoryFulfilmentRepository();
        await _seed(repository);

        await tester.pumpWidget(
          _host(repository, picker: _file('next.json', _nextBytes())),
        );
        await _until(
          tester,
          () => find.byKey(const Key('json-view-orders')).evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const Key('json-view-orders')));
        await _until(
          tester,
          () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));
        final controller = _controller(tester, find.byType(JsonOrdersScreen));
        expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
        expect(find.byKey(const Key('json-orders-date-create')), findsNothing);
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
        expect(
          await controller.commitCumulativeExport(
            now: () => DateTime(2026, 10, 14, 15, 7, 22),
          ),
          isA<FulfilmentExported>(),
        );
        await tester.pump();

        expect(find.byKey(const Key('json-share-export')), findsOneWidget);
        expect(find.byKey(const Key('json-last-export-file')), findsOneWidget);
        final attempts = repository.commitAttempts;

        await tester.tap(
          find.descendant(
            of: find.byType(JsonOrdersScreen),
            matching: find.byType(BackButton),
          ),
        );
        await _until(
          tester,
          () => find.byType(JsonOrdersScreen).evaluate().isEmpty,
        );
        await tester.tap(find.byKey(const Key('json-replace-dataset')));
        await _until(
          tester,
          () => find
              .byKey(const Key('json-replace-confirm'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const Key('json-replace-confirm')));
        await _until(
          tester,
          () => find.text('Інший магазин').evaluate().isNotEmpty,
        );

        expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
        expect(
          tester.widget<Text>(find.byKey(const Key('json-store-name'))).data,
          'Інший магазин',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('json-date-create'))).data,
          '16.10.2026 12:00',
        );
        expect(find.byKey(const Key('json-db-name')), findsNothing);
        expect(controller.session!.dataset.dbName, 'Store_02-B');

        await tester.tap(find.byKey(const Key('json-view-orders')));
        await _until(
          tester,
          () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Замовлення — Інший магазин'), findsOneWidget);
        expect(find.byKey(const Key('json-orders-date-create')), findsNothing);
        expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
        expect(find.text('Новий Клієнт'), findsOneWidget);
        expect(find.text('Тестовий Клієнт А'), findsNothing);
        expect(find.byKey(const Key('json-share-export')), findsNothing);
        expect(find.byKey(const Key('json-last-export-file')), findsNothing);
        expect(
          find.descendant(
            of: find.byType(JsonOrdersScreen),
            matching: find.text('Експортовано'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(JsonOrdersScreen),
            matching: find.text('Видано'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(JsonOrdersScreen),
            matching: find.text('Без вибору'),
          ),
          findsWidgets,
        );
        expect(controller.lastExport, isNull);
        expect(controller.session!.statusOf('NEW-1'), OrderStatus.noSelection);
        expect(controller.block, isNull);
        expect(repository.commitAttempts, attempts + 1);
      },
    );

    testWidgets('a second confirm does not start another commit', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);
      final hold = repository.holdNextCommit();
      addTearDown(hold.release);

      await tester.pumpWidget(
        _host(repository, picker: _file('next.json', _nextBytes())),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-replace-confirm')).evaluate().isNotEmpty,
      );
      final attempts = repository.commitAttempts;
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('json-replace-confirm')),
      );

      confirm.onPressed!();
      confirm.onPressed!();
      await tester.pump();
      await hold.started;

      expect(repository.commitAttempts, attempts + 1);
      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);

      hold.release();
      await _until(
        tester,
        () => find.text('Інший магазин').evaluate().isNotEmpty,
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('json-store-name'))).data,
        'Інший магазин',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('json-date-create'))).data,
        '16.10.2026 12:00',
      );
      expect(repository.commitAttempts, attempts + 1);
    });

    testWidgets('a remote reload closes an open confirmation', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);
      final transport = _DeliveringTransport();

      await tester.pumpWidget(
        _host(
          repository,
          transport: transport,
          picker: _file('next.json', _nextBytes()),
        ),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-replace-dialog')).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-replace-new-store')))
            .data,
        'Інший магазин',
      );

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.replaceDataset(
          catalogue(storeName: 'Третій магазин', dbName: 'Store_03-C'),
        ),
        isA<FulfilmentReplaced>(),
      );
      final attempts = repository.commitAttempts;
      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: other.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(
        tester,
        () => find.byKey(const Key('json-replace-dialog')).evaluate().isEmpty,
      );

      expect(find.text(AppStrings.jsonReplaceStale), findsOneWidget);
      expect(find.text('Третій магазин'), findsOneWidget);
      expect(find.text('Інший магазин'), findsNothing);
      expect(
        _controller(
          tester,
          find.byType(JsonImportScreen),
        ).session!.dataset.dbName,
        'Store_03-C',
      );
      expect(repository.commitAttempts, attempts);
    });

    testWidgets('confirming a stale revision cannot overwrite the winner', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(
          repository,
          child: JsonImportScreen(
            fileService: JsonFileService(
              picker: _file('next.json', _nextBytes()),
            ),
          ),
        ),
      );
      await _untilPhase(tester, FulfilmentUiPhase.ready);
      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-replace-dialog')).evaluate().isNotEmpty,
      );

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.replaceDataset(
          catalogue(storeName: 'Третій магазин', dbName: 'Store_03-C'),
        ),
        isA<FulfilmentReplaced>(),
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-replace-confirm')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-import-blocked')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('json-replace-dialog')), findsNothing);
      expect(find.text(AppStrings.jsonReplaceStale), findsNothing);
      expect(find.text(AppStrings.jsonRevisionConflict), findsOneWidget);
      expect(repository.commitAttempts, attempts + 1);
      expect((await persisted(repository)).dataset.storeName, 'Третій магазин');

      await tester.tap(find.byKey(const Key('json-import-retry')));
      await _until(
        tester,
        () => find.text('Третій магазин').evaluate().isNotEmpty,
      );

      expect(find.text('Інший магазин'), findsNothing);
      expect(find.byType(JsonImportScreen), findsOneWidget);
      expect(
        _controller(
          tester,
          find.byType(JsonImportScreen),
        ).session!.dataset.storeName,
        'Третій магазин',
      );
      expect(repository.commitAttempts, attempts + 1);
    });

    testWidgets('narrow layouts do not overflow', (tester) async {
      await _setSize(tester, const Size(360, 800));
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(
        _host(repository, picker: _file('next.json', _nextBytes())),
      );
      await _until(
        tester,
        () => find.text('Магазин Тест').evaluate().isNotEmpty,
      );

      expect(tester.takeException(), isNull);
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

      await tester.tap(find.byKey(const Key('json-replace-dataset')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-replace-dialog')).evaluate().isNotEmpty,
      );

      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('json-replace-cancel')));
      await _until(
        tester,
        () => find.byKey(const Key('json-replace-dialog')).evaluate().isEmpty,
      );
      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      final controller = _controller(tester, find.byType(JsonOrdersScreen));
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

      expect(_onOrders(const Key('json-replace-dataset')), findsNothing);
      expect(_onOrders(const Key('json-replace-blocked')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

const _databaseName = 'retail-offline-json-replace-test';

Uint8List _nextBytes() {
  final source = utf8
      .decode(
        catalogue(
          storeName: 'Інший магазин',
          dbName: 'Store_02-B',
          orderId: 'NEW-1',
        ),
      )
      .replaceFirst('20261003114618', '20261016120000')
      .replaceFirst('Тестовий Клієнт А', 'Новий Клієнт');
  return Uint8List.fromList(utf8.encode(source));
}

Future<PickedBytes?> Function() _file(String name, Uint8List bytes) {
  return () async => (name: name, bytes: bytes);
}

Finder _onOrders(Key key) {
  return find.descendant(
    of: find.byType(JsonOrdersScreen),
    matching: find.byKey(key),
  );
}

bool _replaceEnabled(WidgetTester tester, Type screen) {
  return tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byType(screen),
              matching: find.byKey(const Key('json-replace-dataset')),
            ),
          )
          .onPressed !=
      null;
}

FulfilmentUiController _controller(WidgetTester tester, Finder finder) {
  return FulfilmentScope.read(tester.element(finder));
}

Future<void> _untilPhase(WidgetTester tester, FulfilmentUiPhase phase) {
  return _untilPhaseOn(tester, JsonImportScreen, phase);
}

Future<void> _untilPhaseOn(
  WidgetTester tester,
  Type screen,
  FulfilmentUiPhase phase,
) {
  return _until(
    tester,
    () => _controller(tester, find.byType(screen)).phase == phase,
  );
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (done()) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for dataset replacement');
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _seed(MemoryFulfilmentRepository repository) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-replace-seed',
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

Widget _host(
  FulfilmentRepository repository, {
  Future<PickedBytes?> Function()? picker,
  Widget? child,
  StorageChangeTransport? transport,
}) {
  return _ReplaceHost(
    key: UniqueKey(),
    repository: repository,
    picker: picker,
    transport: transport,
    child: child,
  );
}

class _ReplaceHost extends StatefulWidget {
  const _ReplaceHost({
    super.key,
    required this.repository,
    this.picker,
    this.child,
    this.transport,
  });

  final FulfilmentRepository repository;
  final Future<PickedBytes?> Function()? picker;
  final Widget? child;
  final StorageChangeTransport? transport;

  @override
  State<_ReplaceHost> createState() => _ReplaceHostState();
}

class _ReplaceHostState extends State<_ReplaceHost> {
  late final FulfilmentUiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FulfilmentUiController.open(
      repository: widget.repository,
      databaseName: _databaseName,
      transport: widget.transport ?? _Transport(),
      visibility: _Pages(),
      senderId: 'json-replace-test',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.picker == null
        ? null
        : JsonFileService(picker: widget.picker);
    return FulfilmentScope(
      controller: _controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: widget.child ?? JsonImportScreen(fileService: files),
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

final class _DeliveringTransport implements StorageChangeTransport {
  void Function(StorageChangeNotice notice)? onNotice;

  void deliver(StorageChangeNotice notice) => onNotice?.call(notice);

  @override
  bool get isAvailable => true;

  @override
  bool publish(StorageChangeNotice notice) => true;

  @override
  void listen(void Function(StorageChangeNotice notice) onNotice) {
    this.onNotice = onNotice;
  }

  @override
  void close() {}
}
