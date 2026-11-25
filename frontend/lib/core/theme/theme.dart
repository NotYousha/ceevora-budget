import 'package:material_ui/material_ui.dart';

class AppColors {
  static const navy = Color(0xFF14284B);
  static const navyLight = Color(0xFF1F3A68);
  static const teal = Color(0xFF00897B);
  static const favourable = Color(0xFF2E7D32);
  static const unfavourable = Color(0xFFC62828);
  static const warning = Color(0xFFEF6C00);
  static const grid = Color(0xFFE0E4EA);
  static const header = Color(0xFFF1F4F8);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    primary: AppColors.teal,
    surface: Colors.white,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      elevation: 0,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppColors.header),
    ),
  );
}
