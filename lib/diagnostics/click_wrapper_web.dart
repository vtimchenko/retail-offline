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
// Variant `click-wrapper+listeners+retain` (A/B 3, `retainInputs: true`):
//   * everything from A/B 2, plus: before the original click the file input
//     is added to a JavaScript `Set` (`retained`). The Set is referenced by
//     the wrapper closure, which hangs off `HTMLInputElement.prototype`, so
//     it is rooted from the global object and the input cannot be garbage
//     collected while it is in the Set;
//   * the `change` and `cancel` listeners (and only those) remove the input
//     from the Set. The `input` listener stays a no-op. Nothing else releases
//     it: no timer, no `requestAnimationFrame`, no focus/blur/visibility
//     listener, no rebuild. If neither `change` nor `cancel` ever arrives the
//     input stays in the Set for the rest of the page session. That is a
//     deliberate, temporary leak for this experiment and must never become
//     production code.
//   * the input is not attached to, or removed from, the DOM.
//
// In all variants uninstall restores the previous state exactly like the old
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

import 'package:flutter/foundation.dart' show visibleForTesting;

class ClickWrapper {
  ClickWrapper({this.withListeners = false, this.retainInputs = false});

  /// Also register the no-op `input`/`change`/`cancel` listeners.
  final bool withListeners;

  /// Also keep each file input in a rooted `Set` until `change`/`cancel`.
  /// Implies the listeners.
  final bool retainInputs;

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
      _handle = install.callAsFunction(
        null,
        withListeners.toJS,
        retainInputs.toJS,
      ) as JSObject?;
    } on Object catch (e) {
      _problem = '${e.runtimeType}';
    }
  }

  /// Number of inputs currently retained. For tests only: nothing in the app
  /// calls this.
  @visibleForTesting
  int get retainedCount =>
      _handle?.callMethod<JSNumber>('retainedCount'.toJS).toDartInt ?? 0;

  /// Whether [input] is currently retained. For tests only.
  @visibleForTesting
  bool isRetained(JSObject input) =>
      _handle?.callMethod<JSBoolean>('isRetained'.toJS, input).toDart ?? false;

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
  return function (withListeners, retainInputs) {
    var proto = HTMLInputElement.prototype;
    var hadOwnClick = Object.prototype.hasOwnProperty.call(proto, 'click');
    var prevClick = proto.click;
    // Rooted through the wrapper closure below (and thereby through
    // HTMLInputElement.prototype). Only created when retainInputs is true.
    var retained = retainInputs ? new Set() : null;

    if (retainInputs) {
      proto.click = function () {
        var input = this;
        if (input.type === 'file') {
          retained.add(input);
          ['input', 'change', 'cancel'].forEach(function (type) {
            input.addEventListener(
              type,
              type === 'input'
                ? function () { void input; }
                : function () { retained.delete(input); }
            );
          });
        }
        return prevClick.apply(this, arguments);
      };
    } else if (withListeners) {
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
      retainedCount: function () { return retained ? retained.size : 0; },
      isRetained: function (input) { return retained ? retained.has(input) : false; },
      uninstall: function () {
        if (hadOwnClick) { proto.click = prevClick; } else { delete proto.click; }
      }
    };
  };
})()
''';
}
