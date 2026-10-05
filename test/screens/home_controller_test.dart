import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retail_offline/core/constants/import_messages.dart';
import 'package:retail_offline/models/imported_file.dart';
import 'package:retail_offline/models/inventory_balance.dart';
import 'package:retail_offline/repositories/serial_selection_repository.dart';
import 'package:retail_offline/repositories/session_data_repository.dart';
import 'package:retail_offline/screens/home/home_controller.dart';
import 'package:retail_offline/services/file/google_drive_file_service.dart';
import 'package:retail_offline/services/file/local_file_service.dart';

import '../support/fixtures.dart';

const _driveUrl =
    'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz_0123-45/view';

/// Hands out queued files, as if the user picked them one after another.
LocalFileService _picker(List<({String name, Uint8List bytes})> queue) =>
    LocalFileService(
      picker: () async => queue.isEmpty ? null : queue.removeAt(0),
    );

HomeController _controller(
  SessionDataRepository repo, {
  SerialSelectionRepository? selections,
  List<({String name, Uint8List bytes})> picks = const [],
  MockClientHandler? drive,
}) => HomeController(
  repository: repo,
  selections: selections,
  localFiles: _picker([...picks]),
  googleDrive: GoogleDriveFileService(
    client: MockClient(drive ?? (_) async => http.Response('blocked', 403)),
  ),
);

final _goodOrders = ordersXlsx(sampleOrderRows());
final _goodInventory = inventoryXlsx(sampleInventoryRows());

void main() {
  group('slot state', () {
    test('starts empty and cannot load', () {
      final c = _controller(InMemorySessionDataRepository());
      expect(c.orders.status, SlotStatus.empty);
      expect(c.inventory.status, SlotStatus.empty);
      expect(c.canLoad, isFalse);
    });

    test('only one file → cannot load; both → can load', () async {
      final c = _controller(
        InMemorySessionDataRepository(),
        picks: [
          (name: 'orders.xlsx', bytes: _goodOrders),
          (name: 'inventory.xlsx', bytes: _goodInventory),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      expect(c.orders.status, SlotStatus.ready);
      expect(c.canLoad, isFalse);

      await c.pickLocalFile(ImportSlotId.inventory);
      expect(c.inventory.status, SlotStatus.ready);
      expect(c.canLoad, isTrue);
    });

    test('cancelling the picker changes nothing', () async {
      final c = _controller(InMemorySessionDataRepository());
      await c.pickLocalFile(ImportSlotId.orders);
      expect(c.orders.status, SlotStatus.empty);
      expect(c.orders.error, isNull);
    });

    test('a wrong file type puts the slot into error', () async {
      final c = _controller(
        InMemorySessionDataRepository(),
        picks: [(name: 'orders.csv', bytes: _goodOrders)],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      expect(c.orders.status, SlotStatus.error);
      expect(c.orders.error, contains('.xlsx'));
      expect(c.canLoad, isFalse);
    });

    test(
      'Google Drive failure affects only its slot; local keeps working',
      () async {
        final c = _controller(
          InMemorySessionDataRepository(),
          picks: [(name: 'inventory.xlsx', bytes: _goodInventory)],
        );
        await c.pickGoogleDriveFile(ImportSlotId.orders, _driveUrl);
        expect(c.orders.status, SlotStatus.error);
        expect(c.orders.error, ImportMessages.driveDownloadBlocked);

        await c.pickLocalFile(ImportSlotId.inventory);
        expect(c.inventory.status, SlotStatus.ready);

        // And the Drive-failed slot can still be fixed with a local file.
        final c2 = _controller(
          InMemorySessionDataRepository(),
          picks: [(name: 'orders.xlsx', bytes: _goodOrders)],
        );
        await c2.pickGoogleDriveFile(ImportSlotId.orders, _driveUrl);
        await c2.pickLocalFile(ImportSlotId.orders);
        expect(c2.orders.status, SlotStatus.ready);
        expect(c2.orders.error, isNull);
      },
    );

    test('invalid Drive link is reported without a request', () async {
      var requests = 0;
      final c = _controller(
        InMemorySessionDataRepository(),
        drive: (_) async {
          requests++;
          return http.Response('', 200);
        },
      );
      await c.pickGoogleDriveFile(ImportSlotId.orders, 'not a link');
      expect(requests, 0);
      expect(c.orders.status, SlotStatus.error);
    });

    test(
      'any source combination works (Drive orders + local inventory)',
      () async {
        final c = _controller(
          InMemorySessionDataRepository(),
          picks: [(name: 'inventory.xlsx', bytes: _goodInventory)],
          drive: (_) async => http.Response.bytes(_goodOrders, 200),
        );
        await c.pickGoogleDriveFile(ImportSlotId.orders, _driveUrl);
        await c.pickLocalFile(ImportSlotId.inventory);

        expect(c.orders.file!.source, FileSource.googleDrive);
        expect(c.inventory.file!.source, FileSource.local);
        expect(c.canLoad, isTrue);

        expect(await c.loadData(), isTrue);
        expect(c.summary!.orders, 3);
      },
    );
  });

  group('loadData – atomic import', () {
    test('commits both datasets and reports calculated counts', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [
          (name: 'orders.xlsx', bytes: _goodOrders),
          (name: 'inventory.xlsx', bytes: _goodInventory),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isTrue);

      expect(repo.hasData, isTrue);
      expect(c.summary!.orders, 3);
      expect(c.summary!.orderItems, 5);
      expect(c.summary!.inventoryRecords, 4);
      expect(repo.orderByNumber('900000002')!.items, hasLength(3));
      expect(c.orders.status, SlotStatus.loaded);
      expect(c.inventory.status, SlotStatus.loaded);
      expect(c.isImporting, isFalse);
    });

    test('Orders valid + Inventory invalid → NOTHING is committed', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [
          (name: 'orders.xlsx', bytes: _goodOrders),
          (
            name: 'inventory.xlsx',
            bytes: inventoryXlsx(
              [inventoryRow()],
              headers: ['Address', 'ProductID', 'Quantity'], // no SerialNumber
            ),
          ),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isFalse);

      expect(repo.hasData, isFalse);
      expect(repo.orderCount, 0);
      expect(c.summary, isNull);
      expect(c.inventory.status, SlotStatus.error);
      expect(c.inventory.error, contains('SerialNumber'));
      // The orders file itself is fine and is not blamed.
      expect(c.orders.status, SlotStatus.ready);
      expect(c.orders.error, isNull);
      expect(c.isImporting, isFalse);
    });

    test('Orders invalid → Inventory is not committed either', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [
          (name: 'orders.xlsx', bytes: ordersXlsx([orderRow(quantity: 'x')])),
          (name: 'inventory.xlsx', bytes: _goodInventory),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isFalse);

      expect(repo.hasData, isFalse);
      expect(repo.inventoryCount, 0);
      expect(c.orders.status, SlotStatus.error);
      expect(c.orders.error, contains('рядку 2'));
    });

    test('a failed re-import keeps previously loaded session data', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [
          (name: 'orders.xlsx', bytes: _goodOrders),
          (name: 'inventory.xlsx', bytes: _goodInventory),
          // second round: valid orders, broken inventory
          (name: 'orders2.xlsx', bytes: ordersXlsx([orderRow()])),
          (
            name: 'inventory2.xlsx',
            bytes: inventoryXlsx([inventoryRow(quantity: 'oops')]),
          ),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isTrue);
      final before = repo.orders;
      expect(repo.orderCount, 3);

      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isFalse);

      expect(identical(repo.orders, before), isTrue);
      expect(repo.orderCount, 3);
      expect(repo.orderItemCount, 5);
      expect(repo.inventoryCount, 4);
      expect(repo.orderByNumber('900000001'), isNotNull);
      expect(c.summary!.orders, 3); // still describes the repository
      expect(c.inventory.status, SlotStatus.error);
    });

    test('inconsistent order data is reported on the orders slot', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [
          (
            name: 'orders.xlsx',
            bytes: ordersXlsx([
              orderRow(),
              orderRow(customerPhone: '0990000000'),
            ]),
          ),
          (name: 'inventory.xlsx', bytes: _goodInventory),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isFalse);

      expect(repo.hasData, isFalse);
      expect(c.orders.error, contains('CustomerPhone'));
    });

    test('canLoad is false when nothing new would be loaded', () async {
      final c = _controller(
        InMemorySessionDataRepository(),
        picks: [
          (name: 'orders.xlsx', bytes: _goodOrders),
          (name: 'inventory.xlsx', bytes: _goodInventory),
        ],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      await c.pickLocalFile(ImportSlotId.inventory);
      expect(await c.loadData(), isTrue);
      expect(c.canLoad, isFalse);
    });

    test(
      'a failed re-import keeps selections; a successful one clears them',
      () async {
        final repo = InMemorySessionDataRepository();
        final selections = InMemorySerialSelectionRepository();
        const balance = InventoryBalance(
          address: r'$$AGVI',
          productId: bigProductId,
          serialNumber: 'SN-0001',
          quantity: 1,
        );
        final c = _controller(
          repo,
          selections: selections,
          picks: [
            (name: 'orders.xlsx', bytes: _goodOrders),
            (name: 'inventory.xlsx', bytes: _goodInventory),
            (name: 'orders2.xlsx', bytes: ordersXlsx([orderRow()])),
            (
              name: 'inventory2.xlsx',
              bytes: inventoryXlsx([inventoryRow(quantity: 'oops')]),
            ),
            (name: 'orders3.xlsx', bytes: _goodOrders),
            (name: 'inventory3.xlsx', bytes: _goodInventory),
          ],
        );

        await c.pickLocalFile(ImportSlotId.orders);
        await c.pickLocalFile(ImportSlotId.inventory);
        expect(await c.loadData(), isTrue);
        expect(
          selections.addOne(
            orderNumber: '900000001',
            productId: bigProductId,
            address: balance.address,
            serialNumber: balance.serialNumber,
            inventory: const [balance],
            requiredQuantity: 1,
          ),
          isTrue,
        );

        await c.pickLocalFile(ImportSlotId.orders);
        await c.pickLocalFile(ImportSlotId.inventory);
        expect(await c.loadData(), isFalse);
        expect(selections.selectedQuantity('900000001', bigProductId), 1);
        expect(repo.orderCount, 3);

        await c.pickLocalFile(ImportSlotId.orders);
        await c.pickLocalFile(ImportSlotId.inventory);
        expect(await c.loadData(), isTrue);
        expect(selections.selectedQuantity('900000001', bigProductId), 0);
      },
    );

    test('loadData without two usable files does nothing', () async {
      final repo = InMemorySessionDataRepository();
      final c = _controller(
        repo,
        picks: [(name: 'orders.xlsx', bytes: _goodOrders)],
      );
      await c.pickLocalFile(ImportSlotId.orders);
      expect(await c.loadData(), isFalse);
      expect(repo.hasData, isFalse);
    });
  });
}
