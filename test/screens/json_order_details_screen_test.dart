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
import 'package:retail_offline/core/theme/app_colors.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/models/order.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';
import 'package:retail_offline/screens/json_import/json_import_screen.dart';
import 'package:retail_offline/screens/json_orders/json_order_details_screen.dart';
import 'package:retail_offline/screens/json_orders/json_orders_screen.dart';
import 'package:retail_offline/screens/json_orders/json_serial_selection_screen.dart';
import 'package:retail_offline/screens/orders/order_details_screen.dart';
import 'package:retail_offline/screens/orders/orders_screen.dart';
import 'package:retail_offline/screens/orders/serial_selection_screen.dart';
import 'package:retail_offline/services/file/json_file_service.dart';
import 'package:retail_offline/services/file/picked_bytes.dart';

import '../application/fulfilment_application_test.dart';
import '../support/memory_fulfilment_repository.dart';

const _largeOrderNumber = '9007199254740993';
const _parcelId = '1290564103789190999';
const _serviceId = '1290564103789190888';
const _parcelTtn = 'TTN-PARCEL-1';
const _formattedPhone = '+38 (067) 123-45-67';

void main() {
  group('JSON order details', () {
    testWidgets('opens one order by OrderID and shows its header', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );

      final before = repository.loads;
      await _open(tester, 'ORD-1');
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.loads, before);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<JsonOrderDetailsScreen>(find.byType(JsonOrderDetailsScreen))
            .orderId,
        'ORD-1',
      );
      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(find.byType(OrderDetailsScreen), findsNothing);
      expect(find.byType(SerialSelectionScreen), findsNothing);
      expect(find.byKey(const Key('json-complete-service')), findsOneWidget);
      expect(find.text('Завершити обслуговування'), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);
      expect(find.text('Поширити файл'), findsNothing);
      expect(find.text('Додати'), findsNothing);
      expect(find.text('Прибрати'), findsNothing);
      expect(find.byType(JsonSerialSelectionScreen), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('json-good-$productId')),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );

      expect(
        _text(tester, find.byKey(const Key('json-order-number'))),
        _largeOrderNumber,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-order-number')))
            .maxLines,
        isNull,
      );
      expect(
        _text(tester, find.byKey(const Key('json-invoice-number'))),
        'ТЕСТ000001',
      );
      expect(
        _text(tester, find.byKey(const Key('json-order-date'))),
        '03.10.2026 11:46',
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer-phone'))),
        '0501112233',
      );
      expect(
        _text(tester, find.byKey(const Key('json-store-name'))),
        'Магазин Тест',
      );
      expect(_onDetails(find.text('Магазин Тест')), findsNWidgets(2));
      expect(_onDetails(find.text('Без вибору')), findsOneWidget);
      expect(find.text('Готово'), findsNothing);
      expect(find.text('Файл сформовано'), findsNothing);
      expect(
        tester.widget<Card>(find.byKey(const Key('json-order-info'))).color,
        isNull,
      );
      expect(_onDetails(find.text('Тестовий Клієнт Б')), findsNothing);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.noSelection);

      final good = controller.session!.dataset.orders
          .firstWhere((order) => order.orderId == 'ORD-1')
          .goods
          .single;
      expect(good.priceMinorUnits, 32450);
      expect(good.amountMinorUnits, 64900);
      expect(good.productId.literal, productId);
      expect(
        _text(tester, find.byKey(ValueKey('json-product-id-$productId'))),
        productId,
      );
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('json-product-id-$productId')))
            .maxLines,
        isNull,
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-good-quantity-$productId'))),
        '2',
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-good-price-$productId'))),
        '324,50',
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-good-amount-$productId'))),
        '649,00',
      );
      expect(
        _text(tester, find.byKey(const Key('json-order-total'))),
        '649,00',
      );
      expect(find.text('324.50'), findsNothing);
      expect(find.text('649.00'), findsNothing);
      expect(find.text('9007199254740992'), findsNothing);
      expect(find.textContaining('9.007'), findsNothing);
      expect(find.textContaining('e+'), findsNothing);
      expect(find.text('Тестовий товар 1'), findsOneWidget);
      expect(find.text('Посилка'), findsNothing);
      expect(find.text('Послуга'), findsNothing);
      expect(find.text('Обрано 0 з 2'), findsOneWidget);
      expect(
        find.byKey(ValueKey('json-good-progress-$productId')),
        findsOneWidget,
      );

      final header = find.byKey(const Key('json-goods-table-header'));
      expect(header, findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find.descendant(of: header, matching: find.text('Товар')),
            )
            .dy,
        tester
            .getTopLeft(
              find.descendant(of: header, matching: find.text('Сума')),
            )
            .dy,
      );
      expect(
        tester.getTopLeft(find.text('Тестовий товар 1')).dy,
        tester
            .getTopLeft(find.byKey(ValueKey('json-good-price-$productId')))
            .dy,
      );
      expect(
        tester
            .getTopLeft(find.byKey(ValueKey('json-product-id-$productId')))
            .dy,
        greaterThan(tester.getTopLeft(find.text('Тестовий товар 1')).dy),
      );
    });

    testWidgets('duplicate order numbers open the tapped OrderID', (
      tester,
    ) async {
      await _importAndOpen(tester, MemoryFulfilmentRepository(), _mixBytes());

      await _open(tester, 'ORD-A');
      expect(
        tester
            .widget<JsonOrderDetailsScreen>(find.byType(JsonOrderDetailsScreen))
            .orderId,
        'ORD-A',
      );
      expect(
        _text(tester, find.byKey(const Key('json-order-number'))),
        _largeOrderNumber,
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Клієнт Формат',
      );
      expect(
        _text(tester, find.byKey(const Key('json-invoice-number'))),
        'INV-ORD-A',
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer-phone'))),
        _formattedPhone,
      );
      expect(_onDetails(find.text('Клієнт Цифри')), findsNothing);
      expect(find.text('Товар Посилка'), findsOneWidget);
      expect(_onDetails(find.text('Товар Двійника')), findsNothing);

      await _back(tester);
      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(find.text(_largeOrderNumber), findsNWidgets(2));

      await _open(tester, 'ORD-B');
      expect(
        tester
            .widget<JsonOrderDetailsScreen>(find.byType(JsonOrderDetailsScreen))
            .orderId,
        'ORD-B',
      );
      expect(
        _text(tester, find.byKey(const Key('json-order-number'))),
        _largeOrderNumber,
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Клієнт Цифри',
      );
      expect(
        _text(tester, find.byKey(const Key('json-invoice-number'))),
        'INV-ORD-B',
      );
      expect(_onDetails(find.text('Клієнт Формат')), findsNothing);
      expect(_onDetails(find.text('Товар Посилка')), findsNothing);
      expect(find.text('Товар Двійника'), findsOneWidget);
      expect(find.text('9007199254740992'), findsNothing);
      expect(find.textContaining('9.007'), findsNothing);
    });

    testWidgets('shows parcel and service lines from the session', (
      tester,
    ) async {
      final controller = await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _mixBytes(),
      );
      await _open(tester, 'ORD-A');

      expect(find.text('Посилка'), findsOneWidget);
      expect(find.text('Послуга'), findsOneWidget);
      expect(
        find.byKey(ValueKey('json-good-parcel-$_parcelId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('json-good-service-$_serviceId')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('json-good-parcel-$productId')), findsNothing);
      expect(
        find.byKey(ValueKey('json-good-service-$productId')),
        findsNothing,
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-parcel-ttn-$_parcelId'))),
        _parcelTtn,
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-product-id-$_parcelId'))),
        _parcelId,
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-product-id-$_serviceId'))),
        _serviceId,
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-good-amount-$productId'))),
        '19,99',
      );
      expect(
        _text(tester, find.byKey(ValueKey('json-good-price-$productId'))),
        '10,00',
      );
      expect(find.text('20,00'), findsNothing);
      expect(_text(tester, find.byKey(const Key('json-order-total'))), '84,99');
      expect(find.text('Обрано 0 з 2'), findsOneWidget);
      expect(find.text('Обрано 0 з 1'), findsOneWidget);
      expect(find.text('Не потребує вибору'), findsOneWidget);
      expect(
        find.byKey(ValueKey('json-good-ready-$_serviceId')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('json-good-$_serviceId')),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('json-good-$productId')),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('json-good-$_parcelId')),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-A',
          productId: _serviceId,
        ),
        0,
      );

      expect(
        await controller.reserve(
          orderId: 'ORD-A',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(find.text('Обрано 1 з 2'), findsOneWidget);
      expect(find.text('Обрано 0 з 2'), findsNothing);
      expect(find.text('Обрано 0 з 1'), findsOneWidget);
      expect(find.text('Не потребує вибору'), findsOneWidget);
      expect(_onDetails(find.text('В процесі')), findsOneWidget);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-A',
          productId: productId,
        ),
        1,
      );
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-B',
          productId: productId,
        ),
        0,
      );
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-A',
          productId: _parcelId,
        ),
        0,
      );
      expect(controller.session!.statusOf('ORD-A'), OrderStatus.inProgress);
      expect(
        tester.widget<Card>(find.byKey(const Key('json-order-info'))).color,
        AppColors.orderStatusInProgressBackground,
      );

      expect(
        await controller.reserve(
          orderId: 'ORD-A',
          productId: productId,
          address: address,
          serialNumber: serial,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(
        find.byKey(ValueKey('json-good-ready-$productId')),
        findsOneWidget,
      );
      expect(_onDetails(find.text('В процесі')), findsOneWidget);
      expect(controller.session!.statusOf('ORD-A'), OrderStatus.inProgress);

      expect(
        await controller.reserve(
          orderId: 'ORD-A',
          productId: _parcelId,
          address: 'A-02',
          serialNumber: _parcelTtn,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(find.text('Обрано 1 з 1'), findsOneWidget);
      expect(
        find.byKey(ValueKey('json-good-ready-$_parcelId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('json-good-ready-$_serviceId')),
        findsOneWidget,
      );
      expect(_onDetails(find.text('Готово до видачі')), findsOneWidget);
      expect(find.text('Не потребує вибору'), findsOneWidget);
      expect(controller.session!.statusOf('ORD-A'), OrderStatus.readyForIssue);
      expect(
        tester.widget<Card>(find.byKey(const Key('json-order-info'))).color,
        AppColors.orderStatusReadyBackground,
      );
      expect(find.byType(SerialSelectionScreen), findsNothing);
    });

    testWidgets('narrow layout stacks goods cards', (tester) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        _mixBytes(),
        size: const Size(360, 2400),
      );

      expect(find.byKey(const Key('json-orders-table-header')), findsNothing);
      await _open(tester, 'ORD-A');

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('json-goods-table-header')), findsNothing);
      expect(find.text('Посилка'), findsOneWidget);
      expect(find.text('Послуга'), findsOneWidget);
      expect(
        _text(tester, find.byKey(ValueKey('json-product-id-$productId'))),
        productId,
      );
      expect(
        tester.getTopLeft(find.text('Товар Посилка')).dy,
        greaterThan(tester.getTopLeft(find.text('Товар Звичайний')).dy + 40),
      );
      expect(find.byType(OrderDetailsScreen), findsNothing);
    });

    testWidgets('back returns to the filtered orders list', (tester) async {
      await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        datasetBytes(),
      );

      await tester.enterText(
        find.byKey(const Key('json-order-number-search')),
        '42',
      );
      await tester.pump();
      expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsNothing);

      await _open(tester, 'ORD-2');
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт Б',
      );
      expect(_text(tester, find.byKey(const Key('json-order-number'))), '42');
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(
        find.byType(JsonOrdersScreen, skipOffstage: false),
        findsOneWidget,
      );

      await _back(tester);

      expect(find.byType(JsonOrderDetailsScreen), findsNothing);
      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('json-order-number-search')),
            )
            .controller!
            .text,
        '42',
      );
      expect(find.text('Тестовий Клієнт Б'), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);
    });

    testWidgets('a reservation on the open order replaces the progress', (
      tester,
    ) async {
      final controller = await _importAndOpen(
        tester,
        MemoryFulfilmentRepository(),
        datasetBytes(),
      );
      await _open(tester, 'ORD-1');
      expect(find.text('Обрано 0 з 2'), findsOneWidget);

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

      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(find.text('Обрано 1 з 2'), findsOneWidget);
      expect(_onDetails(find.text('В процесі')), findsOneWidget);
      expect(find.byKey(const Key('json-order-details')), findsOneWidget);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.inProgress);
    });

    testWidgets('dataset replacement keeps the same OrderID current', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );
      await _open(tester, 'ORD-1');
      final afterOpen = repository.loads;
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.loads, afterOpen);
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.replaceDataset(_renamedBytes()),
        isA<FulfilmentReplaced>(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(repository.loads, afterOpen + 1);
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );

      expect(await controller.refresh(), isA<LoadReady>());
      await tester.pump();

      expect(repository.loads, afterOpen + 2);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(
        tester
            .widget<JsonOrderDetailsScreen>(find.byType(JsonOrderDetailsScreen))
            .orderId,
        'ORD-1',
      );
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Новий Клієнт',
      );
      expect(
        _text(tester, find.byKey(const Key('json-invoice-number'))),
        'ТЕСТ000099',
      );
      expect(
        _text(tester, find.byKey(const Key('json-order-number'))),
        _largeOrderNumber,
      );
      expect(find.text('Тестовий Клієнт А'), findsNothing);
    });

    testWidgets('dataset replacement drops an order that is gone', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );
      await _open(tester, 'ORD-1');
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.replaceDataset(_removedOrderBytes()),
        isA<FulfilmentReplaced>(),
      );
      expect(await controller.refresh(), isA<LoadReady>());
      await tester.pump();

      expect(find.byKey(const Key('json-order-missing')), findsOneWidget);
      expect(find.text('Замовлення не знайдено'), findsOneWidget);
      expect(
        find.text('Цього замовлення немає в поточних даних.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('json-order-details')), findsNothing);
      expect(find.byKey(const Key('json-customer')), findsNothing);
      expect(find.byKey(const Key('json-order-number')), findsNothing);
      expect(_onDetails(find.text('Тестовий Клієнт А')), findsNothing);
      expect(_onDetails(find.text(_largeOrderNumber)), findsNothing);
      expect(_onDetails(find.text('Магазин Новий')), findsOneWidget);
      expect(controller.session!.statusOf('ORD-1'), isNull);

      await tester.tap(find.byKey(const Key('json-order-missing-back')));
      await _until(
        tester,
        () => find.byType(JsonOrderDetailsScreen).evaluate().isEmpty,
      );

      expect(find.byType(JsonOrdersScreen), findsOneWidget);
      expect(find.byType(JsonOrderDetailsScreen), findsNothing);
    });

    testWidgets('a block hides the open order until an explicit retry', (
      tester,
    ) async {
      final repository = _CountingRepository();
      final controller = await _importAndOpen(
        tester,
        repository,
        datasetBytes(),
      );
      await _open(tester, 'ORD-1');
      expect(controller.session, isNotNull);
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );

      repository.debugStorageUnavailable(true);
      final before = repository.loads;
      await controller.refresh();
      await tester.pump();

      expect(repository.loads, before + 1);
      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.session, isNotNull);
      expect(
        find.byKey(const Key('json-order-details-blocked')),
        findsOneWidget,
      );
      expect(_onDetails(find.text('Роботу призупинено')), findsOneWidget);
      expect(
        _onDetails(find.text('Не вдалося відкрити збережені дані.')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('json-order-details')), findsNothing);
      expect(find.byKey(const Key('json-customer')), findsNothing);
      expect(find.byKey(const Key('json-order-number')), findsNothing);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);
      expect(find.text('Магазин Тест'), findsNothing);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, before + 1);

      repository.debugStorageUnavailable(false);
      await tester.tap(find.byKey(const Key('json-order-details-retry')));
      await _until(
        tester,
        () => find.text('Тестовий Клієнт А').evaluate().isNotEmpty,
      );

      expect(find.byKey(const Key('json-order-details-blocked')), findsNothing);
      expect(
        _text(tester, find.byKey(const Key('json-customer'))),
        'Тестовий Клієнт А',
      );
      expect(repository.loads, before + 2);
    });

    testWidgets('loading and an empty dataset do not show an order', (
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
        _host(
          repository,
          child: const JsonOrderDetailsScreen(orderId: 'ORD-1'),
        ),
      );
      await _until(tester, () => repository.loads == 1);

      expect(
        find.byKey(const Key('json-order-details-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('json-order-details-retry')), findsNothing);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(find.byKey(const Key('json-order-details')), findsNothing);

      final during = repository.loads;
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, during);

      gate.complete();
      await _until(
        tester,
        () => find
            .byKey(const Key('json-order-details-empty'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Немає збережених даних'), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      final afterLoad = repository.loads;
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.loads, afterLoad);

      await tester.tap(find.byKey(const Key('json-order-details-retry')));
      await _until(tester, () => repository.loads == afterLoad + 1);
      expect(find.byKey(const Key('json-order-details-empty')), findsOneWidget);
    });

    testWidgets('an unknown OrderID shows not found on a ready session', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository);
      await _setSize(tester, const Size(1000, 1400));
      await tester.pumpWidget(
        _host(
          repository,
          child: const JsonOrderDetailsScreen(orderId: 'ORD-MISSING'),
        ),
      );
      await _until(
        tester,
        () => find.byKey(const Key('json-order-missing')).evaluate().isNotEmpty,
      );

      expect(find.text('Замовлення не знайдено'), findsOneWidget);
      expect(find.text('Магазин Тест'), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsNothing);
      expect(find.text(_largeOrderNumber), findsNothing);
      expect(find.byKey(const Key('json-order-details')), findsNothing);
      expect(find.byKey(const Key('json-complete-service')), findsNothing);
      expect(find.text('Завершити обслуговування'), findsNothing);

      await tester.tap(find.byKey(const Key('json-order-missing-back')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('json-order-missing')), findsOneWidget);
    });

    testWidgets('a ready order issues once and keeps its reservations', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _reserveReady);
      final controller = await _pumpDetails(tester, repository);
      final revision = controller.revision!;
      final reserved = controller.session!.lineReservedQuantity(
        orderId: 'ORD-1',
        productId: productId,
      );

      expect(controller.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(_onDetails(find.text('Готово до видачі')), findsOneWidget);
      expect(_issueEnabled(tester), isTrue);
      expect(reserved, 2);

      final attempts = repository.commitAttempts;
      final hold = repository.holdNextCommit();
      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();
      await hold.started;

      expect(_onDetails(find.text('Готово до видачі')), findsOneWidget);
      expect(find.text('Видано'), findsNothing);
      expect(_issueEnabled(tester), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('json-complete-service')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        reserved,
      );

      hold.release();
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(_onDetails(find.text('Видано')), findsOneWidget);
      expect(find.text('Готово до видачі'), findsNothing);
      expect(find.text('Файл Excel успішно сформовано'), findsNothing);
      expect(find.text('Поширити файл'), findsNothing);
      expect(_issueEnabled(tester), isFalse);
      expect(find.text('Завершити обслуговування'), findsOneWidget);
      expect(controller.revision, revision + 1);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        reserved,
      );
      expect(repository.commitAttempts, attempts + 1);
      expect(tester.takeException(), isNull);

      final stored = FulfilmentApplication(repository: repository);
      expect(await stored.load(), isA<LoadReady>());
      expect(stored.revision, revision + 1);
      expect(stored.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(
        stored.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        reserved,
      );
    });

    testWidgets('an in-progress order keeps completion disabled', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _reservePartial);
      await _pumpDetails(tester, repository);
      final attempts = repository.commitAttempts;

      expect(_onDetails(find.text('В процесі')), findsOneWidget);
      expect(find.text('Обрано 1 з 2'), findsOneWidget);
      expect(find.byKey(const Key('json-complete-service')), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(_onDetails(find.text('В процесі')), findsOneWidget);
      expect(find.text('Видано'), findsNothing);
    });

    testWidgets('a service-only order issues without a reservation', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, bytes: _serviceOnlyBytes());
      final controller = await _pumpDetails(
        tester,
        repository,
        orderId: 'ORD-S',
      );
      final revision = controller.revision!;
      final attempts = repository.commitAttempts;

      expect(controller.session!.statusOf('ORD-S'), OrderStatus.readyForIssue);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-S',
          productId: _serviceId,
        ),
        0,
      );
      expect(
        controller.session!.availableQuantity(
          productId: productId,
          address: address,
          serialNumber: serial,
        ),
        5,
      );
      expect(find.text('Не потребує вибору'), findsOneWidget);
      expect(_issueEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(controller.revision, revision + 1);
      expect(controller.session!.statusOf('ORD-S'), OrderStatus.issued);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-S',
          productId: _serviceId,
        ),
        0,
      );
      expect(
        controller.session!.availableQuantity(
          productId: productId,
          address: address,
          serialNumber: serial,
        ),
        5,
      );
      expect(_issueEnabled(tester), isFalse);
      expect(repository.commitAttempts, attempts + 1);
      expect(find.text('Поширити файл'), findsNothing);
    });

    testWidgets('a parcel order stays disabled until its line is complete', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, bytes: _parcelOrderBytes());
      final controller = await _pumpDetails(
        tester,
        repository,
        orderId: 'ORD-P',
      );

      expect(controller.session!.statusOf('ORD-P'), OrderStatus.noSelection);
      expect(find.text('Обрано 0 з 2'), findsOneWidget);
      expect(find.text('Посилка'), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);

      expect(
        await controller.reserve(
          orderId: 'ORD-P',
          productId: _parcelId,
          address: 'A-02',
          serialNumber: _parcelTtn,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(controller.session!.statusOf('ORD-P'), OrderStatus.inProgress);
      expect(find.text('Обрано 1 з 2'), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);

      expect(
        await controller.reserve(
          orderId: 'ORD-P',
          productId: _parcelId,
          address: 'A-02',
          serialNumber: _parcelTtn,
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      await tester.pump();

      expect(controller.session!.statusOf('ORD-P'), OrderStatus.readyForIssue);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(_issueEnabled(tester), isTrue);

      final reserved = controller.session!.lineReservedQuantity(
        orderId: 'ORD-P',
        productId: _parcelId,
      );
      await tester.tap(find.byKey(const Key('json-complete-service')));
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(controller.session!.statusOf('ORD-P'), OrderStatus.issued);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-P',
          productId: _parcelId,
        ),
        reserved,
      );
      expect(_issueEnabled(tester), isFalse);
    });

    testWidgets('an issued order does not commit again', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _issueOrd1);
      final controller = await _pumpDetails(tester, repository);
      final attempts = repository.commitAttempts;
      final revision = controller.revision;

      expect(_onDetails(find.text('Видано')), findsOneWidget);
      expect(find.text('Поширити файл'), findsNothing);
      expect(find.byKey(const Key('json-complete-service')), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        2,
      );

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(controller.revision, revision);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
    });

    testWidgets('an exported order does not commit again', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _exportOrd1);
      final controller = await _pumpDetails(tester, repository);
      final attempts = repository.commitAttempts;
      final revision = controller.revision;

      expect(_onDetails(find.text('Експортовано')), findsOneWidget);
      expect(find.text('Поширити файл'), findsNothing);
      expect(find.text('Файл Excel успішно сформовано'), findsNothing);
      expect(find.byKey(const Key('json-complete-service')), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(controller.revision, revision);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.exported);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        2,
      );
    });

    testWidgets('a remote reload updates readiness and issued status', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _Transport();
      await _seed(repository);
      final controller = await _pumpDetails(
        tester,
        repository,
        transport: transport,
      );

      expect(_issueEnabled(tester), isFalse);
      expect(_onDetails(find.text('Без вибору')), findsOneWidget);

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
      final afterReserve = repository.commitAttempts;
      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(tester, () => _issueEnabled(tester));

      expect(repository.commitAttempts, afterReserve);
      expect(controller.revision, other.revision);
      expect(_onDetails(find.text('Готово до видачі')), findsOneWidget);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);

      expect(
        await other.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      final afterIssue = repository.commitAttempts;
      transport.deliver(
        StorageChangeNotice(
          revision: '${other.revision}',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(repository.commitAttempts, afterIssue);
      expect(_onDetails(find.text('Видано')), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        2,
      );
    });

    testWidgets('a revision conflict blocks until an explicit refresh', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _reserveReady);
      final controller = await _pumpDetails(tester, repository);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await _until(
        tester,
        () => find
            .byKey(const Key('json-order-details-blocked'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text(AppStrings.jsonRevisionConflict), findsOneWidget);
      expect(find.text('Роботу призупинено'), findsOneWidget);
      expect(find.byKey(const Key('json-order-details')), findsNothing);
      expect(find.byKey(const Key('json-complete-service')), findsNothing);
      expect(find.text('Видано'), findsNothing);
      expect(controller.phase, FulfilmentUiPhase.blocked);
      expect(controller.block, PersistenceBlock.revisionConflict);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.commitAttempts, attempts + 1);

      await tester.tap(find.byKey(const Key('json-order-details-retry')));
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(find.byKey(const Key('json-order-details-blocked')), findsNothing);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(_onDetails(find.text('Видано')), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts + 1);
      expect(
        controller.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        2,
      );
    });

    testWidgets('a reload that wins shows the issued order without a commit', (
      tester,
    ) async {
      final repository = _GatedRepository();
      await _seed(repository, then: _reserveReady);
      final transport = _Transport();
      final controller = await _pumpDetails(
        tester,
        repository,
        transport: transport,
      );
      expect(_issueEnabled(tester), isTrue);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.issueOrder('ORD-1'),
        isA<FulfilmentCommitted<IssueOrderResult>>(),
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
      expect(_onDetails(find.text('Готово до видачі')), findsOneWidget);

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();
      gate.complete();
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(find.byKey(const Key('json-order-details-blocked')), findsNothing);
      expect(find.text(AppStrings.jsonRevisionConflict), findsNothing);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(_issueEnabled(tester), isFalse);
      expect(controller.phase, FulfilmentUiPhase.ready);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
      expect(repository.commitAttempts, attempts);
    });

    testWidgets('a storage failure shows the blocked message', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _reserveReady);
      await _pumpDetails(tester, repository);
      repository.failNextCommit();
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await _until(
        tester,
        () => find
            .byKey(const Key('json-order-details-blocked'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('Роботу призупинено'), findsOneWidget);
      expect(find.text(AppStrings.jsonStorageFailed), findsOneWidget);
      expect(find.byKey(const Key('json-order-details')), findsNothing);
      expect(find.byKey(const Key('json-order-details-retry')), findsOneWidget);
      expect(find.text('Видано'), findsNothing);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.commitAttempts, attempts + 1);

      final stored = FulfilmentApplication(repository: repository);
      expect(await stored.load(), isA<LoadReady>());
      expect(stored.session!.statusOf('ORD-1'), OrderStatus.readyForIssue);
      expect(
        stored.session!.lineReservedQuantity(
          orderId: 'ORD-1',
          productId: productId,
        ),
        2,
      );
    });

    testWidgets('repeated taps while a commit is held produce one commit', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, then: _reserveReady);
      final controller = await _pumpDetails(tester, repository);
      final attempts = repository.commitAttempts;
      final revision = controller.revision!;
      final hold = repository.holdNextCommit();

      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();
      await hold.started;
      expect(_issueEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('json-complete-service')));
      await tester.pump();

      expect(repository.commitAttempts, attempts + 1);
      expect(find.text('Видано'), findsNothing);

      hold.release();
      await _until(tester, () => find.text('Видано').evaluate().isNotEmpty);

      expect(repository.commitAttempts, attempts + 1);
      expect(controller.revision, revision + 1);
      expect(_issueEnabled(tester), isFalse);
      expect(controller.session!.statusOf('ORD-1'), OrderStatus.issued);
    });
  });

  testWidgets('legacy excel orders still open OrderDetailsScreen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemorySessionDataRepository();
    repository.commit(
      orders: [
        Order(
          invoiceDate: DateTime(2026, 10, 3, 11, 46, 18),
          invoiceNumber: 'ТЕСТ000001',
          orderNumber: '900000001',
          customer: 'Клієнт А',
          customerPhone: '0501112233',
          items: const [
            OrderItem(
              product: 'Секретний товар Альфа',
              productId: productId,
              quantity: 2,
              priceMinorUnits: 1000,
              amountMinorUnits: 1999,
            ),
          ],
        ),
      ],
      inventory: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OrdersScreen(
          store: const Store(nameStore: 'ТВ Тестовий Магазин 1', idStore: '42'),
          repository: repository,
          selections: InMemorySerialSelectionRepository(),
          exports: InMemoryOrderExportRepository(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('900000001')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.byKey(const Key('complete-service')), findsOneWidget);
    expect(find.byKey(const Key('json-complete-service')), findsNothing);
    expect(find.text('Файл Excel успішно сформовано'), findsNothing);
    expect(find.text('Секретний товар Альфа'), findsOneWidget);
    expect(find.byType(JsonOrderDetailsScreen), findsNothing);
    expect(find.byType(JsonOrdersScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey('order-item-row-0')));
    await tester.pumpAndSettle();

    expect(find.byType(SerialSelectionScreen), findsOneWidget);
    expect(find.byType(JsonSerialSelectionScreen), findsNothing);
    expect(find.text('Додати'), findsOneWidget);
    expect(find.text('Прибрати'), findsOneWidget);
  });
}

const _databaseName = 'retail-offline-json-order-details-test';

Uint8List _mixBytes() {
  const json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":['
      '{"Address":"A-01","ProductID":1290564103789190763,'
      '"SerialNumber":"SN-0001","Quantity":20},'
      '{"Address":"A-02","ProductID":1290564103789190999,'
      '"SerialNumber":"TTN-PARCEL-1","Quantity":1}],'
      '"orders":[{"OrderID":"ORD-A","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-ORD-A","OrderNumber":9007199254740993,'
      '"Customer":"Клієнт Формат","CustomerPhone":"+38 (067) 123-45-67",'
      '"Goods":[{"Product":"Товар Звичайний","ProductID":1290564103789190763,'
      '"Quantity":2,"Price":10.00,"Amount":19.99,"isServiceGood":0,'
      '"isParcel":0},{"Product":"Товар Посилка",'
      '"ProductID":1290564103789190999,"Quantity":1,"Price":50.00,'
      '"Amount":50.00,"isServiceGood":0,"isParcel":1,'
      '"ParcelTTN":"TTN-PARCEL-1"},{"Product":"Товар Послуга",'
      '"ProductID":1290564103789190888,"Quantity":1,"Price":15.00,'
      '"Amount":15.00,"isServiceGood":1,"isParcel":0}]},'
      '{"OrderID":"ORD-B","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-ORD-B","OrderNumber":9007199254740993,'
      '"Customer":"Клієнт Цифри","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Товар Двійника","ProductID":1290564103789190763,'
      '"Quantity":1,"Price":10.00,"Amount":10.00,"isServiceGood":0,'
      '"isParcel":0}]}]}';
  return Uint8List.fromList(utf8.encode(json));
}

Uint8List _renamedBytes() {
  final source = utf8
      .decode(datasetBytes())
      .replaceFirst(
        '"Customer":"Тестовий Клієнт А"',
        '"Customer":"Новий Клієнт"',
      )
      .replaceFirst(
        '"InvoiceNumber":"ТЕСТ000001"',
        '"InvoiceNumber":"ТЕСТ000099"',
      );
  return Uint8List.fromList(utf8.encode(source));
}

Uint8List _removedOrderBytes() {
  final source = utf8
      .decode(datasetBytes())
      .replaceFirst('Магазин Тест', 'Магазин Новий')
      .replaceFirst('"OrderID":"ORD-1"', '"OrderID":"ORD-9"')
      .replaceFirst('"OrderID":"ORD-2"', '"OrderID":"ORD-8"');
  return Uint8List.fromList(utf8.encode(source));
}

String _text(WidgetTester tester, Finder finder) {
  return tester.widget<Text>(finder).data!;
}

Future<void> _open(WidgetTester tester, String orderId) async {
  await tester.tap(find.byKey(ValueKey(orderId)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
}

Finder _onDetails(Finder matching) {
  return find.descendant(
    of: find.byType(JsonOrderDetailsScreen),
    matching: matching,
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(JsonOrderDetailsScreen),
      matching: find.byType(BackButton),
    ),
  );
  await _until(
    tester,
    () => find.byType(JsonOrderDetailsScreen).evaluate().isEmpty,
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
  await _until(
    tester,
    () =>
        _controllerOf(tester, find.byType(JsonImportScreen)).phase ==
        FulfilmentUiPhase.empty,
  );
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

Widget _host(
  FulfilmentRepository repository, {
  Future<PickedBytes?> Function()? picker,
  Widget? child,
  _Transport? transport,
}) {
  return _DetailsHost(
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

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (done()) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for the JSON order details screen');
}

Future<void> _seed(
  MemoryFulfilmentRepository repository, {
  Uint8List? bytes,
  Future<void> Function(FulfilmentUiController controller)? then,
}) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-order-details-seed',
  );
  try {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (controller.phase == FulfilmentUiPhase.empty) break;
      await Future<void>.value();
    }
    expect(controller.phase, FulfilmentUiPhase.empty);
    expect(
      await controller.importDataset(bytes ?? datasetBytes()),
      isA<FulfilmentImported>(),
    );
    if (then != null) await then(controller);
  } finally {
    controller.dispose();
  }
}

Future<void> _reservePartial(FulfilmentUiController controller) async {
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
}

Future<void> _reserveReady(FulfilmentUiController controller) async {
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
}

Future<void> _issueOrd1(FulfilmentUiController controller) async {
  await _reserveReady(controller);
  expect(
    await controller.issueOrder('ORD-1'),
    isA<FulfilmentCommitted<IssueOrderResult>>(),
  );
}

Future<void> _exportOrd1(FulfilmentUiController controller) async {
  await _issueOrd1(controller);
  expect(
    await controller.commitCumulativeExport(
      now: () => DateTime(2026, 10, 16, 12),
    ),
    isA<FulfilmentExported>(),
  );
}

Future<FulfilmentUiController> _pumpDetails(
  WidgetTester tester,
  MemoryFulfilmentRepository repository, {
  String orderId = 'ORD-1',
  _Transport? transport,
  Size size = const Size(1000, 1400),
}) async {
  await _setSize(tester, size);
  await tester.pumpWidget(
    _host(
      repository,
      transport: transport,
      child: JsonOrderDetailsScreen(orderId: orderId),
    ),
  );
  await _until(
    tester,
    () =>
        find.byKey(const Key('json-order-details')).evaluate().isNotEmpty ||
        find.byKey(const Key('json-order-missing')).evaluate().isNotEmpty ||
        find
            .byKey(const Key('json-order-details-blocked'))
            .evaluate()
            .isNotEmpty ||
        find.byKey(const Key('json-order-details-empty')).evaluate().isNotEmpty,
  );
  return FulfilmentScope.read(
    tester.element(find.byType(JsonOrderDetailsScreen)),
  );
}

bool _issueEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(const Key('json-complete-service')))
          .onPressed !=
      null;
}

class _DetailsHost extends StatefulWidget {
  const _DetailsHost({
    required this.repository,
    this.picker,
    this.transport,
    this.child,
  });

  final FulfilmentRepository repository;
  final Future<PickedBytes?> Function()? picker;
  final _Transport? transport;
  final Widget? child;

  @override
  State<_DetailsHost> createState() => _DetailsHostState();
}

class _DetailsHostState extends State<_DetailsHost> {
  late final FulfilmentUiController _controller;
  late final _Transport _transport;

  @override
  void initState() {
    super.initState();
    _transport = widget.transport ?? _Transport();
    _controller = FulfilmentUiController.open(
      repository: widget.repository,
      databaseName: _databaseName,
      transport: _transport,
      visibility: _Pages(),
      senderId: 'json-order-details-test',
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

Uint8List _serviceOnlyBytes() {
  const json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":[{"Address":"A-01",'
      '"ProductID":1290564103789190763,"SerialNumber":"SN-0001","Quantity":5}],'
      '"orders":[{"OrderID":"ORD-S","InvoiceDate":"20261003114618",'
      '"InvoiceNumber":"INV-S","OrderNumber":7,'
      '"Customer":"Клієнт Послуга","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Доставка","ProductID":1290564103789190888,"Quantity":1,'
      '"Price":15.00,"Amount":15.00,"isServiceGood":1,"isParcel":0}]}]}';
  return Uint8List.fromList(utf8.encode(json));
}

Uint8List _parcelOrderBytes() {
  const json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":[{"Address":"A-02",'
      '"ProductID":1290564103789190999,"SerialNumber":"TTN-PARCEL-1",'
      '"Quantity":2}],"orders":[{"OrderID":"ORD-P",'
      '"InvoiceDate":"20261003114618","InvoiceNumber":"INV-P",'
      '"OrderNumber":8,"Customer":"Клієнт Посилка",'
      '"CustomerPhone":"0501112233","Goods":[{"Product":"Товар Посилка",'
      '"ProductID":1290564103789190999,"Quantity":2,"Price":50.00,'
      '"Amount":100.00,"isServiceGood":0,"isParcel":1,'
      '"ParcelTTN":"TTN-PARCEL-1"}]}]}';
  return Uint8List.fromList(utf8.encode(json));
}
