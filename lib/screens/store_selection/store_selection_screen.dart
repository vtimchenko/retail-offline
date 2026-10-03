import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/store.dart';
import '../../repositories/session_data_repository.dart';
import '../../services/store_service.dart';
import '../../widgets/centered_content.dart';
import '../../widgets/status_message.dart';
import '../../widgets/store_search_field.dart';
import '../home/home_screen.dart';

/// First screen: lets the user pick the store they work in.
class StoreSelectionScreen extends StatefulWidget {
  const StoreSelectionScreen({
    super.key,
    this.storeService = const StoreService(),
    this.repository,
  });

  final StoreService storeService;

  /// Session data shared with the home screen. A new in-memory repository is
  /// created if none is provided.
  final SessionDataRepository? repository;

  @override
  State<StoreSelectionScreen> createState() => _StoreSelectionScreenState();
}

class _StoreSelectionScreenState extends State<StoreSelectionScreen> {
  late Future<List<Store>> _storesFuture;

  /// Selected store; lives only for the current session (not persisted).
  Store? _selectedStore;

  late final SessionDataRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? InMemorySessionDataRepository();
    _storesFuture = widget.storeService.loadStores();
  }

  void _reload() {
    setState(() {
      _selectedStore = null;
      _storesFuture = widget.storeService.loadStores();
    });
  }

  void _continue() {
    final store = _selectedStore;
    if (store == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(store: store, repository: _repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Store>>(
          future: _storesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _LoadingView();
            }
            if (snapshot.hasError) {
              return CenteredContent(
                child: StatusMessage(
                  icon: Icons.error_outline,
                  iconColor: AppColors.error,
                  title: AppStrings.storesErrorTitle,
                  message: AppStrings.storesErrorMessage,
                  actionLabel: AppStrings.retry,
                  onAction: _reload,
                ),
              );
            }
            final stores = snapshot.data ?? const <Store>[];
            if (stores.isEmpty) {
              return CenteredContent(
                child: StatusMessage(
                  icon: Icons.store_mall_directory_outlined,
                  title: AppStrings.storesEmptyTitle,
                  message: AppStrings.storesEmptyMessage,
                  actionLabel: AppStrings.retry,
                  onAction: _reload,
                ),
              );
            }
            return CenteredContent(
              child: _SelectionCard(
                stores: stores,
                selectedStore: _selectedStore,
                onChanged: (store) => setState(() => _selectedStore = store),
                onContinue: _selectedStore == null ? null : _continue,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            AppStrings.loadingStores,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.stores,
    required this.selectedStore,
    required this.onChanged,
    required this.onContinue,
  });

  final List<Store> stores;
  final Store? selectedStore;
  final ValueChanged<Store?> onChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
  child: Image.asset(
    'assets/images/store_selection.png',
    height: 120,
    fit: BoxFit.contain,
  ),
),
            const SizedBox(height: 20),
            Text(
              AppStrings.storeSelectionTitle,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.storeSelectionSubtitle,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            StoreSearchField(
              stores: stores,
              selectedStore: selectedStore,
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onContinue,
              child: const Text(AppStrings.continueButton),
            ),
          ],
        ),
      ),
    );
  }
}
