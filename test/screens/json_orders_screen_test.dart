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
import 'package:retail_offline/core/theme/app_colors.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/exact_integer.dart';
import 'package:retail_offline/models/retail_dataset.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/home/home_screen.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/screens/json_orders/dataset_order_search.dart';
import 'package:retail_offline/screens/json_orders/json_orders_screen.dart';
import 'package:retail_offline/screens/orders/orders_screen.dart';
import 'package:retail_offline/screens/store_selection/store_selection_screen.dart';
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
      expect(find.byType(OrdersScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
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

    testWidgets('stays under store selection and does not replace home', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);

      await tester.pumpWidget(_app(repository));
      await _until(tester, () {
        if (find.byKey(const Key('json-mode-entry')).evaluate().isEmpty) {
          return false;
        }
        return _controllerOf(tester, find.byType(StoreSelectionScreen)).phase ==
            FulfilmentUiPhase.ready;
      });
      final before = _controllerOf(tester, find.byType(StoreSelectionScreen));

      await tester.tap(find.byKey(const Key('json-mode-entry')));
      await _until(
        tester,
        () => find.byKey(const Key('json-view-orders')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('json-view-orders')));
      await _until(
        tester,
        () => find.byType(JsonOrdersScreen).evaluate().isNotEmpty,
      );

      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(find.byType(OrdersScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        find.byType(StoreSelectionScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(
        _controllerOf(tester, find.byType(JsonOrdersScreen)),
        same(before),
      );
      expect(find.text(_largeOrderNumber), findsOneWidget);
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

      expect(find.text(_formattedPhone), findsOneWidget);
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
      expect(find.text('0501112233'), findsOneWidget);
      expect(find.text('Клієнт Формат'), findsNothing);
      expect(find.text(_formattedPhone), findsNothing);
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
      final phone = find.descendant(of: header, matching: find.text('Телефон'));
      expect(tester.getTopLeft(date).dy, tester.getTopLeft(phone).dy);
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
  expect(find.text('Без вибору'), findsOneWidget);
  expect(find.text('В процесі'), findsOneWidget);
  expect(find.text('Готово до видачі'), findsOneWidget);
  expect(find.text('Видано'), findsOneWidget);
  expect(find.text('Експортовано'), findsOneWidget);
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
}) {
  return _JsonHost(repository: repository, picker: picker, child: child);
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
  const _JsonHost({required this.repository, this.picker, this.child});

  final FulfilmentRepository repository;
  final Future<PickedBytes?> Function()? picker;
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
      transport: _Transport(),
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
