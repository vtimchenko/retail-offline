import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/domain/fulfilment/session_snapshot.dart';
import 'package:retail_offline/persistence/fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_repository.dart';
import 'package:retail_offline/persistence/indexeddb/indexeddb_fulfilment_schema.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';

void main() {
  test('non-web builds report IndexedDB as unavailable', () async {
    final repository = IndexedDbFulfilmentRepository();
    final snapshot = SessionSnapshot(
      schemaVersion: 1,
      datasetFingerprint: 'a' * 64,
      reservations: const [],
      issuedOrderIds: const [],
      exportedOrderIds: const [],
    );
    final document = ExportDocument(
      filename: 'export_Store_01-A_20261014150722.json',
      bytes: Uint8List.fromList(const [1]),
      dateCreate: '20261014150722',
    );

    expect(
      repository.databaseName,
      IndexedDbFulfilmentSchema.productionDatabaseName,
    );
    expect(await repository.load(), isA<LoadStorageUnavailable>());
    repository.abortNextTransaction = true;
    expect(
      await repository.importDataset(
        bytes: Uint8List(0),
        fingerprint: 'a' * 64,
        snapshot: snapshot,
      ),
      isA<CommitStorageUnavailable>(),
    );
    expect(
      await repository.replaceDataset(
        expectedRevision: 1,
        bytes: Uint8List(0),
        fingerprint: 'a' * 64,
        snapshot: snapshot,
      ),
      isA<CommitStorageUnavailable>(),
    );
    expect(
      await repository.commitSession(expectedRevision: 1, snapshot: snapshot),
      isA<CommitStorageUnavailable>(),
    );
    expect(
      await repository.commitExport(
        expectedRevision: 1,
        snapshot: snapshot,
        document: document,
      ),
      isA<CommitStorageUnavailable>(),
    );
  });

  test('a test database name is kept and is not the production name', () {
    final repository = IndexedDbFulfilmentRepository(
      databaseName: 'retail-offline-test-stub',
    );

    expect(repository.databaseName, 'retail-offline-test-stub');
    expect(
      repository.databaseName,
      isNot(IndexedDbFulfilmentSchema.productionDatabaseName),
    );
  });
}
