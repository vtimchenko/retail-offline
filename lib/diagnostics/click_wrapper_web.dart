// TEMPORARY A/B DIAGNOSTICS - web implementation.
//
// Reproduces ONLY the part of the old `browser_event_observer_web.dart`
// (removed in PR #6) that wrapped `HTMLInputElement.prototype.click`:
//
//   * installed the same way: evaluated JavaScript (sloppy-mode function),
//     assigned as an own property of `HTMLInputElement.prototype`;
//   * the wrapper is a plain `function () {...}` that calls the previous
//     implementation synchronously, in the same call stack and with the same
//     receiver and arguments: `return prevClick.apply(this, arguments);`;
//   * uninstall restores the previous state exactly like the old `stop()`:
//     put the old function back if the prototype had its own `click`, delete
//     the own property otherwise.
//
// Deliberately NOT reproduced: every log call (the old wrapper called back
// into Dart before `apply`), the extra `input`/`change`/`cancel` listeners,
// the `setTimeout(0)` / `setTimeout(2000)` timers, window focus/blur and
// document visibilitychange listeners. The wrapper does not touch the DOM,
// the input's attributes, the events, or the file contents.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class ClickWrapper {
  JSObject? _handle;
  String? _problem;

  bool get isInstalled => _handle != null;

  /// Why [install] did not install anything (shown in the A/B marker).
  String? get problem => _problem;

  void install() {
    if (_handle != null) return;
    try {
      final install = globalContext.callMethod<JSFunction>(
        'eval'.toJS,
        _script.toJS,
      );
      _handle = install.callAsFunction(null) as JSObject?;
    } on Object catch (e) {
      _problem = '${e.runtimeType}';
    }
  }

  void uninstall() {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    try {
      handle.callMethod('uninstall'.toJS);
    } on Object {
      // Nothing useful to do while tearing down diagnostics.
    }
  }

  static const String _script = r'''
(function () {
  return function () {
    var proto = HTMLInputElement.prototype;
    var hadOwnClick = Object.prototype.hasOwnProperty.call(proto, 'click');
    var prevClick = proto.click;

    proto.click = function () {
      return prevClick.apply(this, arguments);
    };

    return {
      uninstall: function () {
        if (hadOwnClick) { proto.click = prevClick; } else { delete proto.click; }
      }
    };
  };
})()
''';
}
