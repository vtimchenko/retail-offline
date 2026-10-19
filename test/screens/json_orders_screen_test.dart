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
import 'package:retail_offline/core/theme/app_colors.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/screens/json_orders/dataset_order_search.dart';
import 'package:retail_offline/screens/json_orders/json_orders_screen.dart';
import 'package:retail_offline/services/file/cumulative_export_share.dart';
import 'package:retail_offline/services/file/export_share.dart';
import 'package:retail_offline/services/file/json_file_service.dart';
import 'package:retail_offline/services/file/picked_bytes.dart';

import '../application/fulfilment_application_test.dart';
import '../support/memory_fulfilment_repository.dart';

const _formattedPhone = '+38 (067) 123-45-67';
const _largeOrderNumber = '9007199254740993';

void main() {
  group('dataset order search', () {
    final orders = [
      _datasetOrder(
        orderId: 'ORD-A',
        orderNumber: _largeOrderNumber,
        phone: _formattedPhone,
      ),
      _datasetOrder(
        orderId: 'ORD-B',
        orderNumber: _largeOrderNumber,
        phone: '0501112233',
      ),
      _datasetOrder(orderId: 'ORD-C', orderNumber: '42', phone: ''),
    ];

    List<String> ids({String orderNumberQuery = '', String phoneQuery = ''}) {
      return DatasetOrderSearch.filter(
        orders,
        orderNumberQuery: orderNumberQuery,
        phoneQuery: phoneQuery,
      ).map((order) => order.orderId).toList();
    }

    test('order number matches a partial literal', () {
      expect(ids(orderNumberQuery: '4740993'), ['ORD-A', 'ORD-B']);
      expect(ids(orderNumberQuery: ' 42 '), ['ORD-C']);
    });

    test('phone normalization ignores formatting and keeps an empty phone', () {
      expect(ids(phoneQuery: '380671234567'), ['ORD-A']);
      expect(ids(phoneQuery: '+38 (067)'), ['ORD-A']);
      expect(ids(phoneQuery: '050'), ['ORD-B']);
      expect(ids(phoneQuery: '067'), isNot(contains('ORD-C')));
      expect(ids(phoneQuery: ' +()- '), ['ORD-A', 'ORD-B', 'ORD-C']);
      expect(
        DatasetOrderSearch.filter(
          orders,
          orderNumberQuery: '',
          phoneQuery: '067',
        ).single.customerPhone,
        _formattedPhone,
      );
    });

    test('both filters use AND', () {
      expect(ids(orderNumberQuery: '9007', phoneQuery: '050'), ['ORD-B']);
      expect(ids(orderNumberQuery: '9007', phoneQuery: '093'), isEmpty);
    });

    test(
      'duplicate order numbers stay distinct and filtering does not mutate',
      () {
        final phones = orders.map((order) => order.customerPhone).toList();
        final numbers = orders
            .map((order) => order.orderNumber.literal)
            .toList();

        final matched = DatasetOrderSearch.filter(
          orders,
          orderNumberQuery: _largeOrderNumber,
          phoneQuery: '',
        );

        expect(matched.map((order) => order.orderId), ['ORD-A', 'ORD-B']);
        expect(
          matched.map((order) => order.orderNumber.literal),
          everyElement(_largeOrderNumber),
        );
        expect(orders.map((order) => order.customerPhone), phones);
        expect(orders.map((order) => order.orderNumber.literal), numbers);
        expect(identical(orders[0].customerPhone, phones[0]), isTrue);
      },
    );
  });

  group('JSON orders list', () {
    testWidgets('opens from the ready screen on the same fulfilment scope', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );

      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(
        find.byType(JsonImportScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        _controllerOf(tester, find.byType(JsonOrdersScreen)),
        same(controller),
      );
      expect(find.text(_largeOrderNumber), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Тестовий товар 1'), findsNothing);

      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(JsonOrdersScreen).evaluate().isEmpty) break;
      }

      expect(find.byType(JsonOrdersScreen), findsNothing);
      expect(find.byKey(const Key('json-view-orders')), findsOneWidget);
      expect(find.byType(JsonImportScreen), findsOneWidget);
    });

    testWidgets('opens from the app root on the same controller', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(_app(repository));
      await _until(tester, () {
        if (find.byType(JsonImportScreen).evaluate().isEmpty) return false;
        return _controllerOf(tester, find.byType(JsonImportScreen)).phase ==
            FulfilmentUiPhase.ready;
      });
      final before = _controllerOf(tester, find.byType(JsonImportScreen));

      expect(find.text('Вибір магазину'), findsNothing);
      expect(find.byKey(const Key('json-mode-entry')), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byKey(const Key('json-view-orders')), findsOneWidget);

      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
      );

      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(
        find.byType(JsonImportScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        _controllerOf(tester, find.byType(JsonOrdersScreen)),
        same(before),
      );
      expect(find.text(_largeOrderNumber), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isEmpty,
      );

      expect(find.byKey(const Key('json-view-orders')), findsOneWidget);
      expect(find.byType(JsonImportScreen), findsOneWidget);
      expect(
        _controllerOf(tester, find.byType(JsonImportScreen)),
        same(before),
      );
    });

    testWidgets('filters by a partial order number', (tester) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _searchBytes(),
      );

      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        '4740993',
      );
      await tester.pump();

      expect(find.text(_largeOrderNumber), findsNWidgets(2));
      expect(find.text('Клієнт Формат'), findsOneWidget);
      expect(find.text('Клієнт Цифри'), findsOneWidget);
      expect(find.text('Клієнт Інший'), findsNothing);
      expect(find.text('42'), findsNothing);
    });

    testWidgets('normalizes a phone query and keeps the stored formatting', (
      tester,
    ) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _searchBytes(),
      );

      await tester.enterText(
        find.byKey(const Key('json-customer-phone-search')),
        '067',
      );
      await tester.pump();

      expect(find.text('(067) 123-45-67'), findsOneWidget);
      expect(find.text('380671234567'), findsNothing);
      expect(find.text('Клієнт Формат'), findsOneWidget);
      expect(find.text('Клієнт Цифри'), findsNothing);
      expect(find.text('0501112233'), findsNothing);
    });

    testWidgets('combines order number and phone with AND', (tester) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _searchBytes(),
      );

      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        '9007',
      );
      await tester.enterText(
        find.byKey(const Key('json-customer-phone-search')),
        '050',
      );
      await tester.pump();

      expect(find.text('Клієнт Цифри'), findsOneWidget);
      expect(find.text('(050) 111-22-33'), findsOneWidget);
      expect(find.text('Клієнт Формат'), findsNothing);
      expect(find.text('(067) 123-45-67'), findsNothing);
      expect(find.text('Клієнт Інший'), findsNothing);
    });

    testWidgets('shows duplicate order numbers as separate orders', (
      tester,
    ) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _searchBytes(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ORD-A')), findsOneWidget);
      expect(find.byKey(const ValueKey('ORD-B')), findsOneWidget);
      expect(find.byKey(const ValueKey('ORD-C')), findsOneWidget);
      expect(find.text(_largeOrderNumber), findsNWidgets(2));
      expect(find.text('9007199254740992'), findsNothing);
      expect(find.textContaining('9.007'), findsNothing);
      expect(find.text('Прихований товар'), findsNothing);
      expect(find.text('Клієнт Формат'), findsOneWidget);
      expect(find.text('Клієнт Цифри'), findsOneWidget);
    });

    testWidgets('wide layout shows a table of domain statuses', (tester) async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        _statusBytes(),
      );
      await _applyStatuses(controller);
      await tester.pump();

      expect(tester.takeException(), isNull);
      final header = find.byKey(const Key('json-orders-table-header'));
      expect(header, findsOneWidget);
      final date = find.descendant(of: header, matching: find.text('Дата'));
      final invoice = find.descendant(
        of: header,
        matching: find.text('№ рахунка'),
      );
      final phone = find.descendant(of: header, matching: find.text('Телефон'));
      expect(invoice, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('Накладна')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(invoice).dx,
        greaterThan(tester.getTopLeft(date).dx),
      );
      expect(
        tester.getTopLeft(phone).dx,
        greaterThan(tester.getTopLeft(invoice).dx),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ORD-none')),
          matching: find.text('INV-ORD-none'),
        ),
        findsOneWidget,
      );
      expect(tester.getTopLeft(date).dy, tester.getTopLeft(phone).dy);
      expect(find.text('Замовлення — Магазин Тест'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(JsonOrdersScreen),
          matching: find.text(AppStrings.ordersScreenTitle),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(JsonOrdersScreen),
          matching: find.text(AppStrings.jsonDateCreateLabel),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('json-orders-date-create')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(JsonOrdersScreen),
          matching: find.byKey(const Key('json-replace-dataset')),
        ),
        findsNothing,
      );
      final rowDate = find.descendant(
        of: find.byKey(const ValueKey('ORD-none')),
        matching: find.text('03.10.2026 11:46'),
      );
      final rowPhone = find.descendant(
        of: find.byKey(const ValueKey('ORD-none')),
        matching: find.text('(050) 100-00-01'),
      );
      expect(tester.getTopLeft(date).dx, tester.getTopLeft(rowDate).dx);
      expect(tester.getTopLeft(phone).dx, tester.getTopLeft(rowPhone).dx);
      expect(tester.widget<Text>(rowDate).maxLines, 2);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('ORD-none')),
                matching: find.text('Без вибору'),
              ),
            )
            .maxLines,
        2,
      );
      expect(
        find.descendant(
          of: find.byType(JsonOrdersScreen),
          matching: find.byType(Divider),
        ),
        findsNWidgets(5),
      );
      _expectStatusLabels(tester, table: true);
      expect(_rowColor(tester, 'ORD-none'), AppColors.background);
      expect(
        _rowColor(tester, 'ORD-progress'),
        AppColors.orderStatusInProgressBackground,
      );
      expect(
        _rowColor(tester, 'ORD-ready'),
        AppColors.orderStatusReadyBackground,
      );
      expect(
        _rowColor(tester, 'ORD-issued'),
        AppColors.orderStatusIssuedBackground,
      );
      expect(
        _rowColor(tester, 'ORD-exported'),
        AppColors.orderStatusExportedBackground,
      );
    });

    testWidgets('long order identifiers do not overflow desktop or mobile', (
      tester,
    ) async {
      for (final size in const [
        Size(752, 900),
        Size(1200, 900),
        Size(360, 800),
      ]) {
        await _importAndOpen(
          tester,
          MemoryFulfilmentRepository(),
          _searchBytes(),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(_largeOrderNumber), findsWidgets);
        final title = tester.widget<Text>(find.textContaining('Замовлення —'));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        if (size.width < 720) {
          expect(
            find.text('Рахунок №INV-ORD-A від 03.10.2026 11:46'),
            findsOneWidget,
          );
          expect(find.text('(067) 123-45-67'), findsOneWidget);
        }
      }
    });

    testWidgets('long store, customer, and invoice values stay readable', (
      tester,
    ) async {
      const store =
          'Магазин з дуже довгою назвою для вузького екрана співробітника';
      const customer = 'Клієнт з дуже довгим прізвищем та іменем для картки';
      const phone = '+380671234567890123';
      const invoice = 'INV-00000000000000000099';
      final bytes = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(_statusBytes())
              .replaceFirst('Магазин Тест', store)
              .replaceFirst('Клієнт 100', customer)
              .replaceFirst('0501000001', phone)
              .replaceFirst('INV-ORD-none', invoice),
        ),
      );

      for (final size in const [
        Size(360, 800),
        Size(752, 900),
        Size(1200, 900),
      ]) {
        await _importAndOpen(
          tester,
          MemoryFulfilmentRepository(),
          bytes,
          size: size,
        );
        expect(tester.takeException(), isNull);
        final title = tester.widget<Text>(find.textContaining('Замовлення —'));
        expect(title.data, 'Замовлення — $store');
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        if (size.width < 720) {
          expect(
            find.text('Рахунок №$invoice від 03.10.2026 11:46'),
            findsOneWidget,
          );
          expect(find.text(customer), findsOneWidget);
          expect(find.text(phone), findsOneWidget);
          expect(find.text('100'), findsOneWidget);
        } else {
          expect(find.text(invoice), findsOneWidget);
          expect(find.text(customer), findsOneWidget);
          expect(find.text(phone), findsOneWidget);
        }
      }
    });

    testWidgets('narrow layout shows the same statuses as cards', (
      tester,
    ) async {
      final controller = await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _statusBytes(),
        size: const Size(360, 2400),
      );
      await _applyStatuses(controller);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('json-orders-table-header')), findsNothing);
      expect(find.text('Статус'), findsNothing);
      expect(
        find.text('Рахунок №INV-ORD-none від 03.10.2026 11:46'),
        findsOneWidget,
      );
      expect(find.text('Клієнт 100'), findsOneWidget);
      expect(find.text('(050) 100-00-01'), findsOneWidget);
      _expectStatusLabels(tester, table: false);
      expect(_cardColor(tester, 'ORD-none'), isNull);
      expect(
        _cardColor(tester, 'ORD-progress'),
        AppColors.orderStatusInProgressBackground,
      );
      expect(
        _cardColor(tester, 'ORD-ready'),
        AppColors.orderStatusReadyBackground,
      );
      expect(
        _cardColor(tester, 'ORD-issued'),
        AppColors.orderStatusIssuedBackground,
      );
      expect(
        _cardColor(tester, 'ORD-exported'),
        AppColors.orderStatusExportedBackground,
      );
      final first = tester.getTopLeft(find.text('100')).dy;
      final second = tester.getTopLeft(find.text('200')).dy;
      expect(second, greaterThan(first + 40));
    });

    testWidgets('shows an empty result without changing stored phones', (
      tester,
    ) async {
      final controller = await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _searchBytes(),
      );
      final phone = controller.session!.dataset.orders
          .firstWhere((order) => order.orderId == 'ORD-A')
          .customerPhone;

      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        'немає',
      );
      await tester.pump();

      expect(find.byKey(const Key('json-orders-no-match')), findsOneWidget);
      expect(find.text('Клієнт Формат'), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);
      expect(
        controller.session!.dataset.orders
            .firstWhere((order) => order.orderId == 'ORD-A')
            .customerPhone,
        phone,
      );
      expect(phone, _formattedPhone);
    });

    testWidgets('a reservation updates the open list from the live session', (
      tester,
    ) async {
      final controller = await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        datasetBytes(),
      );

      expect(find.text('Без вибору'), findsNWidgets(2));

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

      expect(find.text('В процесі'), findsOneWidget);
      expect(find.text('Без вибору'), findsOneWidget);
      expect(find.text('Готово'), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.inProgress);
      expect(
        _rowColor(tester, 'ORD-1'),
        AppColors.orderStatusInProgressBackground,
      );
    });

    testWidgets('session replacement updates the open list without polling', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );
      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        '42',
      );
      await tester.pump();
      expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
      expect(find.text(_largeOrderNumber), findsNothing);

      final afterOpen = repository.loads;
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, afterOpen);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.replaceDataset(_replacedBytes()),
        isA<FulfilmentReplaced>(),
      );

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, afterOpen + 1);
      expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
      expect(find.text('Новий Клієнт'), findsNothing);

      expect(await controller.refresh(), isA<LoadReady>());
      await tester.pump();

      expect(repository.loads, afterOpen + 2);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('json-order-number-search')),
            )
            .controller!
            .text,
        '42',
      );
      expect(find.byKey(const Key('json-orders-no-match')), findsOneWidget);
      expect(find.text('Тестовий Клієнт Б'), findsNothing);
      expect(find.text('Новий Клієнт'), findsNothing);
      expect(find.text('77'), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);

      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        '',
      );
      await tester.pump();

      expect(find.text('77'), findsOneWidget);
      expect(find.text('88'), findsOneWidget);
      expect(find.text('Новий Клієнт'), findsOneWidget);
      expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
      expect(find.text(_largeOrderNumber), findsNothing);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
    });

    testWidgets('a block hides the open list until an explicit retry', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );
      expect(find.text(_largeOrderNumber), findsOneWidget);

      repository.debugStorageUnavailable(true);
      final before = repository.loads;
      await controller.refresh();
      await tester.pump();

      expect(repository.loads, before + 1);
      final ordersScreen = find.byType(JsonOrdersScreen);
      expect(find.byKey(const Key('json-orders-blocked')), findsOneWidget);
      expect(
        find.descendant(
          of: ordersScreen,
          matching: find.text('Роботу призупинено'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ordersScreen,
          matching: find.text('Не вдалося відкрити збережені дані.'),
        ),
        findsOneWidget,
      );
      expect(find.text(_largeOrderNumber), findsNothing);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(find.text('Магазин Тест'), findsNothing);
      expect(find.byKey(const Key('json-order-number-search')), findsNothing);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, before + 1);

      repository.debugStorageUnavailable(false);
      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(
        tester,
        () => find.text(_largeOrderNumber).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('json-orders-blocked')), findsNothing);
      expect(find.text(_largeOrderNumber), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsOneWidget);
      expect(repository.loads, before + 2);
    });

    testWidgets('loading and an empty dataset do not show orders', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final gate = Completer<void>();
      repository.loadGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await _setSize(tester, const Size(1000, 1400));
      await tester.pumpWidget(
        _host(repository, child: const JsonOrdersScreen()),
      );
      await _until(tester, () => repository.loads == 1);

      expect(find.byKey(const Key('json-orders-loading')), findsOneWidget);
      expect(find.byKey(const Key('json-orders-retry')), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);

      gate.complete();
      await _until(
        tester,
        () => find.byKey(const Key('json-orders-empty')).evaluate().isNotEmpty,
      );

      expect(find.text('Немає збережених даних'), findsOneWidget);
      expect(find.text(_largeOrderNumber), findsNothing);
      final afterLoad = repository.loads;
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, afterLoad);

      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(tester, () => repository.loads == afterLoad + 1);
      expect(find.byKey(const Key('json-orders-empty')), findsOneWidget);
      expect(repository.loads, afterLoad + 1);
    });
  });

  group('cumulative JSON export', () {
    testWidgets('a dataset with no issued orders cannot export or share', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (_) async {});
      final attempts = repository.commitAttempts;

      await _openReady(tester, repository, share: _quietShare().share);

      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(find.byKey(const Key('json-last-export-file')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('json-create-export'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('json-order-number-search')))
              .dy,
        ),
      );

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(find.text(AppStrings.jsonExportUnchanged), findsNothing);
    });

    testWidgets('one issued order enables export', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });

      await _openReady(tester, repository, share: _quietShare().share);

      expect(_enabled(tester, 'json-create-export'), isTrue);
      expect(find.text('Видано'), findsOneWidget);
      expect(find.text('Без вибору'), findsOneWidget);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
    });

    testWidgets('one export commits every newly issued order', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _issue(controller, 'ORD-2', 1);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final attempts = repository.commitAttempts;
      final revision = controller.revision;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(tester, () => find.text('Видано').evaluate().isEmpty);

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.revision, revision! + 1);
      expect(find.text('Експортовано'), findsNWidgets(2));
      expect(find.text('Видано'), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.exported);
      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(find.text(AppStrings.jsonExportRejected), findsNothing);
    });

    testWidgets('export marks only the issued order', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(find.text('Експортовано'), findsOneWidget);
      expect(find.text('Без вибору'), findsOneWidget);
      expect(find.text('Видано'), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.noSelection);
      expect(
        find.text(
          '${AppStrings.jsonLastSavedExport} ${controller.lastExport!.filename}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an existing file with nothing new can only be shared', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final attempts = repository.commitAttempts;

      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(find.text('Експортовано'), findsOneWidget);
      expect(find.text('Без вибору'), findsOneWidget);
      expect(
        find.text(
          '${AppStrings.jsonLastSavedExport} ${controller.lastExport!.filename}',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.noSelection);
    });

    testWidgets('a saved file and a new issue enable both actions', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
        await _issue(controller, 'ORD-2', 1);
      });

      await _openReady(
        tester,
        repository,
        share: _quietShare().share,
        size: const Size(360, 2400),
      );

      expect(tester.takeException(), isNull);
      expect(_enabled(tester, 'json-create-export'), isTrue);
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(
        tester.getTopLeft(find.byKey(const Key('json-share-export'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('json-create-export'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('json-last-export-file'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('json-share-export'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a later export keeps the previously exported order', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
        await _issue(controller, 'ORD-2', 1);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final first = Uint8List.fromList(controller.lastExport!.bytes);
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(tester, () => find.text('Видано').evaluate().isEmpty);

      final document = controller.lastExport!;
      final text = utf8.decode(document.bytes);
      expect(repository.commitAttempts, attempts + 1);
      expect(document.bytes, isNot(first));
      expect(text, contains('"OrderID": "ORD-1"'));
      expect(text, contains('"OrderID": "ORD-2"'));
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.exported);
      expect(
        find.text('${AppStrings.jsonLastSavedExport} ${document.filename}'),
        findsOneWidget,
      );
    });

    testWidgets('share sends the stored filename and bytes', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
      });
      final log = _quietShare();
      final controller = await _openReady(tester, repository, share: log.share);
      final document = controller.lastExport!;
      final attempts = repository.commitAttempts;
      final revision = controller.revision;

      await tester.tap(find.byKey(const Key('json-share-export')));
      await tester.pump();

      expect(log.calls, hasLength(1));
      expect(log.calls.single.$1, document.filename);
      expect(log.calls.single.$2, document.bytes);
      expect(utf8.decode(log.calls.single.$2), contains(productId));
      expect(utf8.decode(log.calls.single.$2), contains(_largeOrderNumber));
      expect(repository.commitAttempts, attempts);
      expect(controller.revision, revision);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(find.text(AppStrings.excelShareFailed), findsNothing);
    });

    testWidgets('cancelling share stays silent', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
      });
      final log = _quietShare(result: const ExportShareCancelled());
      final controller = await _openReady(tester, repository, share: log.share);
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-share-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(log.calls, hasLength(1));
      expect(find.text(AppStrings.excelShareFailed), findsNothing);
      expect(find.text(AppStrings.jsonExportRejected), findsNothing);
      expect(repository.commitAttempts, attempts);
      expect(controller.lastExport, isNotNull);
    });

    testWidgets('a failed share shows the existing message', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
      });
      final log = _quietShare(result: const ExportShareFailed());
      await _openReady(tester, repository, share: log.share);

      await tester.tap(find.byKey(const Key('json-share-export')));
      await _until(
        tester,
        () => find.text(AppStrings.excelShareFailed).evaluate().isNotEmpty,
      );

      expect(log.calls, hasLength(1));
      expect(find.byKey(const Key('json-share-failed')), findsOneWidget);
      expect(
        _controllerOf(tester, find.byType(JsonOrdersScreen)).phase,
        FulfilmentUiPhase.ready,
      );
    });

    testWidgets('a held export does not change badges early', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final hold = repository.holdNextCommit();

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();
      await hold.started;

      expect(find.text('Видано'), findsOneWidget);
      expect(find.text('Експортовано'), findsNothing);
      expect(controller.lastExport, isNull);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.descendant(
                of: find.byKey(const Key('json-create-export')),
                matching: find.byType(CircularProgressIndicator),
              ),
            )
            .color,
        Colors.white,
      );

      hold.release();
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.lastExport, isNotNull);
      expect(find.text('Видано'), findsNothing);
    });

    testWidgets('sharing during an export uses the previous file', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
        await _issue(controller, 'ORD-2', 1);
      });
      final log = _quietShare();
      final controller = await _openReady(tester, repository, share: log.share);
      final previousName = controller.lastExport!.filename;
      final previousBytes = Uint8List.fromList(controller.lastExport!.bytes);
      final hold = repository.holdNextCommit();
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();
      await hold.started;
      await tester.tap(find.byKey(const Key('json-share-export')));
      await tester.pump();

      expect(log.calls, hasLength(1));
      expect(log.calls.single.$1, previousName);
      expect(log.calls.single.$2, previousBytes);
      expect(controller.lastExport!.filename, previousName);
      expect(controller.lastExport!.bytes, previousBytes);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts + 1);
      expect(find.text('Видано'), findsOneWidget);

      hold.release();
      await _until(
        tester,
        () => controller.session!.statusOf('ORD-2') == OrderStatus.exported,
      );
    });

    testWidgets('share after the commit uses the new document', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
        await _issue(controller, 'ORD-2', 1);
      });
      final log = _quietShare();
      final controller = await _openReady(tester, repository, share: log.share);
      final previous = Uint8List.fromList(controller.lastExport!.bytes);

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(tester, () => find.text('Видано').evaluate().isEmpty);
      final document = controller.lastExport!;

      await tester.tap(find.byKey(const Key('json-share-export')));
      await tester.pump();

      expect(log.calls, hasLength(1));
      expect(log.calls.single.$1, document.filename);
      expect(log.calls.single.$2, document.bytes);
      expect(log.calls.single.$2, isNot(previous));
      expect(utf8.decode(log.calls.single.$2), contains('"OrderID": "ORD-1"'));
      expect(utf8.decode(log.calls.single.$2), contains('"OrderID": "ORD-2"'));
    });

    testWidgets('a new screen restores the exported file', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final first = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );
      final filename = first.lastExport!.filename;
      final bytes = Uint8List.fromList(first.lastExport!.bytes);
      final revision = first.revision;

      final second = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );

      expect(second.revision, revision);
      expect(second.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(second.session!.statusOf('ORD-2'), OrderStatus.noSelection);
      expect(second.lastExport!.filename, filename);
      expect(second.lastExport!.bytes, bytes);
      expect(
        find.text('${AppStrings.jsonLastSavedExport} $filename'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(_enabled(tester, 'json-create-export'), isFalse);
    });

    testWidgets('a remote export updates the list and the shared file', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _DeliveringTransport();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
        transport: transport,
      );
      final attempts = repository.commitAttempts;
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 15, 7, 22),
        ),
        isA<FulfilmentExported>(),
      );
      final filename = other.lastExport!.filename;
      final bytes = Uint8List.fromList(other.lastExport!.bytes);

      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: other.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.lastExport!.filename, filename);
      expect(controller.lastExport!.bytes, bytes);
      expect(
        find.text('${AppStrings.jsonLastSavedExport} $filename'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(_enabled(tester, 'json-create-export'), isFalse);
    });

    testWidgets('a revision conflict blocks and does not retry', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 15, 7, 22),
        ),
        isA<FulfilmentExported>(),
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonRevisionConflict), findsOneWidget);
      expect(find.byKey(const Key('json-create-export')), findsNothing);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(find.text('Експортовано'), findsNothing);
      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.block, PersistenceBlock.revisionConflict);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
    });

    testWidgets('refresh loads the other tab file without exporting again', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 15, 7, 22),
        ),
        isA<FulfilmentExported>(),
      );
      final filename = other.lastExport!.filename;
      final bytes = Uint8List.fromList(other.lastExport!.bytes);
      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.block, isNull);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.lastExport!.filename, filename);
      expect(controller.lastExport!.bytes, bytes);
      expect(
        find.text('${AppStrings.jsonLastSavedExport} $filename'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'json-share-export'), isTrue);
      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(find.text(AppStrings.jsonRevisionConflict), findsNothing);
    });

    testWidgets('storage failure keeps the previous file', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
        await _issue(controller, 'ORD-2', 1);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final filename = controller.lastExport!.filename;
      final bytes = Uint8List.fromList(controller.lastExport!.bytes);
      final revision = controller.revision;
      final attempts = repository.commitAttempts;
      repository.failNextCommit();

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonStorageFailed), findsOneWidget);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.issued);
      expect(controller.lastExport!.bytes, bytes);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.commitAttempts, attempts + 1);

      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.revision, revision);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.issued);
      expect(controller.lastExport!.filename, filename);
      expect(controller.lastExport!.bytes, bytes);
      expect(
        find.text('${AppStrings.jsonLastSavedExport} $filename'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'json-create-export'), isTrue);
      expect(_enabled(tester, 'json-share-export'), isTrue);
    });

    testWidgets('repeated taps while exporting commit once', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final attempts = repository.commitAttempts;
      final revision = controller.revision!;
      final hold = repository.holdNextCommit();

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();
      await hold.started;
      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(find.text('Експортовано'), findsNothing);

      hold.release();
      await _until(
        tester,
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.revision, revision + 1);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
    });

    testWidgets('loading, empty, and blocked phases hide file actions', (
      tester,
    ) async {
      final gated = _GatedRepository();
      final gate = Completer<void>();
      gated.loadGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await _setSize(tester, const Size(1000, 1400));
      await tester.pumpWidget(_host(gated, child: const JsonOrdersScreen()));
      await _until(tester, () => gated.loads == 1);

      expect(find.byKey(const Key('json-orders-loading')), findsOneWidget);
      expect(find.byKey(const Key('json-create-export')), findsNothing);
      expect(find.byKey(const Key('json-share-export')), findsNothing);

      gate.complete();
      await _until(
        tester,
        () => find.byKey(const Key('json-orders-empty')).evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('json-create-export')), findsNothing);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(find.byKey(const Key('json-last-export-file')), findsNothing);

      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _commitExport(controller);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      expect(find.byKey(const Key('json-share-export')), findsOneWidget);
      repository.debugStorageUnavailable(true);
      await controller.refresh();
      await tester.pump();

      expect(find.byKey(const Key('json-orders-blocked')), findsOneWidget);
      expect(find.byKey(const Key('json-create-export')), findsNothing);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(find.byKey(const Key('json-last-export-file')), findsNothing);
    });

    testWidgets('another tab issuing first does not publish a partial export', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
        await _reserve(controller, 'ORD-2', 1);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.issueOrder('ORD-2'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
      );

      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(controller.lastExport, isNull);
      expect(repository.commitAttempts, attempts + 1);

      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(tester, () => find.text('Видано').evaluate().length == 2);

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.lastExport, isNull);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(controller.session!.statusOf('ORD-2'), OrderStatus.issued);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(_enabled(tester, 'json-create-export'), isTrue);
    });

    testWidgets('a remote reload that wins does not show a stale conflict', (
      tester,
    ) async {
      final repository = _GatedRepository();
      final transport = _DeliveringTransport();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
        transport: transport,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.cancelIssuance('ORD-1'),
        isA<FulfilmentCommitted<CancelIssuanceResult>>(),
      );
      final attempts = repository.commitAttempts;
      final loads = repository.loads;
      final gate = Completer<void>();
      repository.loadGate = gate;
      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(tester, () => repository.loads == loads + 1);

      await tester.tap(find.byKey(const Key('json-create-export')));
      await tester.pump();
      gate.complete();
      await _until(
        tester,
        () => find.text(AppStrings.jsonExportUnchanged).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonRevisionConflict), findsNothing);
      expect(find.byKey(const Key('json-orders-blocked')), findsNothing);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(controller.lastExport, isNull);
      expect(repository.commitAttempts, attempts);
    });

    testWidgets('a failed export does not leave a conflict after reload', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _DeliveringTransport();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
        transport: transport,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 15, 7, 22),
        ),
        isA<FulfilmentExported>(),
      );
      final bytes = Uint8List.fromList(other.lastExport!.bytes);

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
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
        () => find.text('Експортовано').evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonRevisionConflict), findsNothing);
      expect(find.byKey(const Key('json-orders-blocked')), findsNothing);
      expect(find.text(AppStrings.jsonExportUnchanged), findsNothing);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.lastExport!.bytes, bytes);
      expect(repository.commitAttempts, attempts);
      expect(_enabled(tester, 'json-share-export'), isTrue);
    });

    testWidgets('replacing the dataset elsewhere drops the saved file', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _prepare(repository, (controller) async {
        await _issue(controller, 'ORD-1', 2);
      });
      final controller = await _openReady(
        tester,
        repository,
        share: _quietShare().share,
      );
      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.commitCumulativeExport(
          now: () => DateTime(2026, 10, 16, 15, 7, 22),
        ),
        isA<FulfilmentExported>(),
      );
      expect(
        await other.replaceDataset(_replacedBytes()),
        isA<FulfilmentReplaced>(),
      );
      expect(other.lastExport, isNull);
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-create-export')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-orders-blocked')).evaluate().isNotEmpty,
      );
      expect(controller.lastExport, isNull);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts + 1);

      await tester.tap(find.byKey(const Key('json-orders-retry')));
      await _until(tester, () => find.text('77').evaluate().isNotEmpty);

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.lastExport, isNull);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.noSelection);
      expect(find.byKey(const Key('json-share-export')), findsNothing);
      expect(find.byKey(const Key('json-last-export-file')), findsNothing);
      expect(_enabled(tester, 'json-create-export'), isFalse);
      expect(find.text('Новий Клієнт'), findsOneWidget);
    });
  });
}

const _databaseName = 'retail-offline-json-orders-test';

DatasetOrder _datasetOrder({
  required String orderId,
  required String orderNumber,
  required String phone,
}) {
  return DatasetOrder(
    orderId: orderId,
    invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
    invoiceNumber: 'INV-$orderId',
    orderNumber: ExactInteger(orderNumber),
    customer: 'Клієнт $orderId',
    customerPhone: phone,
    totalMinorUnits: 100,
    goods: const [
      DatasetGood(
        product: 'Товар',
        productId: ExactInteger('1290564103789190763'),
        quantity: 1,
        priceMinorUnits: 100,
        amountMinorUnits: 100,
        isServiceGood: false,
        isParcel: false,
      ),
    ],
  );
}

Uint8List _searchBytes() {
  return _datasetBytes([
    _orderJson(
      orderId: 'ORD-A',
      orderNumber: _largeOrderNumber,
      customer: 'Клієнт Формат',
      phone: _formattedPhone,
    ),
    _orderJson(
      orderId: 'ORD-B',
      orderNumber: _largeOrderNumber,
      customer: 'Клієнт Цифри',
      phone: '0501112233',
    ),
    _orderJson(
      orderId: 'ORD-C',
      orderNumber: '42',
      customer: 'Клієнт Інший',
      phone: '0930001122',
    ),
  ]);
}

Uint8List _statusBytes() {
  return _datasetBytes([
    _orderJson(
      orderId: 'ORD-none',
      orderNumber: '100',
      customer: 'Клієнт 100',
      phone: '0501000001',
    ),
    _orderJson(
      orderId: 'ORD-progress',
      orderNumber: '200',
      customer: 'Клієнт 200',
      phone: '0501000002',
      quantity: 2,
    ),
    _orderJson(
      orderId: 'ORD-ready',
      orderNumber: '300',
      customer: 'Клієнт 300',
      phone: '0501000003',
    ),
    _orderJson(
      orderId: 'ORD-issued',
      orderNumber: '400',
      customer: 'Клієнт 400',
      phone: '0501000004',
    ),
    _orderJson(
      orderId: 'ORD-exported',
      orderNumber: '500',
      customer: 'Клієнт 500',
      phone: '0501000005',
    ),
  ]);
}

Uint8List _datasetBytes(List<String> orders) {
  final json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":[{"Address":"$address",'
      '"ProductID":$productId,"SerialNumber":"$serial","Quantity":20}],'
      '"orders":[${orders.join(',')}]}';
  return Uint8List.fromList(utf8.encode(json));
}

String _orderJson({
  required String orderId,
  required String orderNumber,
  required String customer,
  required String phone,
  int quantity = 1,
}) {
  return '{"OrderID":"$orderId","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-$orderId","OrderNumber":$orderNumber,'
      '"Customer":"$customer","CustomerPhone":"$phone","Goods":[{'
      '"Product":"Прихований товар","ProductID":$productId,"Quantity":$quantity,'
      '"Price":10.00,"Amount":${quantity * 10}.00,"isServiceGood":0,"isParcel":0}]}';
}

Uint8List _replacedBytes() {
  final source = utf8
      .decode(datasetBytes())
      .replaceFirst('"OrderNumber":9007199254740993', '"OrderNumber":77')
      .replaceFirst(
        '"Customer":"Тестовий Клієнт А"',
        '"Customer":"Новий Клієнт"',
      )
      .replaceFirst('"OrderNumber":42', '"OrderNumber":88');
  return Uint8List.fromList(utf8.encode(source));
}

void _expectStatusLabels(WidgetTester tester, {required bool table}) {
  Finder label(String text) => find.descendant(
    of: find.byType(JsonOrdersScreen),
    matching: find.text(text),
  );
  expect(label('Без вибору'), findsOneWidget);
  expect(label('В процесі'), findsOneWidget);
  expect(label('Готово до видачі'), findsOneWidget);
  expect(label('Видано'), findsOneWidget);
  expect(label('Експортовано'), findsOneWidget);
  expect(find.text('Готово'), findsNothing);
  expect(find.text('Файл сформовано'), findsNothing);
  expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  expect(find.byIcon(Icons.timelapse), findsOneWidget);
  expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  expect(find.byIcon(Icons.task_alt), findsOneWidget);
  expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  expect(find.text('Статус'), table ? findsOneWidget : findsNothing);
}

Future<void> _applyStatuses(FulfilmentUiController controller) async {
  await _reserve(controller, 'ORD-exported', 1);
  expect(
    await controller.issueOrder('ORD-exported'),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
  expect(
    await controller.commitCumulativeExport(
      now: () => DateTime(2026, 10, 16, 12),
    ),
    isA<FulfilmentExported>(),
  );
  await _reserve(controller, 'ORD-issued', 1);
  expect(
    await controller.issueOrder('ORD-issued'),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
  await _reserve(controller, 'ORD-ready', 1);
  await _reserve(controller, 'ORD-progress', 1);
}

Future<void> _reserve(
  FulfilmentUiController controller,
  String orderId,
  int quantity,
) async {
  expect(
    await controller.reserve(
      orderId: orderId,
      productId: productId,
      address: address,
      serialNumber: serial,
      quantity: quantity,
    ),
    isA<FulfilmentCommitted<ReserveResult>>(),
  );
}

Future<void> _prepare(
  MemoryFulfilmentRepository repository,
  Future<void> Function(FulfilmentUiController controller) then,
) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-orders-prepare',
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
    await then(controller);
  } finally {
    controller.dispose();
  }
}

Future<void> _issue(
  FulfilmentUiController controller,
  String orderId,
  int quantity,
) async {
  await _reserve(controller, orderId, quantity);
  expect(
    await controller.issueOrder(orderId),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
}

Future<void> _commitExport(FulfilmentUiController controller) async {
  expect(
    await controller.commitCumulativeExport(
      now: () => DateTime(2026, 10, 16, 12),
    ),
    isA<FulfilmentExported>(),
  );
}

Future<FulfilmentUiController> _openReady(
  WidgetTester tester,
  MemoryFulfilmentRepository repository, {
  CumulativeExportShare? share,
  StorageChangeTransport? transport,
  Size size = const Size(1000, 1400),
}) async {
  await _setSize(tester, size);
  await tester.pumpWidget(
    _host(
      repository,
      transport: transport,
      child: JsonOrdersScreen(share: share),
    ),
  );
  await _until(
    tester,
    () =>
        find.byType(JsonOrdersScreen).evaluate().isNotEmpty &&
        _controllerOf(tester, find.byType(JsonOrdersScreen)).phase ==
            FulfilmentUiPhase.ready,
  );
  return _controllerOf(tester, find.byType(JsonOrdersScreen));
}

bool _enabled(WidgetTester tester, String key) {
  return tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed !=
      null;
}

_ShareLog _quietShare({
  ExportShareResult result = const ExportShareHandedOff(),
}) {
  return _ShareLog(result);
}

Future<FulfilmentUiController> _importAndOpen(
  WidgetTester tester,
  MemoryFulfilmentRepository repository,
  Uint8List bytes, {
  Size size = const Size(1000, 1400),
}) async {
  await _setSize(tester, size);
  await tester.pumpWidget(
    _host(repository, picker: _file('dataset.json', bytes)),
  );
  await _untilPhase(tester, FulfilmentUiPhase.empty);
  final controller = _controllerOf(tester, find.byType(JsonImportScreen));
  await tester.tap(find.byKey(const Key('json-import-button')));
  await _until(
    tester,
    () => find.byKey(const Key('json-view-orders')).evaluate().isNotEmpty,
  );
  await tester.tap(find.byKey(const Key('json-view-orders')));
  await _until(
    tester,
    () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
  );
  return controller;
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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
    // A new key makes the next pumpWidget read storage with a new controller.
    key: UniqueKey(),
    repository: repository,
    picker: picker,
    transport: transport,
    child: child,
  );
}

Future<PickedBytes?> Function() _file(String name, Uint8List bytes) {
  return () async => (name: name, bytes: bytes);
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
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for the JSON orders screen');
}

Future<void> _seed(MemoryFulfilmentRepository repository) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-orders-seed',
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

Color? _rowColor(WidgetTester tester, String orderId) {
  return tester
      .widget<Material>(
        find.descendant(
          of: find.byKey(ValueKey(orderId)),
          matching: find.byType(Material),
        ),
      )
      .color;
}

Color? _cardColor(WidgetTester tester, String orderId) {
  return tester
      .widget<Card>(
        find.descendant(
          of: find.byKey(ValueKey(orderId)),
          matching: find.byType(Card),
        ),
      )
      .color;
}

class _JsonHost extends StatefulWidget {
  const _JsonHost({
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
      senderId: 'json-orders-test',
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

final class _CountingRepository extends MemoryFulfilmentRepository {
  var loads = 0;

  @override
  Future<LoadResult> load() async {
    loads++;
    return super.load();
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

final class _ShareLog {
  _ShareLog(this.result);

  final ExportShareResult result;
  final List<(String, Uint8List)> calls = [];

  CumulativeExportShare get share => CumulativeExportShare(
    shareJson: ({required String filename, required Uint8List bytes}) {
      calls.add((filename, Uint8List.fromList(bytes)));
      return Future<ExportShareResult>.value(result);
    },
  );
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
