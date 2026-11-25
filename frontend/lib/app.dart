import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/routing/router.dart';
import 'core/security/session.dart';
import 'core/theme/theme.dart';

class CeevoraBudgetApp extends ConsumerWidget {
  const CeevoraBudgetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Ceevora Budget',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar')],
      // Arabic switches the whole app to right-to-left through these delegates.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
