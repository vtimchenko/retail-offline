import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/errors/dataset_parse_exception.dart';
import '../models/retail_dataset.dart';
import '../services/json/json_dataset_parser.dart';

/// SHA-256 fingerprint of original dataset bytes.
///
/// The digest is 64 lowercase hexadecimal characters. Bytes are hashed as
/// they are given: they are not decoded, trimmed, or written back as JSON.
abstract final class DatasetFingerprint {
  static final RegExp _lowercaseHex = RegExp(r'^[0-9a-f]{64}$');

  /// Number of characters in a canonical fingerprint.
  static const int hexLength = 64;

  /// Whether [fingerprint] is 64 lowercase hexadecimal characters.
  ///
  /// Uppercase hex is rejected. This does not hash anything.
  static bool hasValidFormat(String fingerprint) =>
      _lowercaseHex.hasMatch(fingerprint);

  /// SHA-256 of [bytes] as 64 lowercase hexadecimal characters.
  ///
  /// [bytes] are not copied or modified.
  static String of(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Whether [bytes] hash to [expected].
  ///
  /// An [expected] value that fails [hasValidFormat] does not match.
  /// This does not decode [bytes].
  static bool matches(Uint8List bytes, String expected) {
    if (!hasValidFormat(expected)) return false;
    return of(bytes) == expected;
  }
}

/// Restores a [RetailDataset] from the original file bytes.
///
/// The fingerprint is checked before the bytes are decoded. Parsing uses
/// [JsonDatasetParser], so precision-sensitive identifiers stay text.
class DatasetByteRestore {
  /// Creates a reader that uses [parser] for the JSON dataset.
  const DatasetByteRestore({this.parser = const JsonDatasetParser()});

  /// Parser for a fingerprint-checked UTF-8 document.
  final JsonDatasetParser parser;

  /// Checks [expectedFingerprint], then decodes and parses [bytes].
  ///
  /// [bytes] are hashed before they are interpreted as text. A fingerprint
  /// that is not 64 lowercase hex characters is [DatasetRestoreReason.invalidFingerprint].
  /// A well-formed fingerprint that is not the SHA-256 of [bytes] is
  /// [DatasetRestoreReason.fingerprintMismatch]. UTF-8 and dataset failures
  /// are reached only after the fingerprint matches. The result does not
  /// contain [bytes].
  DatasetRestoreResult restore({
    required Uint8List bytes,
    required String expectedFingerprint,
  }) {
    if (!DatasetFingerprint.hasValidFormat(expectedFingerprint)) {
      return const DatasetRestoreRejected(
        DatasetRestoreReason.invalidFingerprint,
      );
    }
    final actual = DatasetFingerprint.of(bytes);
    if (actual != expectedFingerprint) {
      return const DatasetRestoreRejected(
        DatasetRestoreReason.fingerprintMismatch,
      );
    }

    final String source;
    try {
      source = utf8.decode(bytes);
    } on FormatException {
      return const DatasetRestoreRejected(DatasetRestoreReason.malformedUtf8);
    }

    try {
      return DatasetRestored(
        dataset: parser.parse(source),
        fingerprint: actual,
      );
    } on JsonSyntaxException catch (error) {
      return DatasetRestoreRejected(
        DatasetRestoreReason.malformedJson,
        message: error.message,
      );
    } on DatasetValidationException catch (error) {
      return DatasetRestoreRejected(
        DatasetRestoreReason.invalidDataset,
        message: error.message,
      );
    }
  }
}

/// Outcome of [DatasetByteRestore.restore].
@immutable
sealed class DatasetRestoreResult {
  const DatasetRestoreResult();
}

/// The original bytes matched [fingerprint] and parsed as [dataset].
final class DatasetRestored extends DatasetRestoreResult {
  /// Creates a successful restore result.
  const DatasetRestored({required this.dataset, required this.fingerprint});

  /// Dataset produced by [JsonDatasetParser].
  final RetailDataset dataset;

  /// SHA-256 hex of the original bytes.
  final String fingerprint;
}

/// The original bytes could not become a dataset.
final class DatasetRestoreRejected extends DatasetRestoreResult {
  /// Creates a rejection.
  ///
  /// [message] is the parser's Ukrainian text when [reason] is
  /// [DatasetRestoreReason.malformedJson] or
  /// [DatasetRestoreReason.invalidDataset]. It is null for a fingerprint or
  /// UTF-8 failure, and it does not include the file bytes.
  const DatasetRestoreRejected(this.reason, {this.message});

  /// Why these bytes were rejected.
  final DatasetRestoreReason reason;

  /// Store-employee message from the dataset parser, when there is one.
  final String? message;

  @override
  String toString() => 'DatasetRestoreRejected($reason)';
}

/// Why [DatasetByteRestore.restore] rejected its input.
enum DatasetRestoreReason {
  /// The expected fingerprint is not 64 lowercase hexadecimal characters.
  invalidFingerprint,

  /// The expected fingerprint is not the SHA-256 of the supplied bytes.
  fingerprintMismatch,

  /// The bytes are not strict UTF-8.
  malformedUtf8,

  /// The UTF-8 text is not JSON the dataset parser accepts.
  malformedJson,

  /// The JSON is well formed and the dataset rules reject it.
  invalidDataset,
}
