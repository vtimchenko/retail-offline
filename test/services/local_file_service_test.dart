import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/models/imported_file.dart';
import 'package:retail_offline/services/file/local_file_service.dart';

import '../support/fixtures.dart';

LocalFileService _picking(PickedBytes? Function() pick) =>
    LocalFileService(picker: () async => pick());

void main() {
  final xlsx = ordersXlsx([orderRow()]);

  test('returns an ImportedFile from bytes (no path involved)', () async {
    final file = await _picking(() => (name: 'orders.xlsx', bytes: xlsx))
        .pickXlsx();
    expect(file, isNotNull);
    expect(file!.name, 'orders.xlsx');
    expect(file.source, FileSource.local);
    expect(file.bytes, xlsx);
  });

  test('extension check is case-insensitive', () async {
    final file = await _picking(() => (name: 'ORDERS.XLSX', bytes: xlsx))
        .pickXlsx();
    expect(file, isNotNull);
  });

  test('cancelling the picker is not an error', () async {
    expect(await _picking(() => null).pickXlsx(), isNull);
  });

  test('rejects other extensions, including legacy .xls', () async {
    for (final name in [
      'orders.xls',
      'orders.csv',
      'orders',
      'orders.xlsx.txt',
    ]) {
      await expectLater(
        _picking(() => (name: name, bytes: xlsx)).pickXlsx(),
        throwsA(isA<ImportException>()),
        reason: name,
      );
    }
  });

  test('rejects an empty file', () async {
    await expectLater(
      _picking(() => (name: 'a.xlsx', bytes: Uint8List(0))).pickXlsx(),
      throwsA(isA<ImportException>()),
    );
  });

  test('rejects content that is only NAMED .xlsx', () async {
    final text = Uint8List.fromList('just some text'.codeUnits);
    await expectLater(
      _picking(() => (name: 'fake.xlsx', bytes: text)).pickXlsx(),
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          contains('Excel'),
        ),
      ),
    );
  });

  test('picker failures become a friendly error', () async {
    final service = LocalFileService(
      picker: () async => throw StateError('boom'),
    );
    await expectLater(
      service.pickXlsx(),
      throwsA(
        isA<ImportException>().having(
          (e) => e.message,
          'message',
          isNot(contains('boom')),
        ),
      ),
    );
  });
}
