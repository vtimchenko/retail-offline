import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../home_controller.dart';

/// Shows the counts of the data currently loaded in the session.
class ImportSummaryCard extends StatelessWidget {
  const ImportSummaryCard({super.key, required this.summary});

  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: const Key('import-summary'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  AppStrings.importDoneTitle,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Line(AppStrings.ordersCount, summary.orders),
            _Line(AppStrings.orderItemsCount, summary.orderItems),
            _Line(AppStrings.inventoryRecordsCount, summary.inventoryRecords),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
