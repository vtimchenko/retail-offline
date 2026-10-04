import 'package:file_picker/file_picker.dart' show WebOptions;
import 'package:file_picker_web/file_picker_web.dart' show FilePickerWebOptions;

/// Browser options for the local XLSX picker.
///
/// `cancelUploadOnWindowBlur: false` turns off file_picker_web's heuristic
/// "the window regained focus, so the dialog was cancelled": it completes the
/// pick with `null` 500 ms after the window `focus` event unless `change` has
/// already fired, and then ignores the real `change`. iOS Safari delivers
/// `change` after that (confirmed on a real iPhone: focus, `null` 502 ms
/// later, `change` another 100 ms after that), so a valid selection was lost.
///
/// Real cancellation is still reported through the input's native `cancel`
/// event. Everything else keeps the package defaults (bytes are read during
/// the pick, no read stream).
WebOptions pickerWebOptions() =>
    const FilePickerWebOptions(cancelUploadOnWindowBlur: false);
