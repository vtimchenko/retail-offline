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
JSFunction _fakeChooser() {
  final install = globalContext.callMethod<JSFunction>(
    'eval'.toJS,
    r'''
(function () {
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
    globalThis.__abClicks.push({
      type: input.type,
      accept: input.accept,
      multiple: input.multiple,
      connected: input.isConnected,
      hasParent: input.parentNode != null,
      args: arguments.length
    });
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
  return install.callAsFunction() as JSFunction;
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
    );
  } finally {
    wrapper?.uninstall();
    restore.callAsFunction();
  }
}

void main() {
  setUpAll(() => FilePickerWeb.registerWith(webPluginRegistrar));

  for (final withListeners in [false, true]) {
    final name = withListeners ? 'click-wrapper+listeners' : 'click-wrapper';

    test('$name: install puts a wrapper in place and uninstall restores', () {
      final before = _clickFunction();
      final hadOwn = _clickIsOwnProperty();
      final wrapper = ClickWrapper(withListeners: withListeners)..install();

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
}
