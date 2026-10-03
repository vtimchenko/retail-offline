import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/import_exception.dart';
import '../../../services/file/google_drive_url.dart';

/// Asks for a public Google Drive share link. Returns the entered link, or
/// `null` if cancelled. The link is checked for shape here; downloading
/// happens afterwards in the controller.
Future<String?> showDriveLinkDialog(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _DriveLinkDialog(),
);

class _DriveLinkDialog extends StatefulWidget {
  const _DriveLinkDialog();

  @override
  State<_DriveLinkDialog> createState() => _DriveLinkDialogState();
}

class _DriveLinkDialogState extends State<_DriveLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    try {
      GoogleDriveUrl.parseFileId(text);
    } on ImportException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.driveDialogTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('drive-url-field'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: AppStrings.driveDialogLabel,
                hintText: AppStrings.driveDialogHint,
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.driveDialogNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('drive-url-submit'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _submit,
          child: const Text(AppStrings.getFile),
        ),
      ],
    );
  }
}
