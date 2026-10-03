import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/imported_file.dart';
import '../home_controller.dart';

/// One of the two independent file sections on the home screen.
///
/// Test keys: `<slot>-select-file`, `<slot>-google-drive`, `<slot>-status`.
class FileSlotCard extends StatelessWidget {
  const FileSlotCard({
    super.key,
    required this.slotId,
    required this.title,
    required this.icon,
    required this.slot,
    required this.enabled,
    required this.onSelectFile,
    required this.onGoogleDrive,
  });

  final ImportSlotId slotId;
  final String title;
  final IconData icon;
  final FileSlot slot;

  /// False while any import work is in progress.
  final bool enabled;
  final VoidCallback onSelectFile;
  final VoidCallback onGoogleDrive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final file = slot.file;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  key: Key('${slotId.name}-status'),
                  status: slot.status,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (file != null)
              _FileInfo(file: file)
            else
              Text(
                AppStrings.noFileSelected,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            if (slot.error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      slot.error!,
                      key: Key('${slotId.name}-error'),
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (slot.isBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('${slotId.name}-select-file'),
                  onPressed: enabled ? onSelectFile : null,
                  icon: const Icon(Icons.upload_file),
                  label: const Text(AppStrings.selectFile),
                ),
                OutlinedButton.icon(
                  key: Key('${slotId.name}-google-drive'),
                  onPressed: enabled ? onGoogleDrive : null,
                  icon: const Icon(Icons.add_link),
                  label: const Text(AppStrings.googleDriveLink),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FileInfo extends StatelessWidget {
  const _FileInfo({required this.file});

  final ImportedFile file;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final source = switch (file.source) {
      FileSource.local => AppStrings.sourceLocal,
      FileSource.googleDrive => AppStrings.sourceGoogleDrive,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.name,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            softWrap: true,
          ),
          const SizedBox(height: 4),
          Text(
            '${AppStrings.sourceLabel}: $source',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.status});

  final SlotStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      SlotStatus.empty => (
        AppStrings.statusEmpty,
        AppColors.textSecondary,
        Icons.radio_button_unchecked,
      ),
      SlotStatus.ready => (
        AppStrings.statusReady,
        AppColors.primaryDark,
        Icons.check_circle_outline,
      ),
      SlotStatus.loading => (
        AppStrings.statusLoading,
        AppColors.primaryDark,
        Icons.hourglass_top,
      ),
      SlotStatus.loaded => (
        AppStrings.statusLoaded,
        AppColors.primaryDark,
        Icons.check_circle,
      ),
      SlotStatus.error => (
        AppStrings.statusError,
        AppColors.error,
        Icons.error_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
