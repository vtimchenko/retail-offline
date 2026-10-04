import 'dart:typed_data';

/// A file chosen in the picker: name plus contents (no filesystem path).
typedef PickedBytes = ({String name, Uint8List bytes});
