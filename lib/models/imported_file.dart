import 'package:flutter/foundation.dart';

/// Where the bytes of an [ImportedFile] came from.
enum FileSource { local, googleDrive }

/// A file obtained from any [FileSource]. Everything after acquisition
/// (validation, XLSX reading, parsing) works only with this type and never
/// cares about where the bytes came from.
@immutable
class ImportedFile {
  const ImportedFile({
    required this.name,
    required this.bytes,
    required this.source,
  });

  final String name;
  final Uint8List bytes;
  final FileSource source;

  @override
  String toString() => 'ImportedFile($name, ${bytes.length} B, $source)';
}
