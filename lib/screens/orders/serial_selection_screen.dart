import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/inventory_balance.dart';
import '../../models/order.dart';
import '../../models/serial_selection.dart';
import '../../models/store.dart';
import '../../repositories/serial_selection_repository.dart';
import 'serial_search.dart';

/// Reserves inventory serials for one order line.
///
/// [OrderItem.productId] stays on the model and is not shown.
class SerialSelectionScreen extends StatefulWidget {
  const SerialSelectionScreen({
    super.key,
    required this.store,
    required this.orderNumber,
    required this.item,
    required this.inventory,
    required this.selections,
  });

  final Store store;
  final String orderNumber;
  final OrderItem item;

  /// Inventory rows used to compute stock. Only rows for [item] are shown.
  final List<InventoryBalance> inventory;
  final SerialSelectionRepository selections;

  @override
  State<SerialSelectionScreen> createState() => _SerialSelectionScreenState();
}

class _SerialSelectionScreenState extends State<SerialSelectionScreen> {
  /// Desktop second click. Touch keeps a single tap instant: InkWell's
  /// double-tap recognizer would delay every highlight.
  static const _doubleTapWindow = Duration(milliseconds: 300);

  final TextEditingController _searchController = TextEditingController();

  InventorySlot? _availableSlot;
  InventorySlot? _selectedSlot;
  InventorySlot? _availableTapSlot;
  InventorySlot? _selectedTapSlot;
  DateTime? _availableTapAt;
  DateTime? _selectedTapAt;

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

  InventorySlot _slot(String address, String serialNumber) => InventorySlot(
    productId: widget.item.productId,
    address: address,
    serialNumber: serialNumber,
  );

  List<AvailableSerial> _allAvailable() => widget.selections.availableFor(
    productId: widget.item.productId,
    inventory: widget.inventory,
  );

  List<AvailableSerial> _visibleAvailable() =>
      SerialSearch.filter(_allAvailable(), _searchController.text);

  bool _availableVisible(InventorySlot slot) => _visibleAvailable().any(
    (row) =>
        row.address == slot.address && row.serialNumber == slot.serialNumber,
  );

  bool _canAdd(InventorySlot? slot) {
    if (slot == null || !_availableVisible(slot)) return false;
    if (widget.selections.selectedQuantity(
          widget.orderNumber,
          widget.item.productId,
        ) >=
        widget.item.quantity) {
      return false;
    }
    for (final row in _visibleAvailable()) {
      if (row.address == slot.address &&
          row.serialNumber == slot.serialNumber) {
        return row.availableQuantity >= 1;
      }
    }
    return false;
  }

  bool _canRemove(InventorySlot? slot) {
    if (slot == null) return false;
    for (final row in widget.selections.selectedFor(
      orderNumber: widget.orderNumber,
      productId: widget.item.productId,
    )) {
      if (row.address == slot.address &&
          row.serialNumber == slot.serialNumber) {
        return row.quantity >= 1;
      }
    }
    return false;
  }

  void _onSearchChanged(String _) {
    setState(() {
      final slot = _availableSlot;
      if (slot != null && !_availableVisible(slot)) _availableSlot = null;
    });
  }

  void _add(InventorySlot slot) {
    widget.selections.addOne(
      orderNumber: widget.orderNumber,
      productId: widget.item.productId,
      address: slot.address,
      serialNumber: slot.serialNumber,
      inventory: widget.inventory,
      requiredQuantity: widget.item.quantity,
    );
    setState(() {
      _availableSlot = _availableVisible(slot) ? slot : null;
    });
  }

  void _remove(InventorySlot slot) {
    widget.selections.removeOne(
      orderNumber: widget.orderNumber,
      productId: widget.item.productId,
      address: slot.address,
      serialNumber: slot.serialNumber,
    );
    final stillSelected = widget.selections
        .selectedFor(
          orderNumber: widget.orderNumber,
          productId: widget.item.productId,
        )
        .any(
          (row) =>
              row.address == slot.address &&
              row.serialNumber == slot.serialNumber,
        );
    setState(() => _selectedSlot = stillSelected ? slot : null);
  }

  void _onAvailableTap(InventorySlot slot) {
    if (_isDoubleTap(slot, _availableTapSlot, _availableTapAt)) {
      _availableTapSlot = null;
      _availableTapAt = null;
      _add(slot);
      return;
    }
    _availableTapSlot = slot;
    _availableTapAt = DateTime.now();
    setState(() => _availableSlot = slot);
  }

  void _onSelectedTap(InventorySlot slot) {
    if (_isDoubleTap(slot, _selectedTapSlot, _selectedTapAt)) {
      _selectedTapSlot = null;
      _selectedTapAt = null;
      _remove(slot);
      return;
    }
    _selectedTapSlot = slot;
    _selectedTapAt = DateTime.now();
    setState(() => _selectedSlot = slot);
  }

  bool _isDoubleTap(InventorySlot slot, InventorySlot? previous, DateTime? at) {
    if (!_doubleClick || previous != slot || at == null) return false;
    return DateTime.now().difference(at) <= _doubleTapWindow;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selections.selectedQuantity(
      widget.orderNumber,
      widget.item.productId,
    );
    final allAvailable = _allAvailable();
    final visible = _visibleAvailable();
    final selectedRows = widget.selections.selectedFor(
      orderNumber: widget.orderNumber,
      productId: widget.item.productId,
    );
    final query = _searchController.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(widget.store.nameStore)),
      body: SafeArea(
        child: LayoutBuilder(
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Summary(
                            product: widget.item.product,
                            requiredQuantity: widget.item.quantity,
                            selectedQuantity: selected,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('serial-search'),
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              labelText: AppStrings.serialSearchLabel,
                              hintText: AppStrings.serialSearchHint,
                              prefixIcon: Icon(Icons.qr_code_2_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _SerialSection(
                              title: AppStrings.availableInventoryTitle,
                              wide: wide,
                              quantityLabel: AppStrings.availableQuantityLabel,
                              headerKey: const Key('available-header'),
                              empty: _SectionMessage(
                                key: Key(
                                  query.isNotEmpty && allAvailable.isNotEmpty
                                      ? 'serial-available-no-match'
                                      : 'serial-available-empty',
                                ),
                                message:
                                    query.isNotEmpty && allAvailable.isNotEmpty
                                    ? AppStrings.serialNoMatch
                                    : AppStrings.noAvailableInventory,
                              ),
                              rows: [
                                for (final row in visible)
                                  _SerialRow(
                                    key: ValueKey((
                                      'available',
                                      row.address,
                                      row.serialNumber,
                                    )),
                                    address: row.address,
                                    serialNumber: row.serialNumber,
                                    quantity: row.availableQuantity,
                                    quantityLabel:
                                        AppStrings.availableQuantityLabel,
                                    highlighted: _highlights(
                                      _availableSlot,
                                      row.address,
                                      row.serialNumber,
                                    ),
                                    wide: wide,
                                    onTap: () => _onAvailableTap(
                                      _slot(row.address, row.serialNumber),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TransferButtons(
                            canAdd: _canAdd(_availableSlot),
                            canRemove: _canRemove(_selectedSlot),
                            onAdd: () => _add(_availableSlot!),
                            onRemove: () => _remove(_selectedSlot!),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _SerialSection(
                              title: AppStrings.selectedSerialsTitle,
                              wide: wide,
                              quantityLabel: AppStrings.selectedQuantityLabel,
                              headerKey: const Key('selected-header'),
                              empty: const _SectionMessage(
                                key: Key('serial-selected-empty'),
                                message: AppStrings.noSelectedSerials,
                              ),
                              rows: [
                                for (final row in selectedRows)
                                  _SerialRow(
                                    key: ValueKey((
                                      'selected',
                                      row.address,
                                      row.serialNumber,
                                    )),
                                    address: row.address,
                                    serialNumber: row.serialNumber,
                                    quantity: row.quantity,
                                    quantityLabel:
                                        AppStrings.selectedQuantityLabel,
                                    highlighted: _highlights(
                                      _selectedSlot,
                                      row.address,
                                      row.serialNumber,
                                    ),
                                    wide: wide,
                                    onTap: () => _onSelectedTap(
                                      _slot(row.address, row.serialNumber),
                                    ),
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
        ),
      ),
    );
  }

  bool _highlights(InventorySlot? slot, String address, String serialNumber) =>
      slot != null &&
      slot.address == address &&
      slot.serialNumber == serialNumber;
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.product,
    required this.requiredQuantity,
    required this.selectedQuantity,
  });

  final String product;
  final int requiredQuantity;
  final int selectedQuantity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('${AppStrings.requiredQuantityLabel}: $requiredQuantity'),
        Text(AppStrings.selectedOfRequired(selectedQuantity, requiredQuantity)),
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
            key: const Key('add-serial'),
            onPressed: canAdd ? onAdd : null,
            icon: const Icon(Icons.arrow_downward),
            label: const Text(AppStrings.addSerial),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('remove-serial'),
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

class _SerialSection extends StatelessWidget {
  const _SerialSection({
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
          _SerialHeader(key: headerKey, quantityLabel: quantityLabel),
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

class _SerialHeader extends StatelessWidget {
  const _SerialHeader({super.key, required this.quantityLabel});

  final String quantityLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _SerialColumns(
        address: AppStrings.addressLabel,
        serialNumber: AppStrings.serialNumberLabel,
        quantity: quantityLabel,
        style: style,
        maxLines: 2,
      ),
    );
  }
}

class _SerialRow extends StatelessWidget {
  const _SerialRow({
    super.key,
    required this.address,
    required this.serialNumber,
    required this.quantity,
    required this.quantityLabel,
    required this.highlighted,
    required this.wide,
    required this.onTap,
  });

  final String address;
  final String serialNumber;
  final int quantity;
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
                _SerialField(AppStrings.addressLabel, address),
                _SerialField(AppStrings.serialNumberLabel, serialNumber),
                _SerialField(quantityLabel, '$quantity'),
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
          child: _SerialColumns(
            address: address,
            serialNumber: serialNumber,
            quantity: '$quantity',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _SerialColumns extends StatelessWidget {
  const _SerialColumns({
    required this.address,
    required this.serialNumber,
    required this.quantity,
    required this.style,
    this.maxLines = 1,
  });

  final String address;
  final String serialNumber;
  final String quantity;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, int flex) => Expanded(
      flex: flex,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [cell(address, 3), cell(serialNumber, 4), cell(quantity, 2)],
    );
  }
}

class _SerialField extends StatelessWidget {
  const _SerialField(this.label, this.value);

  final String label;
  final String value;

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
          Text(value, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}
