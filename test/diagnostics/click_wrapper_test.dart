@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/diagnostics/click_wrapper.dart';
import 'package:retail_offline/services/file/web_picker_options.dart';

String _eval(String script) =>
    globalContext.callMethod<JSString>('eval'.toJS, script.toJS).toDart;

/// Replaces `HTMLInputElement.prototype.click` with a stand-in for the OS
/// dialog (same idea as in `web_picker_options_test.dart`) and records, in
/// `globalThis.__abLog`, every `addEventListener` call on a file input plus
/// the click itself, in order. On click it records what the input looks like
/// and answers with one file after 50 ms.
///
/// The recorder is the test's own; the code under test never logs. Returns
/// the function that restores the browser.
JSFunction _fakeChooser({bool answer = true}) {
  final install = globalContext.callMethod<JSFunction>(
    'eval'.toJS,
    r'''
(function (answer) {
  var proto = HTMLInputElement.prototype;
  var had = Object.prototype.hasOwnProperty.call(proto, 'click');
  var prev = proto.click;
  var addProto = EventTarget.prototype;
  var prevAdd = addProto.addEventListener;
  globalThis.__abLog = [];
  globalThis.__abClicks = [];
  globalThis.__abThis = null;
  addProto.addEventListener = function (type) {
    if (this instanceof HTMLInputElement && this.type === 'file') {
      globalThis.__abLog.push('add:' + type + ':' + arguments.length);
    }
    return prevAdd.apply(this, arguments);
  };
  proto.click = function () {
    var input = this;
    globalThis.__abLog.push('click');
    globalThis.__abThis = input;
    globalThis.__abRetainedAtClick = globalThis.__abIsRetained
        ? globalThis.__abIsRetained(input) : null;
    globalThis.__abClicks.push({
      type: input.type,
      accept: input.accept,
      multiple: input.multiple,
      connected: input.isConnected,
      hasParent: input.parentNode != null,
      args: arguments.length
    });
    if (!answer) return;
    setTimeout(function () {
      var dt = new DataTransfer();
      dt.items.add(new File([new Uint8Array([80, 75, 3, 4])], 'a.xlsx'));
      input.files = dt.files;
      input.dispatchEvent(new Event('change'));
    }, 50);
  };
  return function () {
    addProto.addEventListener = prevAdd;
    if (had) { proto.click = prev; } else { delete proto.click; }
  };
})
'''
        .toJS,
  );
  return install.callAsFunction(null, answer.toJS) as JSFunction;
}

/// Exposes `wrapper.isRetained` to the fake chooser, so the click can record
/// whether its receiver was already retained at that moment.
void _recordRetainedAtClick(ClickWrapper wrapper) {
  globalContext['__abIsRetained'] = ((JSObject input) => wrapper.isRetained(
    input,
  )).toJS;
}

bool _clickIsOwnProperty() =>
    _eval(
      "String(Object.prototype.hasOwnProperty.call("
      "HTMLInputElement.prototype, 'click'))",
    ) ==
    'true';

JSAny? _clickFunction() => globalContext.callMethod<JSAny?>(
  'eval'.toJS,
  'HTMLInputElement.prototype.click'.toJS,
);

typedef _Pick = ({
  String name,
  List<int> bytes,
  String log,
  String clicks,
  bool domTouched,
  int retainedAfter,
});

Future<_Pick> _pickOnce(ClickWrapper? wrapper) async {
  final restore = _fakeChooser();
  wrapper?.install();
  final bodyChildren = _eval('String(document.body.childElementCount)');
  try {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      webOptions: pickerWebOptions(),
    );
    return (
      name: file!.name,
      bytes: await file.readAsBytes(),
      log: _eval('JSON.stringify(globalThis.__abLog)'),
      clicks: _eval('JSON.stringify(globalThis.__abClicks)'),
      domTouched:
          _eval('String(document.body.childElementCount)') != bodyChildren,
      retainedAfter: wrapper?.retainedCount ?? 0,
    );
  } finally {
    wrapper?.uninstall();
    restore.callAsFunction();
  }
}

void main() {
  setUpAll(() => FilePickerWeb.registerWith(webPluginRegistrar));

  final modes = <String, ClickWrapper Function()>{
    'click-wrapper': ClickWrapper.new,
    'click-wrapper+listeners': () => ClickWrapper(withListeners: true),
    'click-wrapper+listeners+retain': () =>
        ClickWrapper(withListeners: true, retainInputs: true),
  };

  for (final MapEntry(key: name, value: create) in modes.entries) {
    test('$name: install puts a wrapper in place and uninstall restores', () {
      final before = _clickFunction();
      final hadOwn = _clickIsOwnProperty();
      final wrapper = create()..install();

      expect(wrapper.isInstalled, isTrue);
      expect(wrapper.problem, isNull);
      expect(_clickFunction(), isNot(same(before)));
      expect(_clickIsOwnProperty(), isTrue);

      wrapper.uninstall();

      expect(wrapper.isInstalled, isFalse);
      expect(_clickIsOwnProperty(), hadOwn);
      expect(_clickFunction(), same(before));
    });
  }

  test('click-wrapper: the picker behaves exactly as without it', () async {
    final without = await _pickOnce(null);
    final wrapped = await _pickOnce(ClickWrapper());

    expect(wrapped.name, without.name);
    expect(wrapped.bytes, [80, 75, 3, 4]);
    expect(wrapped.log, without.log); // no extra listeners
    expect(wrapped.clicks, without.clicks);
    expect(wrapped.domTouched, isFalse);
  });

  group('click-wrapper+listeners', () {
    test(
      'registers input, change, cancel before the one original click',
      () async {
        final without = await _pickOnce(null);
        final wrapped = await _pickOnce(ClickWrapper(withListeners: true));

        // file_picker_web's own two listeners come first, in both runs.
        expect(without.log, '["add:change:2","add:cancel:2","click"]');
        // The wrapper adds exactly input, change, cancel (two arguments each:
        // no options object), immediately before the original click, which is
        // invoked exactly once.
        expect(
          wrapped.log,
          '["add:change:2","add:cancel:2",'
          '"add:input:2","add:change:2","add:cancel:2","click"]',
        );
      },
    );

    test('same file, same input state, no DOM attachment', () async {
      final without = await _pickOnce(null);
      final wrapped = await _pickOnce(ClickWrapper(withListeners: true));

      expect(wrapped.name, without.name);
      expect(wrapped.bytes, [80, 75, 3, 4]); // selection still works
      // Same type/accept/multiple, no arguments, still detached.
      expect(wrapped.clicks, without.clicks);
      expect(wrapped.clicks, contains('"connected":false,"hasParent":false'));
      expect(wrapped.domTouched, isFalse);
    });

    test('keeps receiver and arguments, and the listeners are inert', () {
      final restore = _fakeChooser();
      final wrapper = ClickWrapper(withListeners: true)..install();
      try {
        final result = _eval(r'''
(function () {
  var i = document.createElement('input');
  i.type = 'file';
  var later = 0;
  i.click('x', 2);
  i.addEventListener('change', function () { later++; });
  var e = new Event('change', { cancelable: true, bubbles: true });
  i.dispatchEvent(new Event('input'));
  i.dispatchEvent(e);
  i.dispatchEvent(new Event('cancel'));
  return JSON.stringify({
    sameReceiver: globalThis.__abThis === i,
    clickCount: globalThis.__abClicks.length,
    firstArgs: globalThis.__abClicks[0].args,
    defaultPrevented: e.defaultPrevented,
    laterListenerRan: later
  });
})()
''');
        expect(
          result,
          '{"sameReceiver":true,"clickCount":1,"firstArgs":2,'
          '"defaultPrevented":false,"laterListenerRan":1}',
        );
      } finally {
        wrapper.uninstall();
        restore.callAsFunction();
      }
    });
  });

  group('click-wrapper+listeners+retain', () {
    ClickWrapper create() =>
        ClickWrapper(withListeners: true, retainInputs: true);

    test(
      'registers the same listeners as A/B 2 and picks the same file',
      () async {
        final listeners = await _pickOnce(ClickWrapper(withListeners: true));
        final retain = await _pickOnce(create());

        // Retention adds no addEventListener call: same order as A/B 2, and
        // exactly one original click.
        expect(retain.log, listeners.log);
        expect(
          retain.log,
          '["add:change:2","add:cancel:2",'
          '"add:input:2","add:change:2","add:cancel:2","click"]',
        );
        // Desktop Chrome selection still works and returns the same bytes.
        expect(retain.name, listeners.name);
        expect(retain.bytes, [80, 75, 3, 4]);
        // Same input state, still detached, no DOM mutation.
        expect(retain.clicks, listeners.clicks);
        expect(retain.clicks, contains('"connected":false,"hasParent":false'));
        expect(retain.domTouched, isFalse);
        // The real change event released the input.
        expect(retain.retainedAfter, 0);
      },
    );

    test('retains before the click; only change/cancel release it', () async {
      final restore = _fakeChooser(answer: false);
      final wrapper = create()..install();
      _recordRetainedAtClick(wrapper);
      try {
        // Count every timer-ish call made while clicking.
        final result = _eval(r'''
(function () {
  var timerCalls = 0;
  var orig = {};
  ['setTimeout', 'setInterval', 'requestAnimationFrame', 'queueMicrotask']
    .forEach(function (n) {
      orig[n] = globalThis[n];
      globalThis[n] = function () { timerCalls++; return orig[n].apply(this, arguments); };
    });
  var i = document.createElement('input');
  i.type = 'file';
  var connectedBefore = i.isConnected;
  i.click('x', 2);
  Object.keys(orig).forEach(function (n) { globalThis[n] = orig[n]; });
  globalThis.__abInput = i;
  return JSON.stringify({
    connectedBefore: connectedBefore,
    connectedAfter: i.isConnected,
    clickCount: globalThis.__abClicks.length,
    sameReceiver: globalThis.__abThis === i,
    firstArgs: globalThis.__abClicks[0].args,
    retainedAtClick: globalThis.__abRetainedAtClick,
    timerCalls: timerCalls
  });
})()
''');
        expect(
          result,
          '{"connectedBefore":false,"connectedAfter":false,"clickCount":1,'
          '"sameReceiver":true,"firstArgs":2,"retainedAtClick":true,'
          '"timerCalls":0}',
        );
        final input =
            globalContext['__abInput'] as JSObject; // ignore: unnecessary_cast
        expect(wrapper.isRetained(input), isTrue);
        expect(wrapper.retainedCount, 1);

        // `input` is not terminal.
        input.callMethod('dispatchEvent'.toJS, _event('input'));
        expect(wrapper.isRetained(input), isTrue);

        // Time alone does not release it either (no timeout of any kind).
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(wrapper.isRetained(input), isTrue);

        // `change` is terminal.
        input.callMethod('dispatchEvent'.toJS, _event('change'));
        expect(wrapper.isRetained(input), isFalse);
        expect(wrapper.retainedCount, 0);
      } finally {
        wrapper.uninstall();
        restore.callAsFunction();
      }
    });

    test('cancel releases the input', () {
      final restore = _fakeChooser(answer: false);
      final wrapper = create()..install();
      try {
        final input = globalContext.callMethod<JSObject>(
          'eval'.toJS,
          "(function(){var i=document.createElement('input');"
                  "i.type='file';i.click();return i;})()"
              .toJS,
        );
        expect(wrapper.isRetained(input), isTrue);
        input.callMethod('dispatchEvent'.toJS, _event('cancel'));
        expect(wrapper.isRetained(input), isFalse);
      } finally {
        wrapper.uninstall();
        restore.callAsFunction();
      }
    });

    test('a non-file input is neither retained nor given listeners', () {
      final restore = _fakeChooser(answer: false);
      final wrapper = create()..install();
      try {
        final text = globalContext.callMethod<JSObject>(
          'eval'.toJS,
          "(function(){var i=document.createElement('input');"
                  "i.type='text';i.click();return i;})()"
              .toJS,
        );
        expect(wrapper.isRetained(text), isFalse);
        expect(wrapper.retainedCount, 0);
      } finally {
        wrapper.uninstall();
        restore.callAsFunction();
      }
    });

    // Test isolation: the Set lives inside one install() call, so a fresh
    // wrapper never sees inputs retained by an earlier one, even if that one
    // never got a change/cancel. Nothing outside the tests clears anything.
    test('each install starts with nothing retained (isolation)', () {
      final restore = _fakeChooser(answer: false);
      final first = create()..install();
      globalContext.callMethod<JSAny?>(
        'eval'.toJS,
        "(function(){var i=document.createElement('input');"
                "i.type='file';i.click();})()"
            .toJS,
      );
      expect(first.retainedCount, 1); // deliberately left pending
      first.uninstall();

      final second = create()..install();
      try {
        expect(second.retainedCount, 0);
      } finally {
        second.uninstall();
        restore.callAsFunction();
      }
    });
  });
}

JSObject _event(String type) =>
    globalContext.callMethod<JSObject>('eval'.toJS, "new Event('$type')".toJS);
