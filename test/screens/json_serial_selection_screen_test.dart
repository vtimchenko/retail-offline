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
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/screens/json_orders/json_order_details_screen.dart';
import 'package:retail_offline/screens/json_orders/json_serial_selection_screen.dart';

import '../application/fulfilment_application_test.dart';
import '../support/memory_fulfilment_repository.dart';

void main() {
  group('JSON serial selection', () {
    testWidgets('opens from a stock line and returns to that order', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpDetails(tester, repository);

      await tester.tap(find.byKey(ValueKey('json-good-open-$productId')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final screen = tester.widget<JsonSerialSelectionScreen>(
        find.byType(JsonSerialSelectionScreen),
      );
      expect(screen.orderId, 'ORD-1');
      expect(screen.productId, productId);
      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(find.text('Тестовий товар 1'), findsWidgets);
      expect(find.text(productId), findsNothing);
      expect(find.byKey(const Key('json-serial-product-id')), findsNothing);
      expect(find.byKey(const Key('json-serial-status')), findsNothing);
      expect(find.byKey(const Key('json-serial-required')), findsNothing);
      expect(find.byKey(const Key('json-serial-remaining')), findsNothing);
      expect(find.byKey(const Key('json-serial-meest')), findsNothing);
      expect(find.textContaining('9.007'), findsNothing);
      expect(find.text('Обрано 0 з 2'), findsWidgets);
      expect(find.text('Залишилось: 2'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-serial-progress')))
            .style
            ?.color,
        AppColors.textSecondary,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(JsonSerialSelectionScreen),
          matching: find.byType(BackButton),
        ),
      );
      await _until(
        tester,
        () => find.byType(JsonSerialSelectionScreen).evaluate().isEmpty,
      );

      expect(find.byType(JsonOrderDetailsScreen), findsOneWidget);
      expect(find.text('Тестовий Клієнт А'), findsOneWidget);
    });

    testWidgets('a service line does not open serial selection', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, _mixBytes());
      await _pumpDetails(tester, repository, orderId: 'ORD-A');

      expect(find.text('Не потребує вибору'), findsOneWidget);
      expect(find.byKey(ValueKey('json-good-open-$_serviceId')), findsNothing);
      await tester.tap(find.text('Товар Послуга'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(JsonSerialSelectionScreen), findsNothing);
      expect(find.text('Не потребує вибору'), findsOneWidget);
    });

    testWidgets('add and remove one unit update both lists after commit', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      final attempts = repository.commitAttempts;
      await _pumpSerial(tester, repository);

      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '5');
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
      expect(find.text(productId), findsNothing);
      expect(find.byKey(const Key('json-serial-product')), findsOneWidget);
      expect(find.textContaining('e+'), findsNothing);

      await _highlight(tester, 'A-01', 'SN-0001');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 1);
      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '4');
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '1');
      expect(find.text('Залишилось: 1'), findsNothing);
      expect(find.text('В процесі'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-serial-progress')))
            .style
            ?.color,
        AppColors.orderStatusInProgressForeground,
      );
      expect(find.byKey(const Key('json-serial-error')), findsNothing);

      await _highlightSelected(tester, 'A-01', 'SN-0001');
      await tester.tap(find.byKey(const Key('json-serial-remove')));
      await _until(
        tester,
        () => find.text('Обрано 0 з 2').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 2);
      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '5');
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
      expect(find.text('Залишилось: 2'), findsNothing);
      expect(find.text('Обрано 0 з 2'), findsOneWidget);
    });

    testWidgets('a full line disables another add', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository);
      await _highlight(tester, 'A-01', 'SN-0001');

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 2 з 2').evaluate().isNotEmpty,
      );

      final attempts = repository.commitAttempts;
      expect(find.text('Залишилось: 0'), findsNothing);
      expect(find.text('Готово до видачі'), findsNothing);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('json-serial-progress')))
            .style
            ?.color,
        AppColors.primaryDark,
      );
      expect(_addEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '2');
    });

    testWidgets('another order sees stock already reserved', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, _singleUnitBytes());
      await _pumpSerial(tester, repository, orderId: 'ORD-1');
      await _highlight(tester, 'A-01', 'SN-0001');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find
            .byKey(const Key('json-serial-available-empty'))
            .evaluate()
            .isNotEmpty,
      );

      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '1');
      expect(
        find.text('Немає доступних залишків для цього товару'),
        findsOneWidget,
      );

      await _pumpSerial(tester, repository, orderId: 'ORD-2');

      expect(
        find.byKey(const Key('json-serial-available-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
      expect(find.text('SN-0001'), findsNothing);
      expect(_addEnabled(tester), isFalse);
    });

    testWidgets('a parcel lists only its TTN and keeps addresses apart', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, _parcelBytes());
      await _pumpSerial(tester, repository, productId: _parcelId);

      expect(find.text('Посилка'), findsOneWidget);
      expect(find.text('ТТН посилки: TTN-1'), findsOneWidget);
      expect(find.text('Meest ТТН: 000123'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ТТН посилки: TTN-1')).dy,
        tester.getTopLeft(find.text('Meest ТТН: 000123')).dy,
      );
      expect(
        find.byKey(const ValueKey(('json-available', 'A-01', 'TTN-1'))),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(('json-available', 'B-02', 'TTN-1'))),
        findsOneWidget,
      );
      expect(find.text('OTHER'), findsNothing);
      expect(
        tester.getTopLeft(find.text('A-01')).dy,
        lessThan(tester.getTopLeft(find.text('B-02')).dy),
      );

      await _highlight(tester, 'A-01', 'TTN-1');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 1 з 4').evaluate().isNotEmpty,
      );

      expect(_qty(tester, 'json-available-qty', 'A-01', 'TTN-1'), '1');
      expect(_qty(tester, 'json-available-qty', 'B-02', 'TTN-1'), '3');
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'TTN-1'), '1');
    });

    testWidgets('hides Meest TTN unless a parcel has a value', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(
        repository,
        _catalogue(
          stocks: [
            _stock('A-01', _parcelId, 'TTN-1', 1),
            _stock('A-01', productId, 'SN-0001', 1),
          ],
          orders: [
            _order('ORD-1', '7', [
              _line(
                'Товар Посилка',
                _parcelId,
                1,
                parcelTtn: 'TTN-1',
                meestTtn: '',
              ),
              _line('Товар', productId, 1, meestTtn: '000999'),
            ]),
          ],
        ),
      );

      await _pumpSerial(
        tester,
        repository,
        productId: _parcelId,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ТТН посилки: TTN-1'), findsOneWidget);
      expect(find.byKey(const Key('json-serial-meest')), findsNothing);
      expect(find.textContaining('Meest'), findsNothing);

      await _pumpSerial(tester, repository, size: const Size(360, 800));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('json-serial-parcel')), findsNothing);
      expect(find.byKey(const Key('json-serial-meest')), findsNothing);
      expect(find.textContaining('000999'), findsNothing);
    });

    testWidgets('the same serial at two addresses stays two rows', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, _duplicateSerialBytes());
      await _pumpSerial(tester, repository);

      expect(
        find.byKey(const ValueKey(('json-available', 'A-01', 'SAME'))),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(('json-available', 'B-02', 'SAME'))),
        findsOneWidget,
      );
      expect(_qty(tester, 'json-available-qty', 'A-01', 'SAME'), '2');
      expect(_qty(tester, 'json-available-qty', 'B-02', 'SAME'), '4');
      expect(find.text('9'), findsNothing);
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey(('json-available', 'A-01', 'SAME'))),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey(('json-available', 'B-02', 'SAME'))),
              )
              .dy,
        ),
      );
    });

    testWidgets('an issued order is read-only', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes(), then: _issueOrd1);
      final attempts = repository.commitAttempts;
      await _pumpSerial(tester, repository);

      expect(find.text('Видано'), findsNothing);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(find.byKey(const Key('json-serial-readonly')), findsOneWidget);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '2');
      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '3');
      expect(_addEnabled(tester), isFalse);
      expect(_removeEnabled(tester), isFalse);

      await _highlight(tester, 'A-01', 'SN-0001');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '2');
    });

    testWidgets('an exported order is read-only', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes(), then: _exportOrd1);
      final attempts = repository.commitAttempts;
      await _pumpSerial(tester, repository);

      expect(find.text('Експортовано'), findsNothing);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(find.text(AppStrings.jsonSerialOrderLocked), findsOneWidget);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '2');
      expect(_addEnabled(tester), isFalse);
      expect(_removeEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('json-serial-remove')));
      await tester.pump();

      expect(repository.commitAttempts, attempts);
    });

    testWidgets('a remote reload replaces the stock lists', (tester) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _Transport();
      await _seed(repository, datasetBytes());
      final attempts = repository.commitAttempts;
      final controller = await _pumpSerial(
        tester,
        repository,
        transport: transport,
      );

      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '5');

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.reserve(
          orderId: 'ORD-2',
          productId: productId,
          address: 'A-01',
          serialNumber: 'SN-0001',
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      transport.deliver(
        StorageChangeNotice(
          revision: '2',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(
        tester,
        () => _qty(tester, 'json-available-qty', 'A-01', 'SN-0001') == '4',
      );

      expect(controller.revision, 2);
      expect(repository.commitAttempts, attempts + 1);
      expect(find.byKey(const Key('json-serial-selection')), findsOneWidget);
      expect(find.text('Обрано 0 з 2'), findsOneWidget);
    });

    testWidgets('a highlight disappears with its row and stays cleared', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      final transport = _Transport();
      await _seed(repository, _singleUnitBytes());
      final controller = await _pumpSerial(
        tester,
        repository,
        transport: transport,
      );
      await _highlight(tester, 'A-01', 'SN-0001');
      expect(_addEnabled(tester), isTrue);

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.reserve(
          orderId: 'ORD-2',
          productId: productId,
          address: 'A-01',
          serialNumber: 'SN-0001',
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      transport.deliver(
        StorageChangeNotice(
          revision: '2',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(
        tester,
        () => find
            .byKey(const Key('json-serial-available-empty'))
            .evaluate()
            .isNotEmpty,
      );
      expect(_addEnabled(tester), isFalse);

      expect(
        await other.removeUnits(
          orderId: 'ORD-2',
          productId: productId,
          address: 'A-01',
          serialNumber: 'SN-0001',
          quantity: 1,
        ),
        isA<FulfilmentCommitted<RemoveUnitsResult>>(),
      );
      transport.deliver(
        StorageChangeNotice(
          revision: '3',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(
        tester,
        () => find
            .byKey(const ValueKey(('json-available', 'A-01', 'SN-0001')))
            .evaluate()
            .isNotEmpty,
      );

      expect(_addEnabled(tester), isFalse);
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
    });

    testWidgets('a revision conflict is not reserved again', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository);
      await _highlight(tester, 'A-01', 'SN-0001');

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.reserve(
          orderId: 'ORD-2',
          productId: productId,
          address: 'A-01',
          serialNumber: 'SN-0001',
          quantity: 1,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-serial-blocked')).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonRevisionConflict), findsOneWidget);
      expect(find.byKey(const Key('json-serial-selection')), findsNothing);
      expect(find.text('SN-0001'), findsNothing);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.commitAttempts, attempts + 1);
    });

    testWidgets('a storage failure shows the blocked message', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository);
      await _highlight(tester, 'A-01', 'SN-0001');
      repository.failNextCommit();
      final attempts = repository.commitAttempts;

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () =>
            find.byKey(const Key('json-serial-blocked')).evaluate().isNotEmpty,
      );

      expect(find.text('Роботу призупинено'), findsOneWidget);
      expect(find.text(AppStrings.jsonStorageFailed), findsOneWidget);
      expect(find.byKey(const Key('json-serial-selection')), findsNothing);
      expect(find.byKey(const Key('json-serial-retry')), findsOneWidget);
      expect(repository.commitAttempts, attempts + 1);

      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.commitAttempts, attempts + 1);
    });

    testWidgets('a domain rejection stays on the ready screen', (tester) async {
      final repository = _GatedRepository();
      await _seed(repository, datasetBytes());
      final controller = await _pumpSerial(tester, repository);
      await _highlight(tester, 'A-01', 'SN-0001');

      final other = FulfilmentApplication(repository: repository);
      expect(await other.load(), isA<LoadReady>());
      expect(
        await other.reserve(
          orderId: 'ORD-1',
          productId: productId,
          address: 'A-01',
          serialNumber: 'SN-0001',
          quantity: 2,
        ),
        isA<FulfilmentCommitted<ReserveResult>>(),
      );
      final attempts = repository.commitAttempts;
      final loads = repository.loads;
      final gate = Completer<void>();
      repository.loadGate = gate;
      final transport = _transportOf(tester);
      transport.deliver(
        StorageChangeNotice(
          revision: '2',
          fingerprint: controller.fingerprint!,
          senderId: 'remote-tab',
        ),
      );
      await _until(tester, () => repository.loads == loads + 1);
      expect(find.text('Обрано 0 з 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await tester.pump();
      gate.complete();
      await _until(
        tester,
        () => find.byKey(const Key('json-serial-error')).evaluate().isNotEmpty,
      );

      expect(find.text(AppStrings.jsonSerialLineComplete), findsOneWidget);
      expect(find.byKey(const Key('json-serial-selection')), findsOneWidget);
      expect(find.byKey(const Key('json-serial-blocked')), findsNothing);
      expect(find.text('Обрано 2 з 2'), findsOneWidget);
      expect(repository.commitAttempts, attempts);
      expect(controller.phase, FulfilmentUiPhase.ready);
    });

    testWidgets('wide rows use columns and narrow rows use cards', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository, size: const Size(1000, 1400));

      final header = find.byKey(const Key('json-serial-available-header'));
      expect(header, findsOneWidget);
      expect(
        find.byKey(const Key('json-serial-selected-header')),
        findsNothing,
      );
      expect(
        tester
            .getTopLeft(
              find.descendant(of: header, matching: find.text('Адреса')),
            )
            .dy,
        tester
            .getTopLeft(
              find.descendant(
                of: header,
                matching: find.text('Серійний номер'),
              ),
            )
            .dy,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: header, matching: find.text('Адреса')),
            )
            .maxLines,
        2,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: header,
                matching: find.text('Серійний номер'),
              ),
            )
            .maxLines,
        2,
      );
      expect(find.byType(Card), findsNothing);

      await _highlight(tester, 'A-01', 'SN-0001');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );
      final selectedHeader = find.byKey(
        const Key('json-serial-selected-header'),
      );
      expect(selectedHeader, findsOneWidget);
      expect(find.byType(Card), findsNothing);

      await _pumpSerial(tester, repository, size: const Size(360, 1800));
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('json-serial-available-header')),
        findsNothing,
      );
      expect(find.byType(Card), findsWidgets);
      expect(find.text('SN-0001'), findsWidgets);
    });

    testWidgets('long addresses and serials do not overflow', (tester) async {
      const longAddress = 'ADDR-WAREHOUSE-SHELF-BIN-VERY-LONG-LOCATION';
      const longSerial = 'SN-1234567890123456789012345678901234567890';
      final bytes = Uint8List.fromList(
        utf8.encode(
          utf8
              .decode(datasetBytes())
              .replaceFirst('A-01', longAddress)
              .replaceFirst('SN-0001', longSerial),
        ),
      );
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, bytes);

      for (final size in const [Size(752, 900), Size(1200, 900)]) {
        await _pumpSerial(tester, repository, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text(longAddress), findsWidgets);
        expect(find.text(longSerial), findsWidgets);
        final header = find.byKey(const Key('json-serial-available-header'));
        expect(header, findsOneWidget);
        expect(
          tester
              .getTopLeft(
                find.descendant(of: header, matching: find.text('Адреса')),
              )
              .dy,
          tester
              .getTopLeft(
                find.descendant(
                  of: header,
                  matching: find.text('Серійний номер'),
                ),
              )
              .dy,
        );
      }

      await _pumpSerial(tester, repository, size: const Size(360, 800));
      expect(tester.takeException(), isNull);
      expect(find.text(longAddress), findsWidgets);
      expect(find.text(longSerial), findsWidgets);
    });

    testWidgets('desktop double-tap reserves one unit', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      final attempts = repository.commitAttempts;
      await _pumpSerial(tester, repository, platform: TargetPlatform.macOS);

      await tester.tap(
        find.byKey(const ValueKey(('json-available', 'A-01', 'SN-0001'))),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
      expect(repository.commitAttempts, attempts);

      await tester.tap(
        find.byKey(const ValueKey(('json-available', 'A-01', 'SN-0001'))),
      );
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 1);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '1');

      await tester.tap(
        find.byKey(const ValueKey(('json-selected', 'A-01', 'SN-0001'))),
      );
      await tester.pump();
      expect(repository.commitAttempts, attempts + 1);

      await tester.tap(
        find.byKey(const ValueKey(('json-selected', 'A-01', 'SN-0001'))),
      );
      await _until(
        tester,
        () => find.text('Обрано 0 з 2').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 2);
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
    });

    testWidgets('a single tap does not reserve', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      final attempts = repository.commitAttempts;
      await _pumpSerial(tester, repository, platform: TargetPlatform.iOS);

      await tester.tap(
        find.byKey(const ValueKey(('json-available', 'A-01', 'SN-0001'))),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey(('json-available', 'A-01', 'SN-0001'))),
      );
      await tester.pump();

      expect(repository.commitAttempts, attempts);
      expect(
        find.byKey(const Key('json-serial-selected-empty')),
        findsOneWidget,
      );
      expect(_qty(tester, 'json-available-qty', 'A-01', 'SN-0001'), '5');
      expect(_addEnabled(tester), isTrue);
    });

    testWidgets('the add button sends one command', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository);
      await _highlight(tester, 'A-01', 'SN-0001');
      final attempts = repository.commitAttempts;
      final hold = repository.holdNextCommit();

      await tester.tap(find.byKey(const Key('json-serial-add')));
      await tester.pump();
      await hold.started;
      expect(_addEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await tester.pump();

      expect(repository.commitAttempts, attempts + 1);
      hold.release();
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );

      expect(repository.commitAttempts, attempts + 1);
      expect(_qty(tester, 'json-selected-qty', 'A-01', 'SN-0001'), '1');
    });

    testWidgets('search matches the serial and keeps its text', (tester) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, _searchBytes());
      await _pumpSerial(tester, repository);

      await tester.enterText(
        find.byKey(const Key('json-serial-search')),
        'sn-keep',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey(('json-available', 'QQ', 'sn-keep'))),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(('json-available', 'ZZ', 'SN-KEEP'))),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey(('json-available', 'SN-KEEP', 'PLAIN'))),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('json-serial-search')),
        'SN-KEEP',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey(('json-available', 'ZZ', 'SN-KEEP'))),
        findsOneWidget,
      );
      expect(find.text('PLAIN'), findsNothing);

      await _highlight(tester, 'ZZ', 'SN-KEEP');
      await tester.tap(find.byKey(const Key('json-serial-add')));
      await _until(
        tester,
        () => find.text('Обрано 1 з 2').evaluate().isNotEmpty,
      );

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('json-serial-search')))
            .controller!
            .text,
        'SN-KEEP',
      );
      expect(
        find.byKey(const ValueKey(('json-selected', 'SN-KEEP', 'PLAIN'))),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey(('json-selected', 'ZZ', 'SN-KEEP'))),
        findsOneWidget,
      );
    });

    testWidgets('missing order and missing product offer a way back', (
      tester,
    ) async {
      final repository = MemoryFulfilmentRepository();
      await _seed(repository, datasetBytes());
      await _pumpSerial(tester, repository, orderId: 'ORD-MISSING');

      expect(find.text('Замовлення не знайдено'), findsOneWidget);
      expect(find.byKey(const Key('json-serial-selection')), findsNothing);
      expect(find.text('SN-0001'), findsNothing);

      await _pumpSerial(tester, repository, productId: '999');
      expect(find.text('Товар не знайдено'), findsOneWidget);
      expect(
        find.text('Цього товару немає в поточному замовленні.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('json-serial-selection')), findsNothing);
    });
  });
}

const _databaseName = 'retail-offline-json-serial-test';
const _parcelId = '1290564103789190999';
const _serviceId = '1290564103789190888';

Future<void> _seed(
  MemoryFulfilmentRepository repository,
  Uint8List bytes, {
  Future<void> Function(FulfilmentUiController controller)? then,
}) async {
  final controller = FulfilmentUiController.open(
    repository: repository,
    databaseName: _databaseName,
    transport: _Transport(),
    visibility: _Pages(),
    senderId: 'json-serial-seed',
  );
  try {
    await _settle(controller, FulfilmentUiPhase.empty);
    expect(await controller.importDataset(bytes), isA<FulfilmentImported>());
    if (then != null) await then(controller);
  } finally {
    controller.dispose();
  }
}

Future<void> _issueOrd1(FulfilmentUiController controller) async {
  expect(
    await controller.reserve(
      orderId: 'ORD-1',
      productId: productId,
      address: 'A-01',
      serialNumber: 'SN-0001',
      quantity: 2,
    ),
    isA<FulfilmentCommitted<ReserveResult>>(),
  );
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

Future<FulfilmentUiController> _pumpSerial(
  WidgetTester tester,
  MemoryFulfilmentRepository repository, {
  String orderId = 'ORD-1',
  String productId = productId,
  _Transport? transport,
  Size size = const Size(1000, 1400),
  TargetPlatform? platform,
}) async {
  final usedTransport = transport ?? _Transport();
  await _setSize(tester, size);
  await tester.pumpWidget(
    _Host(
      repository: repository,
      transport: usedTransport,
      platform: platform,
      child: JsonSerialSelectionScreen(orderId: orderId, productId: productId),
    ),
  );
  await _until(
    tester,
    () =>
        find.byKey(const Key('json-serial-selection')).evaluate().isNotEmpty ||
        find.byKey(const Key('json-serial-missing')).evaluate().isNotEmpty ||
        find.byKey(const Key('json-serial-empty')).evaluate().isNotEmpty ||
        find.byKey(const Key('json-serial-blocked')).evaluate().isNotEmpty,
  );
  return FulfilmentScope.read(
    tester.element(find.byType(JsonSerialSelectionScreen)),
  );
}

Future<void> _pumpDetails(
  WidgetTester tester,
  MemoryFulfilmentRepository repository, {
  String orderId = 'ORD-1',
}) async {
  await _setSize(tester, const Size(1000, 1400));
  await tester.pumpWidget(
    _Host(
      repository: repository,
      transport: _Transport(),
      child: JsonOrderDetailsScreen(orderId: orderId),
    ),
  );
  await _until(
    tester,
    () => find.byKey(const Key('json-order-details')).evaluate().isNotEmpty,
  );
}

Future<void> _highlight(
  WidgetTester tester,
  String address,
  String serialNumber,
) async {
  await tester.tap(
    find.byKey(ValueKey(('json-available', address, serialNumber))),
  );
  await tester.pump();
}

Future<void> _highlightSelected(
  WidgetTester tester,
  String address,
  String serialNumber,
) async {
  await tester.tap(
    find.byKey(ValueKey(('json-selected', address, serialNumber))),
  );
  await tester.pump();
}

String _qty(
  WidgetTester tester,
  String kind,
  String address,
  String serialNumber,
) {
  return tester
      .widget<Text>(find.byKey(ValueKey((kind, address, serialNumber))))
      .data!;
}

bool _addEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(const Key('json-serial-add')))
          .onPressed !=
      null;
}

bool _removeEnabled(WidgetTester tester) {
  return tester
          .widget<OutlinedButton>(find.byKey(const Key('json-serial-remove')))
          .onPressed !=
      null;
}

_Transport _transportOf(WidgetTester tester) {
  final host = tester.widget<_Host>(find.byType(_Host));
  return host.transport;
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (done()) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for the JSON serial selection screen');
}

Future<void> _settle(
  FulfilmentUiController controller,
  FulfilmentUiPhase phase,
) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (controller.phase == phase) return;
    await Future<void>.value();
  }
  fail('controller stayed ${controller.phase}');
}

class _Host extends StatefulWidget {
  const _Host({
    required this.repository,
    required this.transport,
    required this.child,
    this.platform,
  });

  final MemoryFulfilmentRepository repository;
  final _Transport transport;
  final Widget child;
  final TargetPlatform? platform;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final FulfilmentUiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FulfilmentUiController.open(
      repository: widget.repository,
      databaseName: _databaseName,
      transport: widget.transport,
      visibility: _Pages(),
      senderId: 'json-serial-screen',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform;
    return FulfilmentScope(
      controller: _controller,
      child: MaterialApp(
        theme: platform == null
            ? AppTheme.light
            : AppTheme.light.copyWith(platform: platform),
        home: widget.child,
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

Uint8List _singleUnitBytes() => _catalogue(
  stocks: [_stock('A-01', productId, 'SN-0001', 1)],
  orders: [
    _order('ORD-1', '9007199254740993', [_line('Товар', productId, 2)]),
    _order('ORD-2', '42', [_line('Товар', productId, 1)]),
  ],
);

Uint8List _parcelBytes() => _catalogue(
  stocks: [
    _stock('A-01', _parcelId, 'TTN-1', 2),
    _stock('B-02', _parcelId, 'TTN-1', 3),
    _stock('A-01', _parcelId, 'OTHER', 4),
  ],
  orders: [
    _order('ORD-1', '7', [
      _line(
        'Товар Посилка',
        _parcelId,
        4,
        parcelTtn: 'TTN-1',
        meestTtn: '000123',
      ),
    ]),
  ],
);

Uint8List _duplicateSerialBytes() => _catalogue(
  stocks: [
    _stock('A-01', productId, 'SAME', 2),
    _stock('B-02', productId, 'SAME', 4),
    _stock('A-01', '200', 'SAME', 9),
  ],
  orders: [
    _order('ORD-1', '7', [_line('Товар', productId, 3)]),
  ],
);

Uint8List _searchBytes() => _catalogue(
  stocks: [
    _stock('ZZ', productId, 'SN-KEEP', 2),
    _stock('SN-KEEP', productId, 'PLAIN', 2),
    _stock('QQ', productId, 'sn-keep', 2),
  ],
  orders: [
    _order('ORD-1', '7', [_line('Товар', productId, 2)]),
  ],
);

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
      '"Customer":"Клієнт Формат","CustomerPhone":"0501112233","Goods":[{'
      '"Product":"Товар Звичайний","ProductID":1290564103789190763,'
      '"Quantity":2,"Price":10.00,"Amount":19.99,"isServiceGood":0,'
      '"isParcel":0},{"Product":"Товар Посилка",'
      '"ProductID":1290564103789190999,"Quantity":1,"Price":50.00,'
      '"Amount":50.00,"isServiceGood":0,"isParcel":1,'
      '"ParcelTTN":"TTN-PARCEL-1"},{"Product":"Товар Послуга",'
      '"ProductID":1290564103789190888,"Quantity":1,"Price":15.00,'
      '"Amount":15.00,"isServiceGood":1,"isParcel":0}]}]}';
  return Uint8List.fromList(utf8.encode(json));
}

Uint8List _catalogue({
  required List<String> stocks,
  required List<String> orders,
}) {
  final json =
      '{"storeName":"Магазин Тест","dbName":"Store_01-A",'
      '"dateCreate":"20261003114618","stocks":[${stocks.join(',')}],'
      '"orders":[${orders.join(',')}]}';
  return Uint8List.fromList(utf8.encode(json));
}

String _stock(String address, String product, String serial, int quantity) =>
    '{"Address":"$address","ProductID":$product,'
    '"SerialNumber":"$serial","Quantity":$quantity}';

String _order(String id, String number, List<String> goods) =>
    '{"OrderID":"$id","InvoiceDate":"20261003114618",'
    '"InvoiceNumber":"INV-$id","OrderNumber":$number,'
    '"Customer":"Клієнт","CustomerPhone":"0501112233",'
    '"Goods":[${goods.join(',')}]}';

String _line(
  String name,
  String id,
  int quantity, {
  String? parcelTtn,
  String? meestTtn,
}) {
  final parcel = parcelTtn == null ? 0 : 1;
  final ttn = parcelTtn == null ? '' : ',"ParcelTTN":"$parcelTtn"';
  final meest = meestTtn == null ? '' : ',"MeestTTN":"$meestTtn"';
  return '{"Product":"$name","ProductID":$id,"Quantity":$quantity,'
      '"Price":10.00,"Amount":10.00,"isServiceGood":0,"isParcel":$parcel$ttn$meest}';
}
