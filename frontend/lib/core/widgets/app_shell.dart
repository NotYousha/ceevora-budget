import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../localization/strings.dart';
import '../routing/router.dart';
import '../security/session.dart';
import '../theme/theme.dart';

/// Navy navigation + white content. Collapses to a drawer on narrow (web/mobile) widths.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    if (s == null) return const SizedBox.shrink();
    final location = GoRouterState.of(context).matchedLocation;
    final items = navItems.where((n) => s.can(n.permission)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final nav = Material(
      color: AppColors.navy,
      child: SizedBox(
        width: 240,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                wide
                    ? context.tr('app_title')
                    : '${context.tr('app_title')}\n${s.user.fullName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final n in items)
              ListTile(
                leading: Icon(n.icon, color: Colors.white70),
                title: Text(
                  context.tr(n.label),
                  style: const TextStyle(color: Colors.white),
                ),
                selected: location.startsWith(n.path),
                selectedTileColor: AppColors.navyLight,
                onTap: () {
                  if (!wide) Navigator.of(context).maybePop();
                  context.go(n.path);
                },
              ),
          ],
        ),
      ),
    );
    return Scaffold(
      drawer: wide ? null : Drawer(child: nav),
      appBar: AppBar(
        backgroundColor: wide ? Colors.white : AppColors.navy,
        foregroundColor: wide ? AppColors.navy : Colors.white,
        automaticallyImplyLeading: !wide,
        title: Text(
          ar(context) && s.company.nameAr != null
              ? s.company.nameAr!
              : s.company.name,
        ),
        actions: [
          TextButton(
            onPressed: () => ref.read(localeProvider.notifier).toggle(),
            child: Text(context.tr('language')),
          ),
          if (MediaQuery.sizeOf(context).width >= 700)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text('${s.user.fullName} (${s.user.role})')),
            ),
          IconButton(
            tooltip: context.tr('logout'),
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide) nav,
          Expanded(child: child),
        ],
      ),
    );
  }

  static bool ar(BuildContext c) => c.isArabic;
}
