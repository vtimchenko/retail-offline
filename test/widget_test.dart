import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/models/order_export.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/repositories/order_export_repository.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/screens/store_selection/store_selection_screen.dart';
import 'package:retail_offline/services/store_service.dart';

StoreService _serviceWith(String json) =>
    StoreService(assetLoader: (_) async => json);

void main() {
  group('StoreService', () {
    test('parses valid stores and skips invalid entries', () async {
      final stores = await _serviceWith(
        '[{"nameStore":"A","idStore":"1"},{"nameStore":"","idStore":"2"},{"x":1}]',
      ).loadStores();
      expect(stores, [const Store(nameStore: 'A', idStore: '1')]);
    });

    test('throws on invalid JSON', () {
      expect(
        _serviceWith('nope').loadStores(),
        throwsA(isA<StoreLoadException>()),
      );
    });

    test('throws when JSON is not a list', () {
      expect(
        _serviceWith('{}').loadStores(),
        throwsA(isA<StoreLoadException>()),
      );
    });
  });

  group('Store.matches', () {
    test('is case-insensitive and multi-word', () {
      const store = Store(nameStore: 'ТВ Київ Хрещатик 1', idStore: 'x');
      expect(store.matches('київ'), isTrue);
      expect(store.matches('ТВ хрещ'), isTrue);
      expect(store.matches('львів'), isFalse);
    });
  });

  testWidgets('select a store and navigate to home screen', (tester) async {
    // Use the real stores.json from the project directory.
    final json = File('stores.json').readAsStringSync();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StoreSelectionScreen(
          storeService: StoreService(assetLoader: (path) async => json),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'Продовжити');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'балаклія');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ТВ Балаклія Захисників 1').last);
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('ТВ Балаклія Захисників 1'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: StoreSelectionScreen(storeService: _serviceWith('[]'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Список магазинів порожній'), findsOneWidget);
  });

  testWidgets('shows error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoreSelectionScreen(storeService: _serviceWith('oops')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не вдалося завантажити магазини'), findsOneWidget);
  });

  testWidgets('a real selection change invalidates only that order export', (
    tester,
  ) async {
    final selections = InMemorySerialSelectionRepository();
    final exports = InMemoryOrderExportRepository()
      ..put(
        OrderExport(
          orderNumber: '907907',
          filename: 'a.xlsx',
          bytes: Uint8List.fromList(const [1]),
        ),
      )
      ..put(
        OrderExport(
          orderNumber: 'other',
          filename: 'b.xlsx',
          bytes: Uint8List.fromList(const [2]),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: StoreSelectionScreen(
          storeService: _serviceWith('[]'),
          selections: selections,
          exports: exports,
        ),
      ),
    );

    const inventory = [
      InventoryBalance(
        address: 'A1',
        productId: '1290564103789190763',
        serialNumber: 'SN001',
        quantity: 1,
      ),
    ];
    expect(
      selections.addOne(
        orderNumber: '907907',
        productId: inventory.single.productId,
        address: inventory.single.address,
        serialNumber: inventory.single.serialNumber,
        inventory: inventory,
        requiredQuantity: 1,
      ),
      isTrue,
    );
    expect(exports.exportFor('907907'), isNull);
    expect(exports.exportFor('other'), isNotNull);

    expect(
      selections.addOne(
        orderNumber: '907907',
        productId: inventory.single.productId,
        address: inventory.single.address,
        serialNumber: inventory.single.serialNumber,
        inventory: inventory,
        requiredQuantity: 1,
      ),
      isFalse,
    );
    expect(exports.exportFor('other')?.filename, 'b.xlsx');
  });
}
