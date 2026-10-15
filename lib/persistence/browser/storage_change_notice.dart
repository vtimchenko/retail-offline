import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../dataset_fingerprint.dart';
import '../indexeddb/indexeddb_fulfilment_schema.dart';

const String _channelPrefix = 'retail-offline:';

/// Browser channel name for tabs that share one IndexedDB database.
///
/// The result is `retail-offline:` followed by [databaseName]. An empty
/// [databaseName] throws [ArgumentError] before a browser API is called.
String storageChangeChannelName(String databaseName) {
  if (databaseName.isEmpty) {
    throw ArgumentError.value(
      databaseName,
      'databaseName',
      'Must not be empty.',
    );
  }
  return '$_channelPrefix$databaseName';
}

final RegExp _senderIdPattern = RegExp(r'^[0-9a-z][0-9a-z-]*$');

const int _senderIdMaxLength = 64;

const Set<String> _jsonFields = {
  'version',
  'revision',
  'fingerprint',
  'senderId',
};

/// One committed-revision hint for other tabs.
///
/// The text is a notification. It is not a session, a dataset, or an export.
/// [revision] stays decimal text. It is not parsed into a JavaScript number.
@immutable
final class StorageChangeNotice {
  /// Creates a version-1 notice.
  ///
  /// [revision] must pass [IndexedDbFulfilmentSchema.tryParseRevision].
  /// [fingerprint] must pass [DatasetFingerprint.hasValidFormat].
  /// [senderId] must match `^[0-9a-z][0-9a-z-]*$` and contain 1 to 64
  /// characters. Anything else throws [ArgumentError].
  StorageChangeNotice({
    required this.revision,
    required this.fingerprint,
    required this.senderId,
  }) : version = versionText {
    if (IndexedDbFulfilmentSchema.tryParseRevision(revision) == null) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Not a safe decimal revision.',
      );
    }
    if (!DatasetFingerprint.hasValidFormat(fingerprint)) {
      throw ArgumentError.value(
        fingerprint,
        'fingerprint',
        'Not a lowercase SHA-256 hex digest.',
      );
    }
    if (!_validSender(senderId)) {
      throw ArgumentError.value(
        senderId,
        'senderId',
        'Must be 1 to 64 characters of lowercase letters, digits, or hyphens.',
      );
    }
  }

  /// Wire version this notice writes.
  static const String versionText = '1';

  /// Message version. Constructed notices use [versionText].
  final String version;

  /// Stored revision, copied as decimal text.
  final String revision;

  /// SHA-256 hex of the dataset bytes.
  final String fingerprint;

  /// Identifier of the instance that published the notice.
  final String senderId;

  /// Encodes this notice as one JSON object.
  ///
  /// Every field is a JSON string. [revision] is written unchanged.
  String toJsonText() {
    return jsonEncode({
      'version': version,
      'revision': revision,
      'fingerprint': fingerprint,
      'senderId': senderId,
    });
  }

  /// Parses one JSON notice.
  ///
  /// Returns `null` when [source] is not a JSON object, the keys are not
  /// exactly `version`, `revision`, `fingerprint`, and `senderId`, a value
  /// is not a JSON string, [version] is not [versionText], or a field would
  /// be rejected by [StorageChangeNotice.new].
  static StorageChangeNotice? tryParse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded.length != _jsonFields.length) return null;
    if (!_jsonFields.containsAll(decoded.keys)) return null;

    final version = decoded['version'];
    final revision = decoded['revision'];
    final fingerprint = decoded['fingerprint'];
    final senderId = decoded['senderId'];
    if (version is! String ||
        revision is! String ||
        fingerprint is! String ||
        senderId is! String) {
      return null;
    }
    if (version != versionText) return null;

    try {
      final notice = StorageChangeNotice(
        revision: revision,
        fingerprint: fingerprint,
        senderId: senderId,
      );
      if (notice.revision != revision) return null;
      return notice;
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StorageChangeNotice &&
      other.version == version &&
      other.revision == revision &&
      other.fingerprint == fingerprint &&
      other.senderId == senderId;

  @override
  int get hashCode => Object.hash(version, revision, fingerprint, senderId);

  @override
  String toString() =>
      'StorageChangeNotice($version, $revision, $fingerprint, $senderId)';
}

bool _validSender(String senderId) {
  return senderId.length <= _senderIdMaxLength &&
      _senderIdPattern.hasMatch(senderId);
}
