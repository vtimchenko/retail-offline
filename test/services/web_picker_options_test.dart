@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/services/file/web_picker_options.dart';

/// Replaces `HTMLInputElement.prototype.click` so that "clicking" a file input
/// opens no OS dialog and instead replays what iOS Safari does:
/// window `focus` after [focusAfterMs], then - [changeAfterMs] later - either
/// a `change` carrying one file, or a native `cancel`.
/// Returns the function that restores the browser.
JSFunction _fakeChooser({
  required int focusAfterMs,
  required int changeAfterMs,
  bool cancel = false,
}) {
  final install = globalContext.callMethod<JSFunction>(
    'eval'.toJS,
    r'''
(function (focusAfter, changeAfter, cancel) {
  var proto = HTMLInputElement.prototype;
  var had = Object.prototype.hasOwnProperty.call(proto, 'click');
  var prev = proto.click;
  proto.click = function () {
    var input = this;
    if (input.type !== 'file') return prev.apply(this, arguments);
    setTimeout(function () { window.dispatchEvent(new Event('focus')); }, focusAfter);
    setTimeout(function () {
      if (cancel) { input.dispatchEvent(new Event('cancel')); return; }
      var dt = new DataTransfer();
      dt.items.add(new File([new Uint8Array([80, 75, 3, 4])], 'late.xlsx'));
      input.files = dt.files;
      input.dispatchEvent(new Event('change'));
    }, focusAfter + changeAfter);
  };
  return function () { if (had) { proto.click = prev; } else { delete proto.click; } };
})
'''
        .toJS,
  );
  return install.callAsFunction(
    null,
    focusAfterMs.toJS,
    changeAfterMs.toJS,
    cancel.toJS,
  ) as JSFunction;
}

Future<PlatformFile?> _pick(WebOptions options) => FilePicker.pickFile(
  type: FileType.custom,
  allowedExtensions: const ['xlsx'],
  webOptions: options,
);

void main() {
  // `flutter test` does not run the generated plugin registrant, so register
  // the real web implementation (the one the app uses) explicitly.
  setUpAll(() => FilePickerWeb.registerWith(webPluginRegistrar));

  test('the production options disable the focus-based cancellation', () {
    final options = pickerWebOptions();
    expect(options, isA<FilePickerWebOptions>());
    expect((options as FilePickerWebOptions).cancelUploadOnWindowBlur, isFalse);
    // Nothing else is changed from the package defaults.
    expect(options.withData, isTrue);
    expect(options.withReadStream, isFalse);
  });

  group('iOS Safari timing: change arrives 800 ms after window focus', () {
    late JSFunction restore;
    tearDown(() => restore.callAsFunction());

    test(
      'REGRESSION GUARD: package defaults lose the file (returns null)',
      () async {
        restore = _fakeChooser(focusAfterMs: 20, changeAfterMs: 800);
        // If this ever starts returning a file, file_picker_web fixed the race
        // itself and pickerWebOptions() can be reconsidered.
        expect(await _pick(const WebOptions()), isNull);
      },
    );

    test('with pickerWebOptions() the late file is delivered', () async {
      restore = _fakeChooser(focusAfterMs: 20, changeAfterMs: 800);
      final file = await _pick(pickerWebOptions());
      expect(file, isNotNull);
      expect(file!.name, 'late.xlsx');
      expect(await file.readAsBytes(), [80, 75, 3, 4]);
    });

    test('a quick change (desktop timing) still works', () async {
      restore = _fakeChooser(focusAfterMs: 20, changeAfterMs: 50);
      final file = await _pick(pickerWebOptions());
      expect(file?.name, 'late.xlsx');
    });
  });

  group('cancellation with focus heuristic disabled', () {
    late JSFunction restore;
    tearDown(() => restore.callAsFunction());

    test('the native cancel event still completes with null', () async {
      restore = _fakeChooser(
        focusAfterMs: 20,
        changeAfterMs: 100,
        cancel: true,
      );
      expect(await _pick(pickerWebOptions()), isNull);
    });
  });
}
