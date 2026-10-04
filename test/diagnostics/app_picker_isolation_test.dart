@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/diagnostics/picker_ab.dart';
import 'package:retail_offline/models/store.dart';
import 'package:retail_offline/screens/home/home_screen.dart';

String _eval(String script) =>
    globalContext.callMethod<JSString>('eval'.toJS, script.toJS).toDart;

/// The default diagnostic variant must be the production candidate: nothing
/// may touch `HTMLInputElement.prototype`, otherwise a real-device test of
/// the app-owned picker would not be valid.
void main() {
  testWidgets('app-picker is the default and patches no prototype', (
    tester,
  ) async {
    expect(PickerAbVariant.current, PickerAbVariant.appPicker);

    _eval('''
(function () {
  var p = HTMLInputElement.prototype;
  globalThis.__origClick = p.click;
  globalThis.__origHadOwn = Object.prototype.hasOwnProperty.call(p, 'click');
  globalThis.__origAdd = EventTarget.prototype.addEventListener;
  return '';
})()
''');
    addTearDown(
      () => _eval(
        "delete globalThis.__origClick; delete globalThis.__origHadOwn; "
        "delete globalThis.__origAdd; ''",
      ),
    );

    String unchanged() => _eval('''
String(
  HTMLInputElement.prototype.click === globalThis.__origClick &&
  Object.prototype.hasOwnProperty.call(HTMLInputElement.prototype, 'click')
      === globalThis.__origHadOwn &&
  EventTarget.prototype.addEventListener === globalThis.__origAdd
)
''');

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(
          store: Store(nameStore: 'Тест', idStore: '1'),
        ),
      ),
    );
    expect(unchanged(), 'true');

    // Dispose too: it would restore a wrapper if one had been installed.
    await tester.pumpWidget(const SizedBox());
    expect(unchanged(), 'true');
  });
}
