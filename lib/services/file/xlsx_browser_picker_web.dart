import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart';

import 'picked_bytes.dart';

/// Lets the user choose one `.xlsx` file with the browser's own file chooser
/// and returns its name and bytes (in memory only: no paths, no object URLs,
/// no persistence).
///
/// * `change` with a file -> the file; `change` without one, or the native
///   `cancel` event -> `null`.
/// * Cancellation is signalled ONLY by the native `cancel` event. There is no
///   window-focus/blur/visibility heuristic and no timeout: guessing from
///   elapsed time or focus lost real selections on iOS Safari, where `change`
///   arrives after the window regains focus.
/// * Read failures complete with the original error; `LocalFileService` maps
///   it to its friendly `ImportException`.
///
/// Must be called synchronously from the user's tap (no `await` before it):
/// `input.click()` runs in this call.
///
/// Only one pick can be pending. This is a defensive guard, not a user
/// workflow: the native chooser is modal and the UI does not start a second
/// pick. If one is requested anyway, it fails with a [StateError] and the
/// pending pick is left completely untouched (no input is created or
/// clicked), so an internally rejected request is never reported as a user
/// cancellation and the first pick still finishes through its own
/// `change`/`cancel` event.
Future<PickedBytes?> pickXlsxFromBrowser() {
  if (_pending != null) {
    return Future<PickedBytes?>.error(
      StateError('A file pick is already in progress.'),
    );
  }
  return _PendingPick().start();
}

/// The pick in progress, or `null`.
///
/// RETENTION: this top-level variable intentionally holds the whole pending
/// pick (the `<input>`, its listeners and the completer) from before
/// `input.click()` until `change`/`cancel`. In real-device testing on iOS
/// Safari and the installed PWA, a file input that nothing else referenced
/// left the picker Future pending after the user chose a file, while
/// explicitly retaining the same detached input until `change`/`cancel`
/// delivered the file (see the A/B diagnostics in `lib/diagnostics/`). We
/// observed that behaviour; we have not established the browser-internal
/// cause. Do not replace this with a listener-only reference cycle
/// (input -> listener -> input): that variant was tested and did not help.
_PendingPick? _pending;

/// Number of picks currently pending (0 or 1). For tests only.
@visibleForTesting
int get pendingPickCount => _pending == null ? 0 : 1;

/// Whether [input] is the input of the pending pick. For tests only.
@visibleForTesting
bool isPendingInput(Object input) => identical(_pending?.input, input);

final class _PendingPick {
  _PendingPick() : input = HTMLInputElement();

  /// Created detached and kept detached: never added to the document.
  final HTMLInputElement input;

  final Completer<PickedBytes?> _completer = Completer<PickedBytes?>();

  // One JS function object per listener, reused for add and remove (a new
  // `.toJS` wrapper would never match in `removeEventListener`).
  late final JSFunction _onChange = _handleChange.toJS;
  late final JSFunction _onCancel = _handleCancel.toJS;

  bool _released = false;

  Future<PickedBytes?> start() {
    input
      ..type = 'file'
      ..accept = '.xlsx'
      ..multiple = false;
    input.addEventListener('change', _onChange);
    input.addEventListener('cancel', _onCancel);

    _pending = this; // retained BEFORE the chooser opens
    try {
      input.click(); // still inside the user's gesture
    } on Object catch (e, st) {
      _release();
      return Future<PickedBytes?>.error(e, st);
    }
    return _completer.future;
  }

  void _handleChange(Event _) {
    if (_released) return; // late/duplicate event after a terminal one
    final files = input.files;
    final file = (files == null || files.length == 0) ? null : files.item(0);
    _release();
    if (file == null) {
      _complete(null);
      return;
    }
    _read(file);
  }

  void _handleCancel(Event _) {
    if (_released) return;
    _release();
    _complete(null);
  }

  /// Reads the chosen file after the pick state has already been released;
  /// the `File` object is all that is needed from here on.
  Future<void> _read(File file) async {
    try {
      final buffer = await file.arrayBuffer().toDart;
      _complete((name: file.name, bytes: buffer.toDart.asUint8List()));
    } on Object catch (e, st) {
      if (!_completer.isCompleted) _completer.completeError(e, st);
    }
  }

  /// The single terminal-cleanup path; safe to call any number of times.
  void _release() {
    if (_released) return;
    _released = true;
    input.removeEventListener('change', _onChange);
    input.removeEventListener('cancel', _onCancel);
    if (identical(_pending, this)) _pending = null;
  }

  void _complete(PickedBytes? value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}
