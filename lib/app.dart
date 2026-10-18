import 'package:flutter/material.dart';

import 'application/fulfilment_scope.dart';
import 'application/fulfilment_tab_coordinator.dart';
import 'application/fulfilment_ui_controller.dart';
import 'application/page_visibility.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'persistence/fulfilment_repository.dart';
import 'persistence/indexeddb/indexeddb_fulfilment_repository.dart';
import 'persistence/indexeddb/indexeddb_fulfilment_schema.dart';
import 'screens/json_import/json_import_screen.dart';

/// Owns one fulfilment controller for the process and shows JSON import.
///
/// The controller is created in [State.initState] and disposed with the
/// state. [FulfilmentScope] sits above [MaterialApp], so pushed routes can
/// see it.
class RetailOfflineApp extends StatefulWidget {
  /// Creates the production app.
  ///
  /// [repository], [databaseName], [transport], and [visibility] replace the
  /// IndexedDB and browser defaults in tests. A null [databaseName] uses
  /// [IndexedDbFulfilmentSchema.productionDatabaseName] for both the
  /// repository and the controller.
  const RetailOfflineApp({
    super.key,
    this.repository,
    this.databaseName,
    this.transport,
    this.visibility,
  });

  /// Storage for the fulfilment controller.
  ///
  /// Production uses [IndexedDbFulfilmentRepository].
  final FulfilmentRepository? repository;

  /// IndexedDB name shared by the repository and the cross-tab channel.
  final String? databaseName;

  /// Replaces the browser notice channel in tests.
  final StorageChangeTransport? transport;

  /// Replaces browser page visibility in tests.
  final PageVisibility? visibility;

  @override
  State<RetailOfflineApp> createState() => _RetailOfflineAppState();
}

class _RetailOfflineAppState extends State<RetailOfflineApp> {
  late final FulfilmentUiController _controller;

  @override
  void initState() {
    super.initState();
    final databaseName =
        widget.databaseName ?? IndexedDbFulfilmentSchema.productionDatabaseName;
    _controller = FulfilmentUiController.open(
      repository:
          widget.repository ??
          IndexedDbFulfilmentRepository(databaseName: databaseName),
      databaseName: databaseName,
      transport: widget.transport,
      visibility: widget.visibility,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FulfilmentScope(
      controller: _controller,
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const JsonImportScreen(),
      ),
    );
  }
}
