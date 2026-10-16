@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/app.dart';
import 'package:retail_offline/application/fulfilment_application.dart';
import 'package:retail_offline/application/fulfilment_scope.dart';
import 'package:retail_offline/application/fulfilment_tab_coordinator.dart';
import 'package:retail_offline/application/fulfilment_ui_controller.dart';
import 'package:retail_offline/application/page_visibility.dart';
import 'package:retail_offline/domain/fulfilment/fulfilment_session.dart';
import 'package:retail_offline/persistence/browser/storage_change_notice.dart';
import 'package:retail_offline/persistence/dataset_fingerprint.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_repository.dart';
import 'package:retail_offline/screens/store_selection/store_selection_screen.dart';

import 'application/fulfilment_application_test.dart';
import 'persistence/indexeddb_probe.dart';

void main() {
  var sequence = 0;
  late String databaseName;

  setUp(() {
    sequence += 1;
    databaseName =
        'retail-offline-test-app-$sequence-'
        '${DateTime.now().microsecondsSinceEpoch}';
    requireTestDatabase(databaseName);
  });

  testWidgets('a fresh database imports and a new app restores the session', (
    tester,
  ) async {
    addTearDown(() async {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        await tester.runAsync(
          () => IndexedDbProbe(databaseName).deleteDatabase(),
        );
      }
    });

    final bytes = datasetBytes();
    final fingerprint = DatasetFingerprint.of(bytes);
    final firstRepository = IndexedDbFulfilmentRepository(
      databaseName: databaseName,
    );

    await tester.pumpWidget(_app(firstRepository, databaseName));
    await tester.pump();

    expect(find.byType(StoreSelectionScreen), findsOneWidget);
    expect(find.byType(FulfilmentScope), findsOneWidget);
    final first = _controller(tester);
    expect(first.coordinator.application.repository, same(firstRepository));
    expect(first.phase, FulfilmentUiPhase.loading);

    await _untilPhase(tester, FulfilmentUiPhase.empty);

    expect(find.byType(StoreSelectionScreen), findsOneWidget);
    expect(first.phase, FulfilmentUiPhase.empty);
    expect(first.session, isNull);

    final imported = await tester.runAsync(() => first.importDataset(bytes));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(imported, isA<FulfilmentImported>());
    expect(first.phase, FulfilmentUiPhase.ready);
    expect(first.revision, 1);
    expect(first.fingerprint, fingerprint);
    final firstSession = first.session;
    expect(firstSession, isNotNull);
    expect(firstSession!.dataset.storeName, 'Магазин Тест');
    expect(find.byType(StoreSelectionScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(first.coordinator.isClosed, isTrue);
    expect(find.byType(RetailOfflineApp), findsNothing);
    expect(find.byType(StoreSelectionScreen), findsNothing);
    expect(find.byType(FulfilmentScope), findsNothing);

    final secondRepository = IndexedDbFulfilmentRepository(
      databaseName: databaseName,
    );
    expect(secondRepository, isNot(same(firstRepository)));

    await tester.pumpWidget(_app(secondRepository, databaseName));
    await tester.pump();

    expect(find.byType(StoreSelectionScreen), findsOneWidget);
    final second = _controller(tester);
    expect(second, isNot(same(first)));
    expect(second.coordinator.application.repository, same(secondRepository));
    expect(second.phase, FulfilmentUiPhase.loading);

    await _untilPhase(tester, FulfilmentUiPhase.ready);

    final restored = second.session;
    expect(restored, isNotNull);
    expect(restored, isNot(same(firstSession)));
    expect(second.phase, FulfilmentUiPhase.ready);
    expect(second.revision, 1);
    expect(second.fingerprint, fingerprint);
    expect(restored!.dataset.storeName, 'Магазин Тест');
    expect(restored.dataset.dbName, 'Store_01-A');
    expect(restored.dataset.dateCreate, DateTime(2026, 10, 3, 11, 46, 18));
    final order = restored.dataset.orders.singleWhere(
      (candidate) => candidate.orderId == 'ORD-1',
    );
    expect(order.orderNumber.literal, '9007199254740993');
    final good = order.goods.single;
    expect(good.productId.literal, '1290564103789190763');
    expect(good.isServiceGood, isFalse);
    expect(good.isParcel, isFalse);
    expect(restored.statusOf('ORD-1'), OrderStatus.noSelection);
    expect(find.byType(StoreSelectionScreen), findsOneWidget);
  });
}

RetailOfflineApp _app(
  IndexedDbFulfilmentRepository repository,
  String databaseName,
) {
  return RetailOfflineApp(
    repository: repository,
    databaseName: databaseName,
    transport: _Transport(),
    visibility: _Pages(),
  );
}

FulfilmentUiController _controller(WidgetTester tester) {
  return FulfilmentScope.read(
    tester.element(find.byType(StoreSelectionScreen)),
  );
}

/// Waits until IndexedDB settles the controller to [phase].
///
/// Each turn yields once to the browser, then pumps the fake-async queue.
/// [pump] alone never delivers an IndexedDB callback.
Future<void> _untilPhase(WidgetTester tester, FulfilmentUiPhase phase) async {
  for (var turn = 0; turn < 100; turn++) {
    if (_controller(tester).phase == phase) return;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  fail(
    'Timed out waiting for ${phase.name}. '
    'The controller is ${_controller(tester).phase.name}.',
  );
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
