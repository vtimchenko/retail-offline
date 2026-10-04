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

/// Replaces `HTMLInputElement.prototype.click` with a stand-in for the OS
/// dialog (same idea as in `web_picker_options_test.dart`): it records what
/// the input looks like when it is clicked, then answers with one file after
/// 50 ms. Returns the function that restores the browser.
JSFunction _fakeChooser() {
  final install = globalContext.callMethod<JSFunction>(
    'eval'.toJS,
    r'''
(function () {
  var proto = HTMLInputElement.prototype;
  var had = Object.prototype.hasOwnProperty.call(proto, 'click');
  var prev = proto.click;
  globalThis.__abClicks = [];
  proto.click = function () {
    var input = this;
    globalThis.__abClicks.push({
      type: input.type,
      accept: input.accept,
      multiple: input.multiple,
      connected: input.isConnected,
      args: arguments.length
    });
    setTimeout(function () {
      var dt = new DataTransfer();
      dt.items.add(new File([new Uint8Array([80, 75, 3, 4])], 'a.xlsx'));
      input.files = dt.files;
      input.dispatchEvent(new Event('change'));
    }, 50);
  };
  return function () { if (had) { proto.click = prev; } else { delete proto.click; } };
})
'''
        .toJS,
  );
  return install.callAsFunction() as JSFunction;
}

String _clicks() => globalContext
    .callMethod<JSString>(
      'eval'.toJS,
      'JSON.stringify(globalThis.__abClicks)'.toJS,
    )
    .toDart;

bool _clickIsOwnProperty() => globalContext
    .callMethod<JSBoolean>(
      'eval'.toJS,
      "Object.prototype.hasOwnProperty.call(HTMLInputElement.prototype, 'click')"
          .toJS,
    )
    .toDart;

JSAny? _clickFunction() => globalContext.callMethod<JSAny?>(
  'eval'.toJS,
  'HTMLInputElement.prototype.click'.toJS,
);

Future<({String name, List<int> bytes, String clicks})> _pickOnce({
  required bool withWrapper,
}) async {
  final restore = _fakeChooser();
  final wrapper = ClickWrapper();
  if (withWrapper) wrapper.install();
  try {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      webOptions: pickerWebOptions(),
    );
    return (
      name: file!.name,
      bytes: await file.readAsBytes(),
      clicks: _clicks(),
    );
  } finally {
    wrapper.uninstall();
    restore.callAsFunction();
  }
}

void main() {
  setUpAll(() => FilePickerWeb.registerWith(webPluginRegistrar));

  test('install puts a pass-through in place and uninstall restores it', () {
    final before = _clickFunction();
    final hadOwn = _clickIsOwnProperty();
    final wrapper = ClickWrapper()..install();

    expect(wrapper.isInstalled, isTrue);
    expect(wrapper.problem, isNull);
    expect(_clickFunction(), isNot(same(before)));
    expect(_clickIsOwnProperty(), isTrue);

    wrapper.uninstall();

    expect(wrapper.isInstalled, isFalse);
    expect(_clickIsOwnProperty(), hadOwn);
    expect(_clickFunction(), same(before));
  });

  test('the wrapper does not change what the picker sees or returns', () async {
    final without = await _pickOnce(withWrapper: false);
    final wrapped = await _pickOnce(withWrapper: true);

    expect(wrapped.name, without.name);
    expect(wrapped.bytes, without.bytes);
    expect(wrapped.bytes, [80, 75, 3, 4]);
    // One click, on a file input, with the same accept/multiple/connected
    // state and no arguments, with or without the wrapper. (`connected` is
    // false: file_picker_web's input is never in the document at click time,
    // with or without the wrapper.)
    expect(wrapped.clicks, without.clicks);
    expect(
      wrapped.clicks,
      '[{"type":"file","accept":" .xlsx","multiple":false,'
      '"connected":false,"args":0}]',
    );
  });
}
