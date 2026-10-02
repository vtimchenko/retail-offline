import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/constants/app_constants.dart';
import '../models/store.dart';

/// Thrown when the list of stores cannot be loaded or parsed.
class StoreLoadException implements Exception {
  const StoreLoadException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'StoreLoadException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Loads the list of stores from the bundled `stores.json` asset.
class StoreService {
  const StoreService({
    this.assetPath = AppConstants.storesAssetPath,
    Future<String> Function(String path)? assetLoader,
  }) : _assetLoader = assetLoader ?? _defaultLoader;

  final String assetPath;
  final Future<String> Function(String path) _assetLoader;

  static Future<String> _defaultLoader(String path) =>
      rootBundle.loadString(path);

  /// Returns all valid stores. Malformed entries are skipped; an empty list
  /// is returned if the file contains no valid stores. Throws
  /// [StoreLoadException] if the file is missing or is not a JSON list.
  Future<List<Store>> loadStores() async {
    final String raw;
    try {
      raw = await _assetLoader(assetPath);
    } catch (e) {
      throw StoreLoadException('Cannot read $assetPath', e);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw StoreLoadException('$assetPath is not valid JSON', e);
    }
    if (decoded is! List) {
      throw const StoreLoadException('Expected a JSON list of stores');
    }

    final stores = <Store>[];
    final seenIds = <String>{};
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final store = Store.fromJson(item);
        if (seenIds.add(store.idStore)) stores.add(store);
      } on FormatException catch (e) {
        debugPrint('Skipping invalid store entry: $e');
      }
    }
    return stores;
  }
}
