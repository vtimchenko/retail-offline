import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/store_selection/store_selection_screen.dart';

class RetailOfflineApp extends StatelessWidget {
  const RetailOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const StoreSelectionScreen(),
    );
  }
}
