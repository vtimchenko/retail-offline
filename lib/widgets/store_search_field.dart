import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../models/store.dart';

/// Searchable dropdown (autocomplete) for choosing a [Store].
///
/// [onChanged] is called with the chosen store, or `null` when the selection
/// is cleared (including when the user edits the text after choosing).
class StoreSearchField extends StatefulWidget {
  const StoreSearchField({
    super.key,
    required this.stores,
    required this.selectedStore,
    required this.onChanged,
  });

  final List<Store> stores;
  final Store? selectedStore;
  final ValueChanged<Store?> onChanged;

  @override
  State<StoreSearchField> createState() => _StoreSearchFieldState();
}

class _StoreSearchFieldState extends State<StoreSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _noMatches = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<Store> _options(TextEditingValue value) {
    final query = value.text;
    final selected = widget.selectedStore;
    // Show the full list when empty or when the text is the chosen store name.
    final showAll =
        query.trim().isEmpty ||
        (selected != null && selected.nameStore == query);
    final result = showAll
        ? widget.stores
        : widget.stores.where((s) => s.matches(query));
    final noMatches = result.isEmpty;
    if (noMatches != _noMatches) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _noMatches = noMatches);
      });
    }
    return result;
  }

  void _onTextChanged(String text) {
    final selected = widget.selectedStore;
    if (selected != null && selected.nameStore != text) {
      widget.onChanged(null);
    }
    setState(() {});
  }

  void _select(Store store) {
    _controller.text = store.nameStore;
    _controller.selection = TextSelection.collapsed(
      offset: store.nameStore.length,
    );
    widget.onChanged(store);
    _focusNode.unfocus();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged(null);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedStore;
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<Store>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: (store) => store.nameStore,
          optionsBuilder: _options,
          onSelected: _select,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: _onTextChanged,
              onSubmitted: (_) => onSubmitted(),
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: AppStrings.storeFieldLabel,
                hintText: AppStrings.storeFieldHint,
                helperText: _noMatches ? null : ' ',
                errorText: _noMatches ? AppStrings.storeNotFound : null,
                prefixIcon: Icon(
                  selected != null ? Icons.check_circle : Icons.search,
                  color: selected != null
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                suffixIcon: controller.text.isEmpty
                    ? const Icon(Icons.arrow_drop_down)
                    : IconButton(
                        tooltip: AppStrings.clear,
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
                enabledBorder: selected != null
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      )
                    : null,
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return _OptionsList(
              width: constraints.maxWidth,
              options: options.toList(growable: false),
              onSelected: onSelected,
            );
          },
        );
      },
    );
  }
}

class _OptionsList extends StatelessWidget {
  const _OptionsList({
    required this.width,
    required this.options,
    required this.onSelected,
  });

  final double width;
  final List<Store> options;
  final AutocompleteOnSelected<Store> onSelected;

  @override
  Widget build(BuildContext context) {
    final highlighted = AutocompleteHighlightedOption.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 280),
          child: SizedBox(
            width: width,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final store = options[index];
                return ListTile(
                  title: Text(store.nameStore),
                  selected: index == highlighted,
                  selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
                  selectedColor: AppColors.primaryDark,
                  onTap: () => onSelected(store),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
