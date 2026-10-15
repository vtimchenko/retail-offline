// Browser storage-change notifications behind a conditional export, so VM
// tests (which cannot compile `package:web`) keep working.
export 'storage_change_channel_stub.dart'
    if (dart.library.js_interop) 'storage_change_channel_web.dart';
