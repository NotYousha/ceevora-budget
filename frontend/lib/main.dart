import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  await initializeDateFormatting('ar');
  // retry: null -> failed API calls surface immediately instead of being silently retried.
  runApp(ProviderScope(retry: (_, _) => null, child: const CeevoraBudgetApp()));
}
