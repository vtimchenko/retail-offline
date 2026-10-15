@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/services/file/cumulative_export_share.dart';
import 'package:retail_offline/services/file/export_share.dart';
import 'package:retail_offline/services/json/cumulative_json_export.dart';

/// Chrome stand-ins for `navigator.share` and the download click.
///
/// The stubs record the payload and do not open a share sheet or start a
/// download. A passing run does not establish Safari, iOS PWA, or Android
/// share-sheet behavior.

const _productId = '1290564103789190763';
const _orderNumber = '9007199254740993';
const _filename = 'export_Store_01-A_20261014150722.json';

final Uint8List _bytes = Uint8List.fromList([
  ...utf8.encode('{"ProductID":$_productId,"OrderNumber":$_orderNumber}'),
  0xFF,
  0x00,
  0xFE,
]);

void main() {
  _ShareHarness? installed;

  setUp(() => installed = _ShareHarness.install());

  tearDown(() async {
    final harness = installed;
    installed = null;
    if (harness == null) return;
    await harness.settle();
    harness.restore();
  });

  _ShareHarness harness() {
    final active = installed;
    if (active == null) {
      throw StateError('The share harness is not installed.');
    }
    return active;
  }

  test('canShare missing downloads once with the original bytes', () async {
    harness().canShareMode = 'missing';

    final pending = shareOrDownloadJson(filename: _filename, bytes: _bytes);
    expect(harness().clickCount, 1);
    expect(harness().shareCalls, 0);

    await _expectDownload(
      harness(),
      await pending,
      ExportShareDownloadReason.sharingUnavailable,
      shareCalls: 0,
    );
  });

  test(
    'canShare false downloads once and keeps a files-only payload',
    () async {
      harness().canShareMode = 'false';

      final pending = shareOrDownloadJson(filename: _filename, bytes: _bytes);
      expect(harness().clickCount, 1);
      expect(harness().shareCalls, 0);
      expect(harness().canShareCalls, 1);

      await _expectDownload(
        harness(),
        await pending,
        ExportShareDownloadReason.sharingUnavailable,
        shareCalls: 0,
      );
      expect(harness().payloads.single, _filesOnlyPayload());
      expect(await harness().fileBytes(0), _bytes);
    },
  );

  test('a throwing canShare downloads once', () async {
    harness().canShareMode = 'throw';

    final result = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    await _expectDownload(
      harness(),
      result,
      ExportShareDownloadReason.sharingUnavailable,
      shareCalls: 0,
    );
    expect(harness().canShareCalls, 1);
  });

  test('a resolved share hands off the file and does not download', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'resolve';

    final pending = shareOrDownloadJson(filename: _filename, bytes: _bytes);
    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);
    expect(harness().created, isEmpty);

    final result = await pending;

    expect(result, isA<ExportShareHandedOff>());
    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);
    expect(harness().created, isEmpty);
    expect(harness().payloads, [_filesOnlyPayload(), _filesOnlyPayload()]);
    expect(await harness().fileBytes(0), _bytes);
    expect(await harness().fileBytes(1), _bytes);
  });

  test('AbortError cancels without a download', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'abort';

    final pending = shareOrDownloadJson(filename: _filename, bytes: _bytes);
    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);

    final result = await pending;

    expect(result, isA<ExportShareCancelled>());
    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);
    expect(harness().created, isEmpty);
    expect(harness().revoked, isEmpty);
  });

  test('NotAllowedError downloads once after the share rejection', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'notAllowed';

    final pending = shareOrDownloadJson(filename: _filename, bytes: _bytes);
    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);

    await _expectDownload(
      harness(),
      await pending,
      ExportShareDownloadReason.shareRejected,
      shareCalls: 1,
    );
  });

  test('a TypeError from share downloads once', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'typeError';

    final result = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    await _expectDownload(
      harness(),
      result,
      ExportShareDownloadReason.shareRejected,
      shareCalls: 1,
    );
  });

  test('a generic share failure downloads once', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'error';

    final result = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    await _expectDownload(
      harness(),
      result,
      ExportShareDownloadReason.shareRejected,
      shareCalls: 1,
    );
  });

  test('sharing the same bytes twice leaves both payloads unchanged', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'resolve';

    final first = await shareOrDownloadJson(filename: _filename, bytes: _bytes);
    final second = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    expect(first, isA<ExportShareHandedOff>());
    expect(second, isA<ExportShareHandedOff>());
    expect(harness().shareCalls, 2);
    expect(harness().clickCount, 0);
    expect(await harness().fileBytes(0), _bytes);
    expect(await harness().fileBytes(1), _bytes);
    expect(
      String.fromCharCodes(_bytes.where((byte) => byte < 128)),
      allOf(contains(_productId), contains(_orderNumber)),
    );
  });

  test(
    'downloading the same bytes twice leaves both files unchanged',
    () async {
      harness().canShareMode = 'false';

      final first = await shareOrDownloadJson(
        filename: _filename,
        bytes: _bytes,
      );
      final second = await shareOrDownloadJson(
        filename: _filename,
        bytes: _bytes,
      );

      expect(first, isA<ExportShareDownloadStarted>());
      expect(second, isA<ExportShareDownloadStarted>());
      expect(harness().clickCount, 2);
      expect(harness().shareCalls, 0);
      expect(harness().created, hasLength(2));
      expect(await harness().blobBytes(0), _bytes);
      expect(await harness().blobBytes(1), _bytes);
      expect(harness().clicks[0]['download'], _filename);
      expect(harness().clicks[1]['download'], _filename);
      await harness().settle();
      expect(harness().revoked, harness().created);
    },
  );

  test(
    'the object URL stays alive through the click and is revoked later',
    () async {
      harness().canShareMode = 'false';

      final result = await shareOrDownloadJson(
        filename: _filename,
        bytes: _bytes,
      );
      final url = harness().created.single;

      expect(result, isA<ExportShareDownloadStarted>());
      expect(harness().clicks.single['href'], url);
      expect(harness().clicks.single['connected'], isTrue);
      expect(harness().anchorConnected, isFalse);
      expect(harness().revoked, isEmpty);
      expect(await harness().blobBytes(0), _bytes);

      await harness().settle();

      expect(harness().revoked, [url]);
    },
  );

  test('a download click failure revokes the object URL immediately', () async {
    harness().canShareMode = 'false';
    harness().throwOnClick = true;

    final result = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    expect(result, isA<ExportShareFailed>());
    expect(harness().clickCount, 1);
    expect(harness().shareCalls, 0);
    expect(harness().created, hasLength(1));
    expect(harness().revoked, harness().created);
    expect(harness().anchorConnected, isFalse);
  });

  test('a failed object URL leaves no download and no URL', () async {
    harness().canShareMode = 'missing';
    harness().throwOnCreate = true;

    final result = await shareOrDownloadJson(
      filename: _filename,
      bytes: _bytes,
    );

    expect(result, isA<ExportShareFailed>());
    expect(harness().clickCount, 0);
    expect(harness().shareCalls, 0);
    expect(harness().created, isEmpty);
    expect(harness().revoked, isEmpty);
  });

  test('the coordinator calls the browser adapter before awaiting', () async {
    harness().canShareMode = 'true';
    harness().shareMode = 'resolve';
    final document = ExportDocument(
      filename: _filename,
      bytes: _bytes,
      dateCreate: '20261014150722',
    );

    final pending = const CumulativeExportShare().share(document);

    expect(harness().shareCalls, 1);
    expect(harness().clickCount, 0);
    expect(await pending, isA<ExportShareHandedOff>());
    expect(await harness().fileBytes(0), document.bytes);
    expect(harness().payloads.last['names'], [_filename]);
  });
}

Future<void> _expectDownload(
  _ShareHarness harness,
  ExportShareResult result,
  ExportShareDownloadReason reason, {
  required int shareCalls,
}) async {
  expect(result, isA<ExportShareDownloadStarted>());
  final started = result as ExportShareDownloadStarted;
  expect(started.reason, reason);
  expect(harness.shareCalls, shareCalls);
  expect(harness.clicks, hasLength(1));
  expect(harness.created, hasLength(1));
  expect(harness.blobTypes, [jsonExportMimeType]);

  final click = harness.clicks.single;
  expect(click['download'], _filename);
  expect(click['href'], harness.created.single);
  expect(click['connected'], isTrue);
  expect(click['inBody'], isTrue);
  expect(harness.anchorConnected, isFalse);
  expect(await harness.blobBytes(0), _bytes);
  expect(harness.revoked, isEmpty);

  await harness.settle();

  expect(harness.revoked, harness.created);
}

Map<String, Object?> _filesOnlyPayload() {
  return {
    'fileCount': 1,
    'text': '',
    'title': '',
    'url': '',
    'names': [_filename],
    'types': [jsonExportMimeType],
  };
}

/// Records share and download calls. TEST CODE ONLY.
class _ShareHarness {
  _ShareHarness._(this._state, this._restore);

  final JSObject _state;
  final JSFunction _restore;

  static _ShareHarness install() {
    final state = globalContext.callMethod<JSObject>(
      'eval'.toJS,
      _installScript.toJS,
    );
    return _ShareHarness._(state, state['restore'] as JSFunction);
  }

  void restore() => _restore.callAsFunction(_state);

  set canShareMode(String mode) {
    _state['canShareMode'] = mode.toJS;
    _state.callMethod<JSAny?>('arm'.toJS);
  }

  set shareMode(String mode) => _state['shareMode'] = mode.toJS;

  set throwOnClick(bool value) => _state['throwOnClick'] = value.toJS;

  set throwOnCreate(bool value) => _state['throwOnCreate'] = value.toJS;

  int get canShareCalls => _number('canShareCalls');

  int get shareCalls => _number('shareCalls');

  int get clickCount => clicks.length;

  List<Map<String, Object?>> get clicks => _maps('clicks');

  List<Map<String, Object?>> get payloads => _maps('payloads');

  List<String> get created => _strings('created');

  List<String> get revoked => _strings('revoked');

  List<String> get blobTypes => _strings('blobTypes');

  bool get anchorConnected =>
      _state.callMethod<JSBoolean>('anchorConnected'.toJS).toDart;

  Future<Uint8List> fileBytes(int index) => _read('readFile', index);

  Future<Uint8List> blobBytes(int index) => _read('readBlob', index);

  /// Waits out the production one-second revoke delay when a URL is still live.
  Future<void> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (revoked.length < created.length &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<Uint8List> _read(String method, int index) async {
    final array = await _state
        .callMethod<JSPromise<JSUint8Array>>(method.toJS, index.toJS)
        .toDart;
    return Uint8List.fromList(array.toDart);
  }

  int _number(String name) => (_state[name] as JSNumber).toDartInt;

  List<String> _strings(String name) => [
    for (final item in _decoded(name)) item as String,
  ];

  List<Map<String, Object?>> _maps(String name) => [
    for (final item in _decoded(name)) (item as Map).cast<String, Object?>(),
  ];

  List<Object?> _decoded(String name) {
    return (jsonDecode(_json('globalThis.__jsonShare.$name')) as List)
        .cast<Object?>();
  }

  String _json(String expression) => globalContext
      .callMethod<JSString>('eval'.toJS, 'JSON.stringify($expression)'.toJS)
      .toDart;
}

const _installScript = r'''
(function () {
  var proto = Navigator.prototype;
  var saved = [];
  function patch(obj, name, value) {
    saved.push({
      obj: obj,
      name: name,
      desc: Object.getOwnPropertyDescriptor(obj, name) || null
    });
    Object.defineProperty(obj, name, {
      configurable: true,
      writable: true,
      value: value
    });
  }
  function restoreOne(item) {
    if (item.desc) Object.defineProperty(item.obj, item.name, item.desc);
    else delete item.obj[item.name];
  }

  var prevCreate = URL.createObjectURL;
  var prevRevoke = URL.revokeObjectURL;
  var anchorProto = HTMLAnchorElement.prototype;
  var prevClick = anchorProto.click;

  var state = globalThis.__jsonShare = {
    canShareMode: 'false',
    shareMode: 'resolve',
    throwOnClick: false,
    throwOnCreate: false,
    canShareCalls: 0,
    shareCalls: 0,
    clicks: [],
    payloads: [],
    created: [],
    revoked: [],
    blobTypes: [],
    fileObjects: [],
    blobs: [],
    anchors: []
  };

  function capture(data) {
    var files = data && data.files ? Array.from(data.files) : [];
    state.payloads.push({
      fileCount: files.length,
      text: data && data.text != null ? String(data.text) : '',
      title: data && data.title != null ? String(data.title) : '',
      url: data && data.url != null ? String(data.url) : '',
      names: files.map(function (file) { return file.name; }),
      types: files.map(function (file) { return file.type; })
    });
    files.forEach(function (file) { state.fileObjects.push(file); });
  }

  function canShare(data) {
    state.canShareCalls++;
    capture(data);
    if (state.canShareMode === 'throw') throw new TypeError('canShare failed');
    return state.canShareMode === 'true';
  }

  function share(data) {
    state.shareCalls++;
    capture(data);
    if (state.shareMode === 'resolve') return Promise.resolve();
    if (state.shareMode === 'abort') {
      return Promise.reject(new DOMException('Share canceled', 'AbortError'));
    }
    if (state.shareMode === 'notAllowed') {
      return Promise.reject(
        new DOMException('Permission denied', 'NotAllowedError'));
    }
    if (state.shareMode === 'typeError') {
      return Promise.reject(new TypeError('Invalid share'));
    }
    return Promise.reject(new Error('share failed'));
  }

  function bytesOf(blob) {
    return blob.arrayBuffer().then(function (buffer) {
      return new Uint8Array(buffer);
    });
  }

  state.arm = function () {
    if (state.canShareMode === 'missing') {
      Object.defineProperty(proto, 'canShare', {
        configurable: true,
        writable: true,
        value: undefined
      });
      return;
    }
    Object.defineProperty(proto, 'canShare', {
      configurable: true,
      writable: true,
      value: canShare
    });
  };

  state.readFile = function (index) {
    return bytesOf(state.fileObjects[index]);
  };
  state.readBlob = function (index) {
    return bytesOf(state.blobs[index]);
  };
  state.anchorConnected = function () {
    var anchor = state.anchors[state.anchors.length - 1];
    return !!(anchor && anchor.isConnected);
  };
  state.restore = function () {
    URL.createObjectURL = prevCreate;
    URL.revokeObjectURL = prevRevoke;
    anchorProto.click = prevClick;
    for (var i = saved.length - 1; i >= 0; i--) restoreOne(saved[i]);
    saved = [];
    delete globalThis.__jsonShare;
  };

  patch(proto, 'canShare', canShare);
  patch(proto, 'share', share);

  URL.createObjectURL = function (blob) {
    if (state.throwOnCreate && blob && blob.type === 'application/json') {
      throw new Error('createObjectURL failed');
    }
    var url = prevCreate.call(URL, blob);
    if (blob && blob.type === 'application/json') {
      state.created.push(url);
      state.blobs.push(blob);
      state.blobTypes.push(blob.type);
    }
    return url;
  };
  URL.revokeObjectURL = function (url) {
    if (state.created.indexOf(url) !== -1 &&
        state.revoked.indexOf(url) === -1) {
      state.revoked.push(url);
    }
    return prevRevoke.call(URL, url);
  };
  anchorProto.click = function () {
    if (!this.download) return prevClick.apply(this, arguments);
    state.clicks.push({
      download: String(this.download),
      href: String(this.href),
      connected: this.isConnected,
      inBody: this.parentNode === document.body
    });
    state.anchors.push(this);
    if (state.throwOnClick) throw new Error('click blocked');
  };
  return state;
})()
''';
