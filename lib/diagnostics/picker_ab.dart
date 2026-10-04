// TEMPORARY A/B DIAGNOSTICS for the iOS Safari/PWA local file picker.
// Delete the whole `lib/diagnostics/` folder, and the few lines marked
// `TEMPORARY A/B` in `home_screen.dart`, when the investigation is over.
//
// Nothing here runs timers or listens to focus/blur/visibility. The only
// output is a four-line marker on the home screen.

import 'package:flutter/material.dart';

import '../core/errors/import_exception.dart';
import '../models/imported_file.dart';
import '../services/file/local_file_service.dart';

/// Which experiment this build is. Chosen at build time:
/// `--dart-define=PICKER_AB_VARIANT=baseline`. The default is the variant
/// under test, because the deploy workflow cannot pass defines.
enum PickerAbVariant {
  /// Exactly what `main` does (control).
  baseline('baseline'),

  /// A/B 1: `HTMLInputElement.prototype.click` is wrapped by a pass-through
  /// function. Real iPhone result: PENDING.
  clickWrapper('click-wrapper', wrapsClick: true),

  /// A/B 2: the same wrapper, plus no-op `input`/`change`/`cancel` listeners
  /// registered on the file input right before the original click.
  clickWrapperListeners(
    'click-wrapper+listeners',
    wrapsClick: true,
    addsInputListeners: true,
  ),

  /// A/B 3: A/B 2, plus the file input is kept in a rooted JS `Set` from
  /// before the original click until its `change` or `cancel` event. Real
  /// iPhone result of A/B 1 and A/B 2: PENDING.
  clickWrapperListenersRetain(
    'click-wrapper+listeners+retain',
    wrapsClick: true,
    addsInputListeners: true,
    retainsInput: true,
  );

  const PickerAbVariant(
    this.label, {
    this.wrapsClick = false,
    this.addsInputListeners = false,
    this.retainsInput = false,
  });

  final String label;

  /// Whether `HTMLInputElement.prototype.click` is wrapped.
  final bool wrapsClick;

  /// Whether the wrapper also registers the no-op input listeners.
  final bool addsInputListeners;

  /// Whether the wrapper also retains the input until change/cancel.
  final bool retainsInput;

  static const String _requested = String.fromEnvironment(
    'PICKER_AB_VARIANT',
    defaultValue: 'click-wrapper+listeners+retain',
  );

  /// Unknown values fall back to [baseline] so a typo can never silently
  /// install the wrapper; the marker always shows the effective variant.
  static final PickerAbVariant current = values.firstWhere(
    (v) => v.label == _requested,
    orElse: () => baseline,
  );
}

/// Visible build identifier: experiment number + the `main` commit it is
/// based on.
const String pickerAbBuild = String.fromEnvironment(
  'PICKER_AB_BUILD',
  defaultValue: 'ab3-b30a312',
);

enum PickerAbState { idle, pending, file, nullResult, error }

/// Outcome of the last `LocalFileService.pickXlsx()` call.
class PickerAbProbe extends ChangeNotifier {
  PickerAbState _state = PickerAbState.idle;
  String _detail = '';
  final Stopwatch _clock = Stopwatch();

  PickerAbState get state => _state;

  /// Extra text for the marker (never file contents).
  String get detail => _detail;

  void started() {
    _clock
      ..reset()
      ..start();
    _set(PickerAbState.pending, '');
  }

  void finished(PickerAbState state, [String detail = '']) {
    _clock.stop();
    _set(state, detail);
  }

  int get elapsedMs => _clock.elapsedMilliseconds;

  void _set(PickerAbState state, String detail) {
    _state = state;
    _detail = detail;
    notifyListeners();
  }
}

/// Reports how `FilePicker.pickFile` ended, without touching
/// [LocalFileService]: `started()` runs synchronously (still inside the
/// user's tap), then the real `pickXlsx()` runs unchanged.
///
/// * `FILE`  - the picker returned a file (even if validation then rejected
///   it; the detail says so).
/// * `NULL`  - the picker returned `null` (cancel, or a lost selection).
/// * `ERROR` - the picker itself threw.
class ProbedLocalFileService extends LocalFileService {
  /// [picker] is only for tests; the app uses the real file picker.
  ProbedLocalFileService(this.probe, {super.picker});

  final PickerAbProbe probe;

  @override
  Future<ImportedFile?> pickXlsx() async {
    probe.started();
    try {
      final file = await super.pickXlsx();
      if (file == null) {
        probe.finished(PickerAbState.nullResult);
      } else {
        probe.finished(PickerAbState.file, '${file.bytes.length} bytes');
      }
      return file;
    } on ImportException catch (e) {
      if (e.technical == 'Picker failure') {
        probe.finished(PickerAbState.error, '${e.cause.runtimeType}');
      } else {
        // The picker did return a file; only validation refused it.
        probe.finished(PickerAbState.file, 'rejected by validation');
      }
      rethrow;
    }
  }
}

/// Small unobtrusive text block with the build, the variant and the result of
/// the last pick.
class PickerAbMarker extends StatelessWidget {
  const PickerAbMarker({
    super.key,
    required this.probe,
    required this.wrapperActive,
    this.wrapperProblem,
  });

  final PickerAbProbe probe;
  final bool wrapperActive;
  final String? wrapperProblem;

  String get _variantLine {
    final variant = PickerAbVariant.current;
    if (!variant.wrapsClick) return variant.label;
    if (wrapperProblem != null) {
      return '${variant.label} (INSTALL FAILED: $wrapperProblem)';
    }
    return '${variant.label} (wrapper ${wrapperActive ? 'installed' : 'NOT installed'})';
  }

  String get _resultLine {
    switch (probe.state) {
      case PickerAbState.idle:
        return '-';
      case PickerAbState.pending:
        return 'PENDING';
      case PickerAbState.file:
        return _withDetail('FILE');
      case PickerAbState.nullResult:
        return _withDetail('NULL');
      case PickerAbState.error:
        return _withDetail('ERROR');
    }
  }

  String _withDetail(String label) {
    final detail = probe.detail.isEmpty ? '' : ', ${probe.detail}';
    return '$label (${probe.elapsedMs} ms$detail)';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace', color: Colors.black54);
    return ListenableBuilder(
      listenable: probe,
      builder: (context, _) => Padding(
        key: const Key('picker-ab-marker'),
        padding: const EdgeInsets.only(top: 24),
        child: Text(
          'iOS picker A/B\n'
          'Build: $pickerAbBuild\n'
          'Variant: $_variantLine\n'
          'Last picker result: $_resultLine',
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}
