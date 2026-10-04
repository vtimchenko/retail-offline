// TEMPORARY DIAGNOSTICS - web implementation.
//
// file_picker_web creates its `<input type="file">` internally and never
// exposes it. The least invasive way to watch that element without touching
// the package is to wrap `HTMLInputElement.prototype.click` for the lifetime
// of the diagnostics: file_picker_web calls `uploadInput.click()` right after
// adding its listeners, so our wrapper sees exactly that input, attaches its
// own passive listeners (`input`, `change`, `cancel`) and then calls the
// original `click()`. Nothing is cancelled, replaced or re-dispatched, and
// `stop()` removes the wrapper and every listener again.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Observes browser events relevant to the iOS file-picker investigation.
class BrowserEventObserver {
  JSObject? _handle;

  void start(void Function(String message) log) {
    if (_handle != null) return;
    try {
      final install = globalContext.callMethod<JSFunction>(
        'eval'.toJS,
        _script.toJS,
      );
      final emit = ((JSString message) => log(message.toDart)).toJS;
      _handle = install.callAsFunction(null, emit) as JSObject?;
    } on Object catch (e) {
      log('browser observer FAILED to start: ${e.runtimeType}: $e');
    }
  }

  void stop() {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    try {
      handle.callMethod('stop'.toJS);
    } on Object {
      // Nothing useful to do while tearing down diagnostics.
    }
  }

  // Plain JavaScript (evaluated once per start). Logs only event types,
  // flags, counts, file name/extension/size/MIME type - never contents.
  static const String _script = r'''
(function () {
  return function (cb) {
    var proto = HTMLInputElement.prototype;
    var hadOwnClick = Object.prototype.hasOwnProperty.call(proto, 'click');
    var prevClick = proto.click;
    var undo = [];
    var seq = 0;

    function safe(fn) {
      try { return fn(); } catch (e) { return 'n/a(' + e + ')'; }
    }
    function state(input) {
      return 'connected=' + safe(function () { return input.isConnected; }) +
        ' accept="' + safe(function () { return input.accept; }) + '"' +
        ' multiple=' + safe(function () { return input.multiple; });
    }
    function files(input) {
      return safe(function () {
        var f = input.files;
        if (!f) return 'files=null';
        var s = 'files=' + f.length;
        if (f.length > 0) {
          var x = f[0];
          var n = x.name || '';
          var dot = n.lastIndexOf('.');
          s += ' name=' + n +
            ' ext=' + (dot >= 0 ? n.substring(dot + 1) : '(none)') +
            ' size=' + x.size +
            ' type=' + (x.type || '(empty)');
        }
        return s;
      });
    }
    function listen(target, type, fn) {
      target.addEventListener(type, fn);
      undo.push(function () { target.removeEventListener(type, fn); });
    }

    proto.click = function () {
      var input = this;
      if (input.type === 'file') {
        var tag = 'input#' + (++seq);
        cb(tag + ' click() ' + state(input));
        ['input', 'change', 'cancel'].forEach(function (type) {
          input.addEventListener(type, function () {
            cb(tag + ' EVENT ' + type + ' ' + state(input) + ' ' + files(input));
          });
        });
        setTimeout(function () {
          cb(tag + ' next task: connected=' + safe(function () { return input.isConnected; }));
        }, 0);
        setTimeout(function () {
          cb(tag + ' +2s: connected=' + safe(function () { return input.isConnected; }) +
            ' ' + files(input));
        }, 2000);
      }
      return prevClick.apply(this, arguments);
    };

    ['focus', 'blur'].forEach(function (type) {
      listen(window, type, function () {
        cb('window ' + type + ' hasFocus=' + safe(function () { return document.hasFocus(); }) +
          ' visibility=' + document.visibilityState);
      });
    });
    listen(document, 'visibilitychange', function () {
      cb('document visibilitychange -> ' + document.visibilityState);
    });

    cb('observer started; visibility=' + document.visibilityState +
      ' standalone=' + safe(function () {
        return (navigator.standalone === true) ||
          window.matchMedia('(display-mode: standalone)').matches;
      }));
    cb('userAgent=' + navigator.userAgent);

    return {
      stop: function () {
        undo.forEach(function (fn) { fn(); });
        if (hadOwnClick) { proto.click = prevClick; } else { delete proto.click; }
        cb('observer stopped');
      }
    };
  };
})()
''';
}
