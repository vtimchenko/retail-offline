import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF00A046);
  static const Color primaryDark = Color(0xFF008A3C);
  static const Color background = Color(0xFFF1F3F4);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color border = Color(0xFFD5D9DD);
  static const Color error = Color(0xFFD32F2F);

  /// Light amber row/card for an order that has a partial serial selection.
  static const Color orderStatusInProgressBackground = Color(0xFFFFF6E0);
  static const Color orderStatusInProgressForeground = Color(0xFF8D6E00);

  /// Light green row/card for an order whose serials are complete.
  static const Color orderStatusReadyBackground = Color(0xFFE7F6EC);
  static const Color orderStatusReadyForeground = primaryDark;

  /// Light blue row/card for an order with a current Excel file.
  static const Color orderStatusFileReadyBackground = Color(0xFFE7F1FB);
  static const Color orderStatusFileReadyForeground = Color(0xFF0D47A1);
}
