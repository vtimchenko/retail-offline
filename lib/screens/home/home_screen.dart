import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../diagnostics/click_wrapper.dart'; // TEMPORARY A/B
import '../../diagnostics/picker_ab.dart'; // TEMPORARY A/B
import '../../models/store.dart';
import '../../repositories/session_data_repository.dart';
import '../../widgets/centered_content.dart';
import 'home_controller.dart';
import 'widgets/drive_link_dialog.dart';
import 'widgets/file_slot_card.dart';
import 'widgets/import_summary_card.dart';

/// Main screen of the app for the selected [store]: the user provides the
/// orders and inventory files, which are validated and loaded into the
/// session repository. Order search comes later.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    this.repository,
    this.controller,
  });

  /// Store chosen on the previous screen; `store.idStore` is used by
  /// future features.
  final Store store;

  /// Where imported data goes. Defaults to a new in-memory repository.
  final SessionDataRepository? repository;

  /// Overrides the whole import controller (used by tests).
  final HomeController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  late final bool _ownsController;

  // TEMPORARY A/B (iOS picker investigation).
  final PickerAbProbe _abProbe = PickerAbProbe();
  final ClickWrapper _abClickWrapper = ClickWrapper(
    withListeners: PickerAbVariant.current.addsInputListeners,
  );

  /// Below this width the two cards are stacked.
  static const double _wideBreakpoint = 720;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        HomeController(
          repository: widget.repository ?? InMemorySessionDataRepository(),
          localFiles: ProbedLocalFileService(_abProbe), // TEMPORARY A/B
        );
    // TEMPORARY A/B: installed once, before any tap, like the old observer.
    if (PickerAbVariant.current.wrapsClick) {
      _abClickWrapper.install();
    }
  }

  @override
  void dispose() {
    _abClickWrapper.uninstall(); // TEMPORARY A/B
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _enterDriveLink(ImportSlotId id) async {
    final url = await showDriveLinkDialog(context);
    if (url == null) return;
    await _controller.pickGoogleDriveFile(id, url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.store.nameStore)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) =>
              CenteredContent(maxWidth: 960, child: _buildContent(context)),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final c = _controller;

    Widget card(ImportSlotId id, String title, IconData icon) => FileSlotCard(
      slotId: id,
      title: title,
      icon: icon,
      slot: c.slot(id),
      enabled: !c.isBusy,
      onSelectFile: () => c.pickLocalFile(id),
      onGoogleDrive: () => _enterDriveLink(id),
    );

    final ordersCard = card(
      ImportSlotId.orders,
      AppStrings.ordersCardTitle,
      Icons.receipt_long_outlined,
    );
    final inventoryCard = card(
      ImportSlotId.inventory,
      AppStrings.inventoryCardTitle,
      Icons.inventory_2_outlined,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppStrings.homeTitle,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.homeSubtitle,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ordersCard),
                  const SizedBox(width: 16),
                  Expanded(child: inventoryCard),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [ordersCard, const SizedBox(height: 16), inventoryCard],
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('load-data'),
          onPressed: c.canLoad ? c.loadData : null,
          child: c.isImporting
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(AppStrings.importing),
                  ],
                )
              : const Text(AppStrings.loadData),
        ),
        if (!c.isBusy && !(c.orders.isUsable && c.inventory.isUsable)) ...[
          const SizedBox(height: 8),
          Text(
            AppStrings.loadDataHint,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (c.summary != null) ...[
          const SizedBox(height: 20),
          ImportSummaryCard(summary: c.summary!),
        ],
        // TEMPORARY A/B (iOS picker investigation).
        PickerAbMarker(
          probe: _abProbe,
          wrapperActive: _abClickWrapper.isInstalled,
          wrapperProblem: _abClickWrapper.problem,
        ),
      ],
    );
  }
}
