// TEMPORARY DIAGNOSTICS for the iOS local-file-picker investigation.
// Remove this whole `lib/diagnostics/` folder, the panel widget and the few
// `PickerDiagnostics` calls once the root cause is fixed.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser_event_observer.dart';

/// In-memory, on-screen log of what happens between the tap on
/// "Обрати файл" and `FilePicker.pickFile()` returning.
///
/// Every entry is appended and published immediately (not after the picker
/// completes), so events that arrive while the picker Future is pending - or
/// after it already returned `null` - are visible. Never receives file
/// contents: only names, sizes, counts, flags and error types.
class PickerDiagnostics extends ChangeNotifier {
  PickerDiagnostics._();

  static final PickerDiagnostics instance = PickerDiagnostics._();

  static const int _maxLines = 600;

  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _lines = <String>[];
  final BrowserEventObserver _observer = BrowserEventObserver();
  int _attached = 0;

  List<String> get lines => List.unmodifiable(_lines);

  /// The whole log as plain text (for the Copy button).
  String get text => _lines.join('\n');

  /// Appends a line prefixed with the milliseconds elapsed since the start of
  /// the current attempt (see [beginAttempt]).
  void log(String message) {
    final ms = _clock.elapsedMilliseconds.toString().padLeft(5, '0');
    _lines.add('[$ms ms] $message');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    notifyListeners();
  }

  /// Starts a new numbered attempt and restarts the millisecond clock, so
  /// every following event (even one that arrives long after the picker
  /// returned) is relative to the tap that started it.
  void beginAttempt() {
    _clock
      ..reset()
      ..start();
    if (_lines.isNotEmpty) _lines.add('');
    log('===== pickXlsx started =====');
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  /// Installs the browser-level observers (window focus/blur, document
  /// visibility, and the `<input type=file>` created by file_picker_web).
  /// Reference counted; every call must be paired with [detach].
  void attach() {
    if (_attached++ == 0) {
      _observer.start(log);
    }
  }

  void detach() {
    if (_attached > 0 && --_attached == 0) {
      _observer.stop();
    }
  }

  /// Logs a warning if the operation is still pending after 10 s and 30 s.
  /// It only writes log lines - it never cancels or completes anything.
  /// Returns the function that stops the markers.
  VoidCallback watchPending(String what) {
    final timers = <Timer>[
      for (final seconds in const [10, 30])
        Timer(
          Duration(seconds: seconds),
          () => log('WARNING: $what still pending after $seconds seconds'),
        ),
    ];
    return () {
      for (final t in timers) {
        t.cancel();
      }
    };
  }
}
