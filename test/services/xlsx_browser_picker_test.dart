@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/models/imported_file.dart';
import 'package:retail_offline/services/file/local_file_service.dart';
import 'package:retail_offline/services/file/xlsx_browser_picker.dart';

/// A stand-in for the OS file chooser. TEST CODE ONLY: it replaces
/// `HTMLInputElement.prototype.click` (so no dialog opens and the test can
/// play the browser's events by hand) and watches add/removeEventListener on
/// file inputs. The production picker never depends on any of this.
class _FakeChooser {
  _FakeChooser._(this._fc, this._restore);

  final JSObject _fc;
  final JSFunction _restore;

  static _FakeChooser install() {
    final fc = globalContext.callMethod<JSObject>(
      'eval'.toJS,
      r'''
(function () {
  var proto = HTMLInputElement.prototype;
  var had = Object.prototype.hasOwnProperty.call(proto, 'click');
  var prevClick = proto.click;
  var et = EventTarget.prototype;
  var prevAdd = et.addEventListener;
  var prevRemove = et.removeEventListener;
  var prevArrayBuffer = File.prototype.arrayBuffer;
  var fc = globalThis.__fc = {
    inputs: [], snaps: [], listeners: [], throwOnClick: false,
    pendingAtClick: null
  };
  function isFileInput(t) {
    return t instanceof HTMLInputElement && t.type === 'file';
  }
  et.addEventListener = function (type, fn) {
    if (isFileInput(this)) fc.listeners.push({ t: this, type: type, fn: fn });
    return prevAdd.apply(this, arguments);
  };
  et.removeEventListener = function (type, fn) {
    var self = this;
    if (isFileInput(self)) {
      fc.listeners = fc.listeners.filter(function (l) {
        return !(l.t === self && l.type === type && l.fn === fn);
      });
    }
    return prevRemove.apply(this, arguments);
  };
  proto.click = function () {
    var input = this;
    if (input.type !== 'file') return prevClick.apply(this, arguments);
    fc.inputs.push(input);
    fc.snaps.push({
      accept: input.accept,
      multiple: input.multiple,
      connected: input.isConnected,
      hasParent: input.parentNode != null,
      args: arguments.length,
      listenersAtClick: fc.listeners.filter(function (l) {
        return l.t === input;
      }).length,
      pendingAtClick: fc.pendingAtClick ? fc.pendingAtClick(input) : null
    });
    if (fc.throwOnClick) throw new Error('click blocked');
  };
  fc.choose = function (input, name, bytes) {
    var dt = new DataTransfer();
    dt.items.add(new File([new Uint8Array(bytes)], name));
    input.files = dt.files;
    input.dispatchEvent(new Event('change'));
  };
  fc.fire = function (input, type) { input.dispatchEvent(new Event(type)); };
  fc.focusWindow = function () { window.dispatchEvent(new Event('focus')); };
  fc.listenerCount = function (input) {
    return fc.listeners.filter(function (l) { return l.t === input; }).length;
  };
  fc.failNextRead = function () {
    File.prototype.arrayBuffer = function () {
      File.prototype.arrayBuffer = prevArrayBuffer;
      return Promise.reject(new Error('read failed'));
    };
  };
  fc.restore = function () {
    File.prototype.arrayBuffer = prevArrayBuffer;
    et.addEventListener = prevAdd;
    et.removeEventListener = prevRemove;
    if (had) { proto.click = prevClick; } else { delete proto.click; }
    delete globalThis.__fc;
  };
  return fc;
})()
'''
          .toJS,
    );
    fc['pendingAtClick'] = ((JSObject input) => isPendingInput(input)).toJS;
    return _FakeChooser._(fc, fc['restore'] as JSFunction);
  }

  /// Puts the browser back. A pick a test left pending is first ended
  /// through the production cancel path, so no state leaks into the next test.
  void restore() {
    if (pendingPickCount > 0) cancel(lastInput);
    _restore.callAsFunction(_fc);
  }

  set throwOnClick(bool value) => _fc['throwOnClick'] = value.toJS;

  JSObject get lastInput {
    final inputs = _fc['inputs'] as JSArray<JSObject>;
    return inputs.toDart.last;
  }

  List<Map<String, Object?>> get clicks =>
      (jsonDecode(_json('globalThis.__fc.snaps')) as List)
          .cast<Map<String, Object?>>();

  int listenerCount(JSObject input) =>
      (_fc.callMethod<JSNumber>('listenerCount'.toJS, input)).toDartInt;

  void choose(JSObject input, String name, List<int> bytes) =>
      _fc.callMethod<JSAny?>(
        'choose'.toJS,
        input,
        name.toJS,
        [for (final b in bytes) b.toJS].toJS,
      );

  /// A `change` event whose FileList is empty.
  void chooseNothing(JSObject input) => fire(input, 'change');

  void cancel(JSObject input) => fire(input, 'cancel');

  void fire(JSObject input, String type) =>
      _fc.callMethod<JSAny?>('fire'.toJS, input, type.toJS);

  void focusWindow() => _fc.callMethod<JSAny?>('focusWindow'.toJS);

  void failNextRead() => _fc.callMethod<JSAny?>('failNextRead'.toJS);
}

String _json(String expression) => globalContext
    .callMethod<JSString>('eval'.toJS, 'JSON.stringify($expression)'.toJS)
    .toDart;

int _bodyChildren() => int.parse(
  globalContext
      .callMethod<JSString>(
        'eval'.toJS,
        'String(document.body.childElementCount)'.toJS,
      )
      .toDart,
);

/// Tracks a Future without awaiting it.
class _Tracker<T> {
  _Tracker(Future<T> future) {
    future.then<void>(
      (v) {
        done = true;
        value = v;
      },
      onError: (Object e) {
        done = true;
        error = e;
      },
    );
  }

  bool done = false;
  T? value;
  Object? error;
}

Future<void> _settle([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _FakeChooser chooser;
  setUp(() => chooser = _FakeChooser.install());
  tearDown(() => chooser.restore());

  final bytes = <int>[0x50, 0x4B, 3, 4, 0, 255, 128, 7];

  test('returns the exact file name and bytes', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    chooser.choose(chooser.lastInput, 'Замовлення listOrders.xlsx', bytes);
    await _settle();

    expect(pick.error, isNull);
    expect(pick.value, isNotNull);
    expect(pick.value!.name, 'Замовлення listOrders.xlsx');
    expect(pick.value!.bytes, isA<Uint8List>());
    expect(pick.value!.bytes, orderedEquals(bytes));
    expect(pendingPickCount, 0);
  });

  test('the input is an XLSX-only single-file input, clicked at once', () {
    final pick = pickXlsxFromBrowser();
    // No await between the call and click(): the click already happened.
    expect(chooser.clicks, hasLength(1));
    final click = chooser.clicks.single;
    expect(click['accept'], '.xlsx');
    expect(click['multiple'], isFalse);
    expect(click['args'], 0);
    unawaited(pick);
  });

  test('the input stays detached; the DOM is not touched', () async {
    final bodyBefore = _bodyChildren();
    final pick = _Tracker(pickXlsxFromBrowser());
    final click = chooser.clicks.single;
    expect(click['connected'], isFalse);
    expect(click['hasParent'], isFalse);
    expect(_bodyChildren(), bodyBefore);

    chooser.choose(chooser.lastInput, 'a.xlsx', bytes);
    await _settle();
    expect(pick.done, isTrue);
    expect(_bodyChildren(), bodyBefore);
  });

  test('is retained and listening BEFORE the chooser opens', () {
    final pick = pickXlsxFromBrowser();
    final click = chooser.clicks.single;
    expect(click['pendingAtClick'], isTrue); // retained at click time
    expect(click['listenersAtClick'], 2); // change + cancel
    expect(pendingPickCount, 1);
    expect(isPendingInput(chooser.lastInput), isTrue);
    unawaited(pick);
  });

  test('the "input" event neither completes nor releases the pick', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    chooser.fire(chooser.lastInput, 'input');
    await _settle();

    expect(pick.done, isFalse);
    expect(pendingPickCount, 1);
    expect(isPendingInput(chooser.lastInput), isTrue);
  });

  test(
    'change with a file completes with it and releases everything',
    () async {
      final pick = _Tracker(pickXlsxFromBrowser());
      final input = chooser.lastInput;
      chooser.choose(input, 'a.xlsx', bytes);

      // Released synchronously by the terminal event, before the read finishes.
      expect(pendingPickCount, 0);
      expect(isPendingInput(input), isFalse);
      expect(chooser.listenerCount(input), 0);

      await _settle();
      expect(pick.value!.name, 'a.xlsx');
    },
  );

  test('change with no file completes with null and releases', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    final input = chooser.lastInput;
    chooser.chooseNothing(input);
    await _settle();

    expect(pick.done, isTrue);
    expect(pick.value, isNull);
    expect(pick.error, isNull);
    expect(pendingPickCount, 0);
    expect(chooser.listenerCount(input), 0);
  });

  test('native cancel completes with null and releases', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    final input = chooser.lastInput;
    chooser.cancel(input);
    await _settle();

    expect(pick.done, isTrue);
    expect(pick.value, isNull);
    expect(pendingPickCount, 0);
    expect(isPendingInput(input), isFalse);
    expect(chooser.listenerCount(input), 0);
  });

  test('a duplicate or late terminal event is ignored', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    final input = chooser.lastInput;
    chooser.cancel(input);
    chooser.cancel(input);
    chooser.choose(input, 'late.xlsx', bytes);
    await _settle();

    expect(pick.value, isNull); // the first terminal event won
    expect(pendingPickCount, 0);
  });

  group('no focus heuristic and no timeout', () {
    test('window focus does not cancel the pick', () async {
      final pick = _Tracker(pickXlsxFromBrowser());
      chooser.focusWindow();
      await _settle(700); // longer than the old 500 ms heuristic

      expect(pick.done, isFalse);
      expect(pendingPickCount, 1);
    });

    test('focus, then change 800 ms later (iOS Safari timing): file', () async {
      final pick = _Tracker(pickXlsxFromBrowser());
      final input = chooser.lastInput;
      chooser.focusWindow();
      await _settle(800);
      expect(pick.done, isFalse);

      chooser.choose(input, 'late.xlsx', bytes);
      await _settle();
      expect(pick.value!.name, 'late.xlsx');
      expect(pick.value!.bytes, orderedEquals(bytes));
    });

    test('an unanswered chooser stays pending and retained', () async {
      final pick = _Tracker(pickXlsxFromBrowser());
      await _settle(1500);

      expect(pick.done, isFalse);
      expect(pendingPickCount, 1);
      expect(isPendingInput(chooser.lastInput), isTrue);
    });
  });

  test('repeated sequential selections work', () async {
    for (final name in ['orders.xlsx', 'inventory.xlsx', 'again.xlsx']) {
      final pick = _Tracker(pickXlsxFromBrowser());
      chooser.choose(chooser.lastInput, name, bytes);
      await _settle();
      expect(pick.value!.name, name);
      expect(pendingPickCount, 0);
    }
    // ...and a cancel followed by a selection.
    final cancelled = _Tracker(pickXlsxFromBrowser());
    chooser.cancel(chooser.lastInput);
    final chosen = _Tracker(pickXlsxFromBrowser());
    chooser.choose(chooser.lastInput, 'after-cancel.xlsx', bytes);
    await _settle();
    expect(cancelled.value, isNull);
    expect(chosen.value!.name, 'after-cancel.xlsx');
  });

  test('a synchronous click() failure cleans up and propagates', () async {
    chooser.throwOnClick = true;
    final pick = _Tracker(pickXlsxFromBrowser());
    final input = chooser.lastInput;
    await _settle();

    expect(pick.done, isTrue);
    expect(pick.error, isNotNull);
    expect(pendingPickCount, 0);
    expect(isPendingInput(input), isFalse);
    expect(chooser.listenerCount(input), 0);

    // The picker is usable again afterwards.
    chooser.throwOnClick = false;
    final next = _Tracker(pickXlsxFromBrowser());
    chooser.choose(chooser.lastInput, 'ok.xlsx', bytes);
    await _settle();
    expect(next.value!.name, 'ok.xlsx');
  });

  test('a read failure completes with an error and leaves no state', () async {
    final pick = _Tracker(pickXlsxFromBrowser());
    final input = chooser.lastInput;
    chooser.failNextRead();
    chooser.choose(input, 'a.xlsx', bytes);
    await _settle();

    expect(pick.done, isTrue);
    expect(pick.error, isNotNull);
    expect(pick.value, isNull);
    expect(pendingPickCount, 0);
    expect(chooser.listenerCount(input), 0);
  });

  group('concurrency: a second pick is rejected, the first is untouched', () {
    test(
      'pick #2 fails with StateError; pick #1 finishes; pick #3 works',
      () async {
        // 1. Pick #1 starts and stays retained / pending.
        final first = _Tracker(pickXlsxFromBrowser());
        final firstInput = chooser.lastInput;
        expect(chooser.clicks, hasLength(1));
        expect(pendingPickCount, 1);
        expect(isPendingInput(firstInput), isTrue);
        expect(chooser.listenerCount(firstInput), 2);

        // 2. Pick #2 creates and clicks nothing.
        final second = _Tracker(pickXlsxFromBrowser());
        expect(chooser.clicks, hasLength(1));
        expect(chooser.lastInput, same(firstInput));

        // 3. It fails with the expected state error.
        await _settle();
        expect(second.done, isTrue);
        expect(second.value, isNull);
        expect(second.error, isA<StateError>());

        // 4. Pick #1 is retained, listening and unaffected (not completed,
        //    in particular not as a "cancel").
        expect(first.done, isFalse);
        expect(pendingPickCount, 1);
        expect(isPendingInput(firstInput), isTrue);
        expect(chooser.listenerCount(firstInput), 2);

        // 5. Its own change event still returns the selected file normally.
        chooser.choose(firstInput, 'first.xlsx', bytes);
        await _settle();
        expect(first.error, isNull);
        expect(first.value!.name, 'first.xlsx');
        expect(first.value!.bytes, orderedEquals(bytes));
        expect(pendingPickCount, 0);
        expect(chooser.listenerCount(firstInput), 0);

        // 6. Afterwards a new pick #3 works normally.
        final third = _Tracker(pickXlsxFromBrowser());
        expect(chooser.clicks, hasLength(2));
        expect(isPendingInput(chooser.lastInput), isTrue);
        chooser.choose(chooser.lastInput, 'third.xlsx', bytes);
        await _settle();
        expect(third.error, isNull);
        expect(third.value!.name, 'third.xlsx');
        expect(pendingPickCount, 0);
      },
    );

    test(
      'pick #1 can still be cancelled normally after a rejected pick #2',
      () async {
        final first = _Tracker(pickXlsxFromBrowser());
        final firstInput = chooser.lastInput;
        final second = _Tracker(pickXlsxFromBrowser());
        await _settle();
        expect(second.error, isA<StateError>());

        chooser.cancel(firstInput);
        await _settle();
        expect(first.done, isTrue);
        expect(first.value, isNull);
        expect(first.error, isNull);
        expect(pendingPickCount, 0);
      },
    );
  });

  group('LocalFileService with its default picker', () {
    test('returns a local ImportedFile (desktop Chrome path)', () async {
      final result = Completer<ImportedFile?>();
      unawaited(const LocalFileService().pickXlsx().then(result.complete));
      chooser.choose(chooser.lastInput, 'listOrders.xlsx', bytes);

      final file = await result.future;
      expect(file!.name, 'listOrders.xlsx');
      expect(file.bytes, orderedEquals(bytes));
      expect(file.source, FileSource.local);
    });

    test('cancel is null', () async {
      final result = Completer<ImportedFile?>();
      unawaited(const LocalFileService().pickXlsx().then(result.complete));
      chooser.cancel(chooser.lastInput);
      expect(await result.future, isNull);
    });

    test('validation still rejects a wrong extension', () async {
      final result = const LocalFileService().pickXlsx();
      final expectation = expectLater(result, throwsA(isA<ImportException>()));
      chooser.choose(chooser.lastInput, 'orders.csv', bytes);
      await expectation;
    });

    test('a picker failure becomes the friendly ImportException', () async {
      chooser.throwOnClick = true;
      await expectLater(
        const LocalFileService().pickXlsx(),
        throwsA(
          isA<ImportException>().having(
            (e) => e.technical,
            'technical',
            'Picker failure',
          ),
        ),
      );
      expect(pendingPickCount, 0);
    });
  });
}
