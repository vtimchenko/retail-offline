import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'indexeddb_probe_stub.dart' hide IndexedDbProbe;

export 'indexeddb_probe_stub.dart'
    show probeBytes, probeText, requireTestDatabase;

/// Reads and writes one IndexedDB test database.
///
/// Production code does not use this. [requireTestDatabase] rejects the
/// production name before any browser call.
class IndexedDbProbe {
  const IndexedDbProbe(this.databaseName);

  final String databaseName;

  Future<void> deleteDatabase() {
    requireTestDatabase(databaseName);
    return _request(window.indexedDB.deleteDatabase(databaseName));
  }

  Future<List<String>> storeNames() {
    requireTestDatabase(databaseName);
    return _open((IDBDatabase database) {
      return [
        for (var index = 0; index < database.objectStoreNames.length; index++)
          database.objectStoreNames.item(index)!,
      ];
    });
  }

  Future<Map<String, Object>?> read(String store) {
    requireTestDatabase(databaseName);
    return _withDatabase(1, (IDBDatabase database) async {
      final transaction = database.transaction(store.toJS, 'readonly');
      final request = transaction.objectStore(store).get('current'.toJS);
      final copied = Completer<Map<String, Object>?>();
      final retained = <JSFunction>[];
      request.onsuccess = _retain(retained, (Event _) {
        retained.length;
        copied.complete(_copyRecord(request.result));
      });
      await _transaction(transaction);
      return copied.future;
    });
  }

  Future<void> write(String store, Map<String, Object> record) {
    requireTestDatabase(databaseName);
    return _withDatabase(1, (IDBDatabase database) {
      final transaction = database.transaction(store.toJS, 'readwrite');
      transaction.objectStore(store).put(_object(record), 'current'.toJS);
      return _transaction(transaction);
    });
  }

  Future<void> deleteRecord(String store) {
    requireTestDatabase(databaseName);
    return _withDatabase(1, (IDBDatabase database) {
      final transaction = database.transaction(store.toJS, 'readwrite');
      transaction.objectStore(store).delete('current'.toJS);
      return _transaction(transaction);
    });
  }

  Future<void> createDatabaseVersion(int version) {
    requireTestDatabase(databaseName);
    final completer = Completer<void>();
    final retained = <JSFunction>[];
    final request = window.indexedDB.open(databaseName, version);
    request.onupgradeneeded = _retain(retained, (Event _) {
      final database = request.result as IDBDatabase;
      if (!database.objectStoreNames.contains('probe')) {
        database.createObjectStore('probe');
      }
    });
    request.onsuccess = _retain(retained, (Event _) {
      (request.result as IDBDatabase).close();
      retained.length;
      completer.complete();
    });
    request.onerror = _retain(retained, (Event _) {
      completer.completeError(StateError('Could not open version $version.'));
    });
    return completer.future;
  }

  Future<T> _open<T>(FutureOr<T> Function(IDBDatabase database) action) {
    return _withRequest(window.indexedDB.open(databaseName), action);
  }

  Future<T> _withDatabase<T>(
    int version,
    FutureOr<T> Function(IDBDatabase database) action,
  ) {
    return _withRequest(window.indexedDB.open(databaseName, version), action);
  }

  Future<T> _withRequest<T>(
    IDBOpenDBRequest request,
    FutureOr<T> Function(IDBDatabase database) action,
  ) async {
    final completer = Completer<IDBDatabase>();
    final retained = <JSFunction>[];
    request.onsuccess = _retain(retained, (Event _) {
      retained.length;
      completer.complete(request.result as IDBDatabase);
    });
    request.onerror = _retain(retained, (Event _) {
      completer.completeError(StateError('Could not open $databaseName.'));
    });
    final database = await completer.future;
    try {
      return await action(database);
    } finally {
      database.close();
    }
  }

  Future<void> _transaction(IDBTransaction transaction) {
    final completer = Completer<void>();
    final retained = <JSFunction>[];
    transaction.oncomplete = _retain(retained, (Event _) {
      if (completer.isCompleted) return;
      retained.length;
      completer.complete();
    });
    transaction.onabort = _retain(retained, (Event _) {
      if (completer.isCompleted) return;
      completer.completeError(StateError('IndexedDB transaction aborted.'));
    });
    transaction.onerror = _retain(retained, (Event _) {
      if (completer.isCompleted) return;
      completer.completeError(StateError('IndexedDB transaction failed.'));
    });
    return completer.future;
  }

  Future<void> _request(IDBRequest request) {
    final completer = Completer<void>();
    final retained = <JSFunction>[];
    request.onsuccess = _retain(retained, (Event _) {
      retained.length;
      completer.complete();
    });
    request.onerror = _retain(retained, (Event _) {
      completer.completeError(StateError('IndexedDB request failed.'));
    });
    return completer.future;
  }
}

JSFunction _retain(
  List<JSFunction> retained,
  void Function(Event event) listener,
) {
  final function = listener.toJS;
  retained.add(function);
  return function;
}

JSObject _object(Map<String, Object> record) {
  final object = JSObject();
  for (final entry in record.entries) {
    final value = entry.value;
    final JSAny stored = switch (value) {
      final String text => text.toJS,
      final Uint8List bytes => bytes.toJS,
      _ => throw ArgumentError.value(
        value.runtimeType,
        entry.key,
        'Probe records store strings and bytes.',
      ),
    };
    object.setProperty(entry.key.toJS, stored);
  }
  return object;
}

Map<String, Object>? _copyRecord(JSAny? result) {
  if (result == null || result.isNull || result.isUndefined) return null;
  final object = result as JSObject;
  final copied = <String, Object>{};
  for (final key in _objectKeys(object).toDart) {
    final name = key.toDart;
    final value = object.getProperty<JSAny?>(key);
    if (value == null || value.isNull || value.isUndefined) {
      throw StateError('$name was empty.');
    }
    if (value.isA<JSString>()) {
      copied[name] = (value as JSString).toDart;
    } else if (value.isA<JSUint8Array>()) {
      copied[name] = Uint8List.fromList((value as JSUint8Array).toDart);
    } else {
      throw StateError('$name had an unexpected JavaScript type.');
    }
  }
  return copied;
}

@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject object);
