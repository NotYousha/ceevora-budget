import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/admin_page.dart';
import '../../features/authentication/login_page.dart';
import '../../features/budget_approval/approval_page.dart';
import '../../features/budget_entry/budget_entry_page.dart';
import '../../features/budget_master/budget_master_page.dart';
import '../../features/budget_revision/revision_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/reports/daily_performance_page.dart';
import '../../features/reports/daily_pl_page.dart';
import '../../features/reports/reports_page.dart';
import '../security/session.dart';
import '../widgets/app_shell.dart';

class NavItem {
  final String path, label, permission;
  final IconData icon;
  const NavItem(this.path, this.label, this.icon, this.permission);
}

const navItems = [
  NavItem(
    '/dashboard',
    'nav_dashboard',
    Icons.dashboard_outlined,
    'DASHBOARD_VIEW',
  ),
  NavItem('/master', 'nav_master', Icons.folder_outlined, 'BUDGET_VIEW'),
  NavItem('/entry', 'nav_entry', Icons.grid_on, 'BUDGET_VIEW'),
  NavItem(
    '/approval',
    'nav_approval',
    Icons.fact_check_outlined,
    'BUDGET_VIEW',
  ),
  NavItem('/revision', 'nav_revision', Icons.edit_note, 'BUDGET_VIEW'),
  NavItem(
    '/daily-performance',
    'nav_daily_perf',
    Icons.today_outlined,
    'REPORT_VIEW',
  ),
  NavItem(
    '/daily-pl',
    'nav_daily_pl',
    Icons.receipt_long_outlined,
    'REPORT_VIEW',
  ),
  NavItem('/reports', 'nav_reports', Icons.assessment_outlined, 'REPORT_VIEW'),
  NavItem(
    '/admin',
    'nav_admin',
    Icons.admin_panel_settings_outlined,
    'ADMIN_CONFIG',
  ),
];

String homeFor(Session s) => navItems
    .firstWhere((n) => s.can(n.permission), orElse: () => navItems[1])
    .path;

class _SessionListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable();
  ref.listen(sessionProvider, (_, _) => refresh.ping());
  int? id(GoRouterState s) => int.tryParse(s.uri.queryParameters['id'] ?? '');
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      final atLogin = state.matchedLocation == '/login';
      if (s == null) return atLogin ? null : '/login';
      if (atLogin) return homeFor(s);
      final item = navItems
          .where((n) => state.matchedLocation.startsWith(n.path))
          .firstOrNull;
      if (item != null && !s.can(item.permission)) return homeFor(s);
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
          GoRoute(
            path: '/master',
            builder: (_, s) =>
                BudgetMasterPage(key: ValueKey(s.uri), budgetId: id(s)),
          ),
          GoRoute(
            path: '/entry',
            builder: (_, s) =>
                BudgetEntryPage(key: ValueKey(s.uri), budgetId: id(s)),
          ),
          GoRoute(path: '/approval', builder: (_, _) => const ApprovalPage()),
          GoRoute(
            path: '/revision',
            builder: (_, s) =>
                RevisionPage(key: ValueKey(s.uri), budgetId: id(s)),
          ),
          GoRoute(
            path: '/daily-performance',
            builder: (_, _) => const DailyPerformancePage(),
          ),
          GoRoute(path: '/daily-pl', builder: (_, _) => const DailyPlPage()),
          GoRoute(
            path: '/reports',
            builder: (_, s) =>
                ReportsPage(initialCode: s.uri.queryParameters['code']),
          ),
          GoRoute(path: '/admin', builder: (_, _) => const AdminPage()),
        ],
      ),
    ],
  );
});
