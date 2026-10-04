// TEMPORARY A/B DIAGNOSTICS - web implementation.
//
// Reproduces ONLY parts of the old `browser_event_observer_web.dart`
// (removed in PR #6) that wrapped `HTMLInputElement.prototype.click`.
//
// Variant `click-wrapper` (A/B 1, `withListeners: false`):
//   * installed the same way as the old observer: evaluated JavaScript
//     (sloppy-mode function) assigned as an own property of
//     `HTMLInputElement.prototype`;
//   * the wrapper is a plain `function () {...}` that calls the previous
//     implementation synchronously, in the same call stack and with the same
//     receiver and arguments: `return prevClick.apply(this, arguments);`.
//
// Variant `click-wrapper+listeners` (A/B 2, `withListeners: true`):
//   * the same wrapper, but for `<input type="file">` it first registers
//     three listeners directly on that input - `input`, `change`, `cancel`,
//     in that order, with `addEventListener(type, fn)` (no options object,
//     exactly like the old observer's `forEach`) - and only then calls the
//     previous `click` implementation;
//   * the callbacks do nothing observable. Each one is a closure that merely
//     mentions the input (`void input;`) so that, as in the old observer,
//     the listener closure refers back to the input. They never call Dart,
//     never read `input.files`, never log, never touch events.
//   * the listeners are never removed.
//
// In both variants uninstall restores the previous state exactly like the old
// `stop()`: put the old function back if the prototype had its own `click`,
// delete the own property otherwise.
//
// Deliberately NOT reproduced: every log call (the old wrapper called back
// into Dart before `apply`), the `setTimeout(0)` / `setTimeout(2000)` timers,
// window focus/blur and document visibilitychange listeners. Nothing here
// touches the DOM, the input's attributes, the events or the file contents,
// and nothing keeps a reference to the input outside the input itself.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class ClickWrapper {
  ClickWrapper({this.withListeners = false});

  /// Also register the no-op `input`/`change`/`cancel` listeners.
  final bool withListeners;

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
      _handle = install.callAsFunction(null, withListeners.toJS) as JSObject?;
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
  return function (withListeners) {
    var proto = HTMLInputElement.prototype;
    var hadOwnClick = Object.prototype.hasOwnProperty.call(proto, 'click');
    var prevClick = proto.click;

    if (withListeners) {
      proto.click = function () {
        var input = this;
        if (input.type === 'file') {
          ['input', 'change', 'cancel'].forEach(function (type) {
            input.addEventListener(type, function () { void input; });
          });
        }
        return prevClick.apply(this, arguments);
      };
    } else {
      proto.click = function () {
        return prevClick.apply(this, arguments);
      };
    }

    return {
      uninstall: function () {
        if (hadOwnClick) { proto.click = prevClick; } else { delete proto.click; }
      }
    };
  };
})()
''';
}
