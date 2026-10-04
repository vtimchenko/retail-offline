import 'package:file_picker/file_picker.dart' show WebOptions;

/// Non-web platforms have no browser options.
WebOptions pickerWebOptions() => const WebOptions();

/// Short description for the diagnostic log.
const String pickerWebOptionsLabel = 'webOptions=default (non-web)';
