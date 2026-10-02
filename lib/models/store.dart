import 'package:flutter/foundation.dart';

/// A retail store the employee can work in.
@immutable
class Store {
  const Store({required this.nameStore, required this.idStore});

  /// Parses a store from a JSON object. Throws [FormatException] if required
  /// fields are missing, have the wrong type or are blank.
  factory Store.fromJson(Map<String, dynamic> json) {
    final name = json['nameStore'];
    final id = json['idStore'];
    if (name is! String ||
        id is! String ||
        name.trim().isEmpty ||
        id.trim().isEmpty) {
      throw FormatException('Invalid store entry: $json');
    }
    return Store(nameStore: name.trim(), idStore: id.trim());
  }

  final String nameStore;
  final String idStore;

  /// Case-insensitive match: every whitespace-separated word of [query]
  /// must occur in [nameStore].
  bool matches(String query) {
    final name = nameStore.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(name.contains);
  }

  @override
  bool operator ==(Object other) =>
      other is Store &&
      other.idStore == idStore &&
      other.nameStore == nameStore;

  @override
  int get hashCode => Object.hash(idStore, nameStore);

  @override
  String toString() => 'Store($idStore, $nameStore)';
}
