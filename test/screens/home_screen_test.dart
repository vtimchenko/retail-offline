import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retail_offline/core/theme/app_theme.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';
import 'package:retail_offline/screens/home/home_controller.dart';
import 'package:retail_offline/screens/home/home_screen.dart';
import 'package:retail_offline/services/file/google_drive_file_service.dart';
import 'package:retail_offline/services/file/local_file_service.dart';

import '../support/fixtures.dart';

const _store = Store(nameStore: 'ТВ Тестовий Магазин 1', idStore: '42');
const _driveUrl =
    'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz_0123-45/view';

final _orders = ordersXlsx(sampleOrderRows());
final _inventory = inventoryXlsx(sampleInventoryRows());

typedef _Pick = ({String name, Uint8List bytes});

HomeController _controller(
  SessionDataRepository repo,
  List<_Pick> picks, {
  MockClientHandler? drive,
}) {
  final queue = [...picks];
  return HomeController(
    repository: repo,
    localFiles: LocalFileService(
      picker: () async => queue.isEmpty ? null : queue.removeAt(0),
    ),
    googleDrive: GoogleDriveFileService(
      client: MockClient(drive ?? (_) async => http.Response('blocked', 403)),
    ),
  );
}

Future<void> _pumpHome(
  WidgetTester tester,
  HomeController controller, {
  Size size = const Size(1000, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: HomeScreen(store: _store, controller: controller),
    ),
  );
}

Finder get _loadButton => find.byKey(const Key('load-data'));
bool _loadEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_loadButton).onPressed != null;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the store name and two independent file sections', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), const []),
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('ТВ Тестовий Магазин 1'), findsOneWidget);
    expect(find.text('Файл замовлень'), findsOneWidget);
    expect(find.text('Файл залишків'), findsOneWidget);
    expect(find.text('Обрати файл'), findsNWidgets(2));
    expect(find.text('Посилання Google Drive'), findsNWidgets(2));
    expect(find.text('Не обрано'), findsNWidgets(2));
  });

  testWidgets('"Завантажити дані" is disabled with no files', (tester) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), const []),
    );
    expect(find.text('Завантажити дані'), findsOneWidget);
    expect(_loadEnabled(tester), isFalse);
  });

  testWidgets('"Завантажити дані" stays disabled with only ONE file', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), [
        (name: 'orders.xlsx', bytes: _orders),
      ]),
    );
    await _tap(tester, 'orders-select-file');

    expect(find.text('orders.xlsx'), findsOneWidget);
    expect(find.text('Джерело: Локальний файл'), findsOneWidget);
    expect(find.text('Обрано'), findsOneWidget);
    expect(_loadEnabled(tester), isFalse);
  });

  testWidgets('also disabled when only the inventory file is chosen', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), [
        (name: 'inventory.xlsx', bytes: _inventory),
      ]),
    );
    await _tap(tester, 'inventory-select-file');
    expect(_loadEnabled(tester), isFalse);
  });

  testWidgets('enabled once BOTH valid files are chosen', (tester) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), [
        (name: 'orders.xlsx', bytes: _orders),
        (name: 'inventory.xlsx', bytes: _inventory),
      ]),
    );
    await _tap(tester, 'orders-select-file');
    await _tap(tester, 'inventory-select-file');

    expect(_loadEnabled(tester), isTrue);
    expect(find.text('Обрано'), findsNWidgets(2));
  });

  testWidgets(
    'an invalid file shows a Ukrainian error and keeps Load disabled',
    (tester) async {
      await _pumpHome(
        tester,
        _controller(InMemorySessionDataRepository(), [
          (name: 'orders.xls', bytes: _orders),
          (name: 'inventory.xlsx', bytes: _inventory),
        ]),
      );
      await _tap(tester, 'orders-select-file');
      await _tap(tester, 'inventory-select-file');

      expect(find.byKey(const Key('orders-error')), findsOneWidget);
      expect(find.textContaining('.xlsx'), findsWidgets);
      expect(find.text('Помилка'), findsOneWidget);
      expect(_loadEnabled(tester), isFalse);
    },
  );

  testWidgets('loading shows calculated Orders / Items / Inventory counts', (
    tester,
  ) async {
    final repo = InMemorySessionDataRepository();
    await _pumpHome(
      tester,
      _controller(repo, [
        (name: 'orders.xlsx', bytes: _orders),
        (name: 'inventory.xlsx', bytes: _inventory),
      ]),
    );
    await _tap(tester, 'orders-select-file');
    await _tap(tester, 'inventory-select-file');
    await tester.tap(_loadButton);
    await tester.pump(); // importing state
    expect(find.text('Обробка файлів…'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(repo.hasData, isTrue);
    expect(find.text('Дані завантажено'), findsOneWidget);
    expect(find.text('Замовлень: ${repo.orderCount}'), findsOneWidget);
    expect(
      find.text('Товарних позицій: ${repo.orderItemCount}'),
      findsOneWidget,
    );
    expect(
      find.text('Записів залишків: ${repo.inventoryCount}'),
      findsOneWidget,
    );
    // Sample data: 5 Excel rows form 3 orders.
    expect(repo.orderCount, 3);
    expect(repo.orderItemCount, 5);
    expect(find.text('Завантажено'), findsNWidgets(2));
    // Stays on the home screen.
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'failure in the second file shows the error and commits nothing',
    (tester) async {
      final repo = InMemorySessionDataRepository();
      await _pumpHome(
        tester,
        _controller(repo, [
          (name: 'orders.xlsx', bytes: _orders),
          (
            name: 'inventory.xlsx',
            bytes: inventoryXlsx([inventoryRow(quantity: 'x')]),
          ),
        ]),
      );
      await _tap(tester, 'orders-select-file');
      await _tap(tester, 'inventory-select-file');
      await tester.tap(_loadButton);
      await tester.pumpAndSettle();

      expect(repo.hasData, isFalse);
      expect(find.byKey(const Key('inventory-error')), findsOneWidget);
      expect(find.byKey(const Key('orders-error')), findsNothing);
      expect(find.text('Дані завантажено'), findsNothing);
    },
  );

  testWidgets(
    'Google Drive dialog validates the link, then reports a blocked download',
    (tester) async {
      final repo = InMemorySessionDataRepository();
      await _pumpHome(
        tester,
        _controller(repo, [(name: 'inventory.xlsx', bytes: _inventory)]),
      );

      await _tap(tester, 'orders-google-drive');
      expect(find.byKey(const Key('drive-url-field')), findsOneWidget);

      // Invalid link: the dialog stays open with a message.
      await tester.enterText(
        find.byKey(const Key('drive-url-field')),
        'not a link',
      );
      await _tap(tester, 'drive-url-submit');
      expect(find.byKey(const Key('drive-url-field')), findsOneWidget);
      expect(
        find.textContaining('посилання на файл Google Drive'),
        findsOneWidget,
      );

      // Valid link, but the (stubbed) download is blocked.
      await tester.enterText(
        find.byKey(const Key('drive-url-field')),
        _driveUrl,
      );
      await _tap(tester, 'drive-url-submit');
      expect(find.byKey(const Key('drive-url-field')), findsNothing);
      expect(find.byKey(const Key('orders-error')), findsOneWidget);
      expect(find.textContaining('Google не дозволив'), findsOneWidget);

      // Local import still works for the same slot.
      await _tap(tester, 'inventory-select-file');
      expect(find.text('inventory.xlsx'), findsOneWidget);
    },
  );

  testWidgets('Google Drive file is shown with its source and enables Load', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _controller(
        InMemorySessionDataRepository(),
        [(name: 'inventory.xlsx', bytes: _inventory)],
        drive: (_) async => http.Response.bytes(
          _orders,
          200,
          headers: {
            'content-disposition': 'attachment; filename="drive-orders.xlsx"',
          },
        ),
      ),
    );
    await _tap(tester, 'orders-google-drive');
    await tester.enterText(find.byKey(const Key('drive-url-field')), _driveUrl);
    await _tap(tester, 'drive-url-submit');
    await _tap(tester, 'inventory-select-file');

    expect(find.text('drive-orders.xlsx'), findsOneWidget);
    expect(find.text('Джерело: Google Drive'), findsOneWidget);
    expect(_loadEnabled(tester), isTrue);
  });

  testWidgets('narrow (phone) layout stacks the cards without overflow', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), [
        (
          name: 'orders-with-a-rather-long-file-name-for-a-phone-screen.xlsx',
          bytes: _orders,
        ),
      ]),
      size: const Size(360, 900),
    );
    await _tap(tester, 'orders-select-file');

    expect(tester.takeException(), isNull);
    final ordersTop = tester.getTopLeft(find.text('Файл замовлень')).dy;
    final inventoryTop = tester.getTopLeft(find.text('Файл залишків')).dy;
    expect(inventoryTop, greaterThan(ordersTop + 50));
  });

  testWidgets('wide layout puts the cards side by side', (tester) async {
    await _pumpHome(
      tester,
      _controller(InMemorySessionDataRepository(), const []),
    );
    final ordersTop = tester.getTopLeft(find.text('Файл замовлень')).dy;
    final inventoryTop = tester.getTopLeft(find.text('Файл залишків')).dy;
    expect(inventoryTop, ordersTop);
  });

  testWidgets('shows existing session data when the screen is reopened', (
    tester,
  ) async {
    final repo = InMemorySessionDataRepository();
    final first = _controller(repo, [
      (name: 'orders.xlsx', bytes: _orders),
      (name: 'inventory.xlsx', bytes: _inventory),
    ]);
    // Real async work (the controller yields to the UI with a timer).
    await tester.runAsync(() async {
      await first.pickLocalFile(ImportSlotId.orders);
      await first.pickLocalFile(ImportSlotId.inventory);
      await first.loadData();
    });

    await _pumpHome(tester, HomeController(repository: repo));
    expect(find.text('Замовлень: 3'), findsOneWidget);
    expect(find.text('Товарних позицій: 5'), findsOneWidget);
  });
}
