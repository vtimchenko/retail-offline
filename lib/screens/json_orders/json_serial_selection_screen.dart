import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/fulfilment_application.dart';
import '../../application/fulfilment_scope.dart';
import '../../application/fulfilment_ui_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/fulfilment/fulfilment_session.dart';
import '../../models/retail_dataset.dart';
import '../../models/serial_selection.dart';
import '../../widgets/status_message.dart';
import '../json_import/fulfilment_block_message.dart';
import '../orders/serial_search.dart';

/// Reserves one stock slot at a time for a JSON order line.
///
/// [orderId] and [productId] are the only values this screen keeps. Each
/// build reads [FulfilmentScope], resolves that line on the current
/// [FulfilmentSession], and derives available and selected rows from
/// [FulfilmentSession.availableQuantity] and
/// [FulfilmentSession.slotReservedQuantity]. Add and remove send one unit
/// through [FulfilmentUiController].
class JsonSerialSelectionScreen extends StatefulWidget {
  /// Creates selection for one goods line in the ambient session.
  const JsonSerialSelectionScreen({
    super.key,
    required this.orderId,
    required this.productId,
  });

  /// Dataset `OrderID`. This is not an order number.
  final String orderId;

  /// Exact product-id literal. This is not parsed as a number.
  final String productId;

  @override
  State<JsonSerialSelectionScreen> createState() =>
      _JsonSerialSelectionScreenState();
}

class _JsonSerialSelectionScreenState extends State<JsonSerialSelectionScreen> {
  /// Desktop second click. Touch keeps a single tap as highlight only.
  static const _doubleTapWindow = Duration(milliseconds: 300);

  final TextEditingController _searchController = TextEditingController();

  _Slot? _availableHighlight;
  _Slot? _selectedHighlight;
  _Slot? _availableTapSlot;
  _Slot? _selectedTapSlot;
  DateTime? _availableTapAt;
  DateTime? _selectedTapAt;
  String? _inlineError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _doubleClick => switch (Theme.of(context).platform) {
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => true,
  };

  void _onSearchChanged(String _) => setState(() {});

  void _onAvailableTap(_Slot slot) {
    final doubled = _isDoubleTap(slot, _availableTapSlot, _availableTapAt);
    if (doubled) {
      _availableTapSlot = null;
      _availableTapAt = null;
    } else {
      _availableTapSlot = slot;
      _availableTapAt = DateTime.now();
    }
    setState(() => _availableHighlight = slot);
    if (doubled) unawaited(_reserve(slot));
  }

  void _onSelectedTap(_Slot slot) {
    final doubled = _isDoubleTap(slot, _selectedTapSlot, _selectedTapAt);
    if (doubled) {
      _selectedTapSlot = null;
      _selectedTapAt = null;
    } else {
      _selectedTapSlot = slot;
      _selectedTapAt = DateTime.now();
    }
    setState(() => _selectedHighlight = slot);
    if (doubled) unawaited(_release(slot));
  }

  bool _isDoubleTap(_Slot slot, _Slot? previous, DateTime? at) {
    if (!_doubleClick || previous != slot || at == null) return false;
    return DateTime.now().difference(at) <= _doubleTapWindow;
  }

  Future<void> _reserve(_Slot slot) async {
    final controller = FulfilmentScope.read(context);
    if (!_canReserve(controller, slot)) return;
    setState(() => _inlineError = null);
    try {
      final result = await controller.reserve(
        orderId: widget.orderId,
        productId: widget.productId,
        address: slot.address,
        serialNumber: slot.serialNumber,
        quantity: 1,
      );
      if (!mounted) return;
      _showReserve(result);
    } on Object {
      if (!mounted) return;
      setState(() => _inlineError = null);
    }
  }

  Future<void> _release(_Slot slot) async {
    final controller = FulfilmentScope.read(context);
    if (!_canRelease(controller, slot)) return;
    setState(() => _inlineError = null);
    try {
      final result = await controller.removeUnits(
        orderId: widget.orderId,
        productId: widget.productId,
        address: slot.address,
        serialNumber: slot.serialNumber,
        quantity: 1,
      );
      if (!mounted) return;
      _showRelease(result);
    } on Object {
      if (!mounted) return;
      setState(() => _inlineError = null);
    }
  }

  void _showReserve(FulfilmentCommandResult<ReserveResult>? result) {
    final phase = FulfilmentScope.read(context).phase;
    switch (result) {
      case null:
      case FulfilmentNotReady<ReserveResult>():
        return;
      case FulfilmentBlocked<ReserveResult>()
          when phase == FulfilmentUiPhase.ready:
        setState(() => _inlineError = null);
      case FulfilmentBlocked<ReserveResult>():
        return;
      case FulfilmentDomainRejected<ReserveResult>(:final result):
        final message = _reserveMessage(result);
        if (message == null) return;
        setState(() => _inlineError = message);
      case FulfilmentCommitted<ReserveResult>():
      case FulfilmentUnchanged<ReserveResult>():
        setState(() => _inlineError = null);
    }
  }

  void _showRelease(FulfilmentCommandResult<RemoveUnitsResult>? result) {
    final phase = FulfilmentScope.read(context).phase;
    switch (result) {
      case null:
      case FulfilmentNotReady<RemoveUnitsResult>():
        return;
      case FulfilmentBlocked<RemoveUnitsResult>()
          when phase == FulfilmentUiPhase.ready:
        setState(() => _inlineError = null);
      case FulfilmentBlocked<RemoveUnitsResult>():
        return;
      case FulfilmentDomainRejected<RemoveUnitsResult>(:final result):
        final message = _releaseMessage(result);
        if (message == null) return;
        setState(() => _inlineError = message);
      case FulfilmentCommitted<RemoveUnitsResult>():
      case FulfilmentUnchanged<RemoveUnitsResult>():
        setState(() => _inlineError = null);
    }
  }

  bool _canReserve(FulfilmentUiController controller, _Slot slot) {
    final ready = _readyLine(controller);
    if (ready == null || ready.locked || ready.good.isServiceGood) {
      return false;
    }
    final reserved = ready.session.lineReservedQuantity(
      orderId: widget.orderId,
      productId: widget.productId,
    );
    if (reserved >= ready.good.quantity) return false;
    for (final row in ready.visible) {
      if (row.slot == slot) return row.quantity > 0;
    }
    return false;
  }

  bool _canRelease(FulfilmentUiController controller, _Slot slot) {
    final ready = _readyLine(controller);
    if (ready == null || ready.locked || ready.good.isServiceGood) {
      return false;
    }
    for (final row in ready.selected) {
      if (row.slot == slot) return row.quantity >= 1;
    }
    return false;
  }

  _ReadyLine? _readyLine(FulfilmentUiController controller) {
    if (!_mutationsOpen(controller)) return null;
    final session = controller.session;
    if (session == null) return null;
    final order = _orderById(session, widget.orderId);
    if (order == null) return null;
    final good = _goodById(order, widget.productId);
    if (good == null) return null;
    final available = _availableRows(session, good);
    return _ReadyLine(
      session: session,
      good: good,
      locked: _isLocked(session.statusOf(widget.orderId)),
      visible: _filterAvailable(available, _searchController.text),
      selected: _selectedRows(session, widget.orderId, widget.productId),
    );
  }

  /// Drops a highlight whose row is no longer on screen.
  ///
  /// Search applies only to the available list. A selected row stays
  /// highlighted while this order still holds it.
  void _pruneHighlights(FulfilmentSession session) {
    final order = _orderById(session, widget.orderId);
    final good = order == null ? null : _goodById(order, widget.productId);
    if (good == null) return;
    _availableHighlight = _kept(
      _availableHighlight,
      _filterAvailable(_availableRows(session, good), _searchController.text),
    );
    _selectedHighlight = _kept(
      _selectedHighlight,
      _selectedRows(session, widget.orderId, widget.productId),
    );
  }

  bool _mutationsOpen(FulfilmentUiController controller) {
    return controller.phase == FulfilmentUiPhase.ready &&
        controller.canMutate &&
        !controller.commandInFlight &&
        !controller.refreshInFlight;
  }

  @override
  Widget build(BuildContext context) {
    final controller = FulfilmentScope.of(context);
    if (controller.phase != FulfilmentUiPhase.ready && _inlineError != null) {
      _inlineError = null;
    }
    final session = controller.session;
    if (controller.phase == FulfilmentUiPhase.ready && session != null) {
      _pruneHighlights(session);
    }
    final title = controller.phase == FulfilmentUiPhase.ready && session != null
        ? session.dataset.storeName
        : AppStrings.ordersScreenTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: switch (controller.phase) {
          FulfilmentUiPhase.loading => const _LoadingBody(),
          FulfilmentUiPhase.empty => _MessageBody(
            onRetry: controller.refreshInFlight ? null : () => _retry(context),
            refreshing: controller.refreshInFlight,
            child: const StatusMessage(
              key: Key('json-serial-empty'),
              icon: Icons.receipt_long_outlined,
              title: AppStrings.jsonEmptyTitle,
              message: AppStrings.jsonEmptyMessage,
            ),
          ),
          FulfilmentUiPhase.blocked => _BlockedBody(
            message: fulfilmentBlockedMessage(controller),
            refreshing: controller.refreshInFlight,
            onRetry: controller.commandInFlight || controller.refreshInFlight
                ? null
                : () => _retry(context),
          ),
          FulfilmentUiPhase.ready =>
            session == null
                ? _MessageBody(
                    onRetry: controller.refreshInFlight
                        ? null
                        : () => _retry(context),
                    refreshing: controller.refreshInFlight,
                    child: const StatusMessage(
                      key: Key('json-serial-empty'),
                      icon: Icons.receipt_long_outlined,
                      title: AppStrings.jsonEmptyTitle,
                      message: AppStrings.jsonEmptyMessage,
                    ),
                  )
                : _ReadySelection(
                    session: session,
                    orderId: widget.orderId,
                    productId: widget.productId,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                    inlineError: _inlineError,
                    mutationsOpen: _mutationsOpen(controller),
                    availableHighlight: _availableHighlight,
                    selectedHighlight: _selectedHighlight,
                    onAvailableTap: _onAvailableTap,
                    onSelectedTap: _onSelectedTap,
                    onAdd: (slot) => unawaited(_reserve(slot)),
                    onRemove: (slot) => unawaited(_release(slot)),
                  ),
        },
      ),
    );
  }
}

/// Reloads storage once. A build does not call this.
Future<void> _retry(BuildContext context) async {
  final controller = FulfilmentScope.read(context);
  try {
    await controller.refresh();
  } on Object {
    // operationError is already recorded. The blocked view explains it.
  }
}

class _ReadyLine {
  const _ReadyLine({
    required this.session,
    required this.good,
    required this.locked,
    required this.visible,
    required this.selected,
  });

  final FulfilmentSession session;
  final DatasetGood good;
  final bool locked;
  final List<_StockRow> visible;
  final List<_StockRow> selected;
}

class _ReadySelection extends StatelessWidget {
  const _ReadySelection({
    required this.session,
    required this.orderId,
    required this.productId,
    required this.searchController,
    required this.onSearchChanged,
    required this.inlineError,
    required this.mutationsOpen,
    required this.availableHighlight,
    required this.selectedHighlight,
    required this.onAvailableTap,
    required this.onSelectedTap,
    required this.onAdd,
    required this.onRemove,
  });

  final FulfilmentSession session;
  final String orderId;
  final String productId;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? inlineError;
  final bool mutationsOpen;
  final _Slot? availableHighlight;
  final _Slot? selectedHighlight;
  final ValueChanged<_Slot> onAvailableTap;
  final ValueChanged<_Slot> onSelectedTap;
  final ValueChanged<_Slot> onAdd;
  final ValueChanged<_Slot> onRemove;

  @override
  Widget build(BuildContext context) {
    final order = _orderById(session, orderId);
    if (order == null) {
      return const _MissingBody(
        title: AppStrings.jsonOrderNotFoundTitle,
        message: AppStrings.jsonOrderNotFoundMessage,
      );
    }
    final good = _goodById(order, productId);
    if (good == null) {
      return const _MissingBody(
        title: AppStrings.jsonGoodNotFoundTitle,
        message: AppStrings.jsonGoodNotFoundMessage,
      );
    }

    final available = _availableRows(session, good);
    final visible = _filterAvailable(available, searchController.text);
    final selected = _selectedRows(session, orderId, productId);
    final shownAvailable = _kept(availableHighlight, visible);
    final shownSelected = _kept(selectedHighlight, selected);

    final status = session.statusOf(orderId);
    final locked = _isLocked(status);
    final service = good.isServiceGood;
    final reserved = session.lineReservedQuantity(
      orderId: orderId,
      productId: productId,
    );
    final canAdd =
        mutationsOpen &&
        !locked &&
        !service &&
        reserved < good.quantity &&
        shownAvailable != null &&
        _quantityOf(visible, shownAvailable) > 0;
    final canRemove =
        mutationsOpen &&
        !locked &&
        !service &&
        shownSelected != null &&
        _quantityOf(selected, shownSelected) >= 1;
    final query = searchController.text.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > AppConstants.ordersMaxWidth
            ? AppConstants.ordersMaxWidth
            : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: LayoutBuilder(
                builder: (context, content) {
                  final wide =
                      content.maxWidth >= AppConstants.wideLayoutBreakpoint;
                  return Column(
                    key: const Key('json-serial-selection'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Summary(
                        good: good,
                        status: status,
                        reserved: reserved,
                        service: service,
                      ),
                      if (locked) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppStrings.jsonSerialOrderLocked,
                          key: const Key('json-serial-readonly'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('json-serial-search'),
                        controller: searchController,
                        onChanged: onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: AppStrings.serialSearchLabel,
                          hintText: AppStrings.serialSearchHint,
                          prefixIcon: Icon(Icons.qr_code_2_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _StockSection(
                          title: AppStrings.availableInventoryTitle,
                          wide: wide,
                          quantityLabel: AppStrings.availableQuantityLabel,
                          headerKey: const Key('json-serial-available-header'),
                          empty: _SectionMessage(
                            key: Key(
                              query.isNotEmpty && available.isNotEmpty
                                  ? 'json-serial-available-no-match'
                                  : 'json-serial-available-empty',
                            ),
                            message: query.isNotEmpty && available.isNotEmpty
                                ? AppStrings.serialNoMatch
                                : AppStrings.noAvailableInventory,
                          ),
                          rows: [
                            for (final row in visible)
                              _StockTile(
                                key: ValueKey((
                                  'json-available',
                                  row.address,
                                  row.serialNumber,
                                )),
                                quantityKey: ValueKey((
                                  'json-available-qty',
                                  row.address,
                                  row.serialNumber,
                                )),
                                row: row,
                                quantityLabel:
                                    AppStrings.availableQuantityLabel,
                                highlighted: shownAvailable == row.slot,
                                wide: wide,
                                onTap: () => onAvailableTap(row.slot),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _TransferButtons(
                        canAdd: canAdd,
                        canRemove: canRemove,
                        onAdd: () => onAdd(shownAvailable!),
                        onRemove: () => onRemove(shownSelected!),
                      ),
                      if (inlineError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          inlineError!,
                          key: const Key('json-serial-error'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.error),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Expanded(
                        child: _StockSection(
                          title: AppStrings.selectedSerialsTitle,
                          wide: wide,
                          quantityLabel: AppStrings.selectedQuantityLabel,
                          headerKey: const Key('json-serial-selected-header'),
                          empty: const _SectionMessage(
                            key: Key('json-serial-selected-empty'),
                            message: AppStrings.noSelectedSerials,
                          ),
                          rows: [
                            for (final row in selected)
                              _StockTile(
                                key: ValueKey((
                                  'json-selected',
                                  row.address,
                                  row.serialNumber,
                                )),
                                quantityKey: ValueKey((
                                  'json-selected-qty',
                                  row.address,
                                  row.serialNumber,
                                )),
                                row: row,
                                quantityLabel: AppStrings.selectedQuantityLabel,
                                highlighted: shownSelected == row.slot,
                                wide: wide,
                                onTap: () => onSelectedTap(row.slot),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.good,
    required this.status,
    required this.reserved,
    required this.service,
  });

  final DatasetGood good;
  final OrderStatus? status;
  final int reserved;
  final bool service;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parcelTtn = good.parcelTtn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status != null)
          Text(
            status!.label,
            key: const Key('json-serial-status'),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 4),
        Text(
          good.product,
          key: const Key('json-serial-product'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.productIdLabel,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          good.productId.literal,
          key: const Key('json-serial-product-id'),
          style: textTheme.bodyLarge,
        ),
        if (good.isParcel && parcelTtn != null) ...[
          const SizedBox(height: 4),
          Text(
            AppStrings.parcelGoodLabel,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '${AppStrings.parcelTtnLabel}: $parcelTtn',
            key: const Key('json-serial-parcel'),
            style: textTheme.bodyLarge,
          ),
        ],
        const SizedBox(height: 4),
        if (service)
          Text(
            AppStrings.serviceLineProgress,
            key: const Key('json-serial-service'),
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          )
        else ...[
          Text(
            '${AppStrings.requiredQuantityLabel}: ${good.quantity}',
            key: const Key('json-serial-required'),
          ),
          Text(
            AppStrings.selectedOfRequired(reserved, good.quantity),
            key: const Key('json-serial-progress'),
          ),
          Text(
            '${AppStrings.remainingQuantityLabel}: ${good.quantity - reserved}',
            key: const Key('json-serial-remaining'),
          ),
        ],
      ],
    );
  }
}

class _TransferButtons extends StatelessWidget {
  const _TransferButtons({
    required this.canAdd,
    required this.canRemove,
    required this.onAdd,
    required this.onRemove,
  });

  final bool canAdd;
  final bool canRemove;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('json-serial-add'),
            onPressed: canAdd ? onAdd : null,
            icon: const Icon(Icons.arrow_downward),
            label: const Text(AppStrings.addSerial),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('json-serial-remove'),
            onPressed: canRemove ? onRemove : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.arrow_upward),
            label: const Text(AppStrings.removeSerial),
          ),
        ),
      ],
    );
  }
}

class _StockSection extends StatelessWidget {
  const _StockSection({
    required this.title,
    required this.wide,
    required this.quantityLabel,
    required this.headerKey,
    required this.rows,
    required this.empty,
  });

  final String title;
  final bool wide;
  final String quantityLabel;
  final Key headerKey;
  final List<Widget> rows;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (wide && rows.isNotEmpty)
          _StockHeader(key: headerKey, quantityLabel: quantityLabel),
        Expanded(
          child: rows.isEmpty
              ? Center(child: empty)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: rows,
                ),
        ),
      ],
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _StockHeader extends StatelessWidget {
  const _StockHeader({super.key, required this.quantityLabel});

  final String quantityLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _StockColumns(
        address: AppStrings.addressLabel,
        serialNumber: AppStrings.serialNumberLabel,
        quantity: quantityLabel,
        style: style,
        maxLines: 2,
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({
    super.key,
    required this.quantityKey,
    required this.row,
    required this.quantityLabel,
    required this.highlighted,
    required this.wide,
    required this.onTap,
  });

  final Key quantityKey;
  final _StockRow row;
  final String quantityLabel;
  final bool highlighted;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? AppColors.primary.withValues(alpha: 0.12)
        : null;
    if (!wide) {
      return Card(
        color: color ?? AppColors.surface,
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StockField(AppStrings.addressLabel, row.address),
                _StockField(AppStrings.serialNumberLabel, row.serialNumber),
                _StockField(
                  quantityLabel,
                  '${row.quantity}',
                  valueKey: quantityKey,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: color ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: _StockColumns(
            address: row.address,
            serialNumber: row.serialNumber,
            quantity: '${row.quantity}',
            quantityKey: quantityKey,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _StockColumns extends StatelessWidget {
  const _StockColumns({
    required this.address,
    required this.serialNumber,
    required this.quantity,
    required this.style,
    this.quantityKey,
    this.maxLines = 1,
  });

  final String address;
  final String serialNumber;
  final String quantity;
  final TextStyle? style;
  final Key? quantityKey;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, int flex, {Key? key}) => Expanded(
      flex: flex,
      child: Text(
        text,
        key: key,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell(address, 3),
        cell(serialNumber, 4),
        cell(quantity, 2, key: quantityKey),
      ],
    );
  }
}

class _StockField extends StatelessWidget {
  const _StockField(this.label, this.valueText, {this.valueKey});

  final String label;
  final String valueText;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(valueText, key: valueKey, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        key: Key('json-serial-loading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(AppStrings.jsonLoading),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.child,
    required this.onRetry,
    required this.refreshing,
  });

  final Widget child;
  final VoidCallback? onRetry;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-serial-retry'),
              onPressed: onRetry,
              child: refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedBody extends StatelessWidget {
  const _BlockedBody({
    required this.message,
    required this.refreshing,
    required this.onRetry,
  });

  final String message;
  final bool refreshing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('json-serial-blocked'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              AppStrings.jsonBlockedTitle,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              key: const Key('json-serial-blocked-message'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-serial-retry'),
              onPressed: onRetry,
              child: refreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingBody extends StatelessWidget {
  const _MissingBody({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('json-serial-missing'),
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusMessage(
              icon: Icons.search_off,
              title: title,
              message: message,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('json-serial-missing-back'),
              onPressed: () {
                final navigator = Navigator.of(context);
                if (navigator.canPop()) navigator.pop();
              },
              child: const Text(AppStrings.jsonBackToOrders),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _Slot {
  const _Slot(this.address, this.serialNumber);

  final String address;
  final String serialNumber;

  @override
  bool operator ==(Object other) =>
      other is _Slot &&
      other.address == address &&
      other.serialNumber == serialNumber;

  @override
  int get hashCode => Object.hash(address, serialNumber);
}

@immutable
class _StockRow {
  const _StockRow({
    required this.address,
    required this.serialNumber,
    required this.quantity,
  });

  final String address;
  final String serialNumber;
  final int quantity;

  _Slot get slot => _Slot(address, serialNumber);
}

DatasetOrder? _orderById(FulfilmentSession session, String orderId) {
  for (final order in session.dataset.orders) {
    if (order.orderId == orderId) return order;
  }
  return null;
}

DatasetGood? _goodById(DatasetOrder order, String productId) {
  for (final good in order.goods) {
    if (good.productId.literal == productId) return good;
  }
  return null;
}

bool _isLocked(OrderStatus? status) =>
    status == OrderStatus.issued || status == OrderStatus.exported;

/// Available rows for [good], in dataset stock order.
///
/// Quantity comes from [FulfilmentSession.availableQuantity]. A row with
/// nothing free is omitted. A parcel keeps only its ParcelTTN.
List<_StockRow> _availableRows(FulfilmentSession session, DatasetGood good) {
  final productId = good.productId.literal;
  final rows = <_StockRow>[];
  for (final stock in session.dataset.stocks) {
    if (stock.productId.literal != productId) continue;
    if (good.isParcel && stock.serialNumber != good.parcelTtn) continue;
    final available = session.availableQuantity(
      productId: productId,
      address: stock.address,
      serialNumber: stock.serialNumber,
    );
    if (available == 0) continue;
    rows.add(
      _StockRow(
        address: stock.address,
        serialNumber: stock.serialNumber,
        quantity: available,
      ),
    );
  }
  return rows;
}

/// Slots this order line holds, in dataset stock order.
///
/// Quantity comes from [FulfilmentSession.slotReservedQuantity]. A slot
/// this line does not hold is omitted, including one whose free quantity
/// is already zero.
List<_StockRow> _selectedRows(
  FulfilmentSession session,
  String orderId,
  String productId,
) {
  final rows = <_StockRow>[];
  for (final stock in session.dataset.stocks) {
    if (stock.productId.literal != productId) continue;
    final reserved = session.slotReservedQuantity(
      orderId: orderId,
      productId: productId,
      address: stock.address,
      serialNumber: stock.serialNumber,
    );
    if (reserved == 0) continue;
    rows.add(
      _StockRow(
        address: stock.address,
        serialNumber: stock.serialNumber,
        quantity: reserved,
      ),
    );
  }
  return rows;
}

List<_StockRow> _filterAvailable(List<_StockRow> rows, String query) {
  final filtered = SerialSearch.filter([
    for (final row in rows)
      AvailableSerial(
        address: row.address,
        serialNumber: row.serialNumber,
        availableQuantity: row.quantity,
      ),
  ], query);
  return [
    for (final row in filtered)
      _StockRow(
        address: row.address,
        serialNumber: row.serialNumber,
        quantity: row.availableQuantity,
      ),
  ];
}

_Slot? _kept(_Slot? slot, List<_StockRow> rows) {
  if (slot == null) return null;
  for (final row in rows) {
    if (row.slot == slot) return slot;
  }
  return null;
}

int _quantityOf(List<_StockRow> rows, _Slot slot) {
  for (final row in rows) {
    if (row.slot == slot) return row.quantity;
  }
  return 0;
}

String? _reserveMessage(ReserveResult result) {
  return switch (result) {
    ReserveApplied() => null,
    InsufficientStock() => AppStrings.jsonSerialInsufficientStock,
    LineComplete() => AppStrings.jsonSerialLineComplete,
    ReserveRejected(:final reason) => switch (reason) {
      ReserveRejection.invalidQuantity => AppStrings.jsonSerialInvalidQuantity,
      ReserveRejection.unknownOrder => AppStrings.jsonOrderNotFoundMessage,
      ReserveRejection.unknownLine => AppStrings.jsonGoodNotFoundMessage,
      ReserveRejection.unknownStock => AppStrings.jsonSerialUnknownStock,
      ReserveRejection.parcelMismatch => AppStrings.jsonSerialParcelMismatch,
      ReserveRejection.serviceLine => AppStrings.jsonSerialServiceLine,
      ReserveRejection.orderLocked => AppStrings.jsonSerialOrderLocked,
    },
  };
}

String? _releaseMessage(RemoveUnitsResult result) {
  return switch (result) {
    UnitsRemoved() => null,
    RemoveUnitsRejected(:final reason) => switch (reason) {
      RemoveRejection.invalidQuantity => AppStrings.jsonSerialInvalidQuantity,
      RemoveRejection.unknownOrder => AppStrings.jsonOrderNotFoundMessage,
      RemoveRejection.unknownLine => AppStrings.jsonGoodNotFoundMessage,
      RemoveRejection.orderLocked => AppStrings.jsonSerialOrderLocked,
      RemoveRejection.insufficientReserved =>
        AppStrings.jsonSerialInsufficientReserved,
    },
  };
}
