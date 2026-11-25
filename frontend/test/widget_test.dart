import 'package:ceevora_budget/app.dart';
import 'package:ceevora_budget/core/security/session.dart';
import 'package:ceevora_budget/features/budget_approval/approval_page.dart';
import 'package:ceevora_budget/features/budget_master/budget_master_page.dart';
import 'package:ceevora_budget/shared/models/models.dart';
import 'package:ceevora_budget/shared/repositories/budget_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_repo.dart';

Future<ProviderContainer> pumpApp(WidgetTester t, FakeRepo repo) async {
  t.view.physicalSize = const Size(1600, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [repoProvider.overrideWithValue(repo)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CeevoraBudgetApp(),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  testWidgets(
    'login validates, rejects bad password, then opens the dashboard',
    (t) async {
      final repo = FakeRepo();
      final c = await pumpApp(t, repo);
      await t.tap(find.text('Sign in').last);
      await t.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(2));

      await t.enterText(find.byKey(const Key('username')), 'fmanager');
      await t.enterText(find.byKey(const Key('password')), 'wrong');
      await t.tap(find.text('Sign in').last);
      await t.pumpAndSettle();
      expect(find.text('Invalid tenant, username or password'), findsOneWidget);
      expect(c.read(sessionProvider), isNull);

      await t.enterText(find.byKey(const Key('password')), 'Demo@2027');
      await t.tap(find.text('Sign in').last);
      await t.pumpAndSettle();
      expect(repo.calls.last, 'login:DEMO:fmanager');
      expect(c.read(sessionProvider)!.user.username, 'fmanager');
      expect(find.text('Net Sales'), findsWidgets); // dashboard KPI card
      expect(find.text('440,000.00'), findsWidgets);
      expect(find.textContaining('PROVISIONAL'), findsOneWidget);
      // Accountant-only screens are hidden for a finance manager
      expect(find.text('Administration'), findsNothing);
    },
  );

  testWidgets('Arabic switches the layout to right-to-left', (t) async {
    final c = await pumpApp(t, FakeRepo());
    await t.tap(find.text('العربية'));
    await t.pumpAndSettle();
    expect(c.read(localeProvider), 'ar');
    expect(
      Directionality.of(t.element(find.text('تسجيل الدخول').last)),
      TextDirection.rtl,
    );
  });

  testWidgets('approval: reject needs remarks and sends them', (t) async {
    final repo = FakeRepo();
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final container = ProviderContainer(
      overrides: [repoProvider.overrideWithValue(repo)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .signIn(
          Session(
            't',
            DateTime(2099),
            AppUser.fromJson(loginJson['user'] as Json),
            Company.fromJson(loginJson['company'] as Json),
          ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ApprovalPage())),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('BUD-2028-001'), findsOneWidget);
    await t.tap(find.text('BUD-2028-001'));
    await t.pumpAndSettle();
    expect(find.text('Company Total'), findsOneWidget);
    expect(find.text('200,000.00'), findsWidgets);

    await t.tap(find.text('Reject'));
    // The Reject button shows a busy spinner while the dialog is open, so pump fixed frames.
    await t.pump(const Duration(milliseconds: 500));
    final ok = find.widgetWithText(FilledButton, 'OK');
    expect(t.widget<FilledButton>(ok).onPressed, isNull); // remarks required
    await t.enterText(find.byType(TextField).last, 'Add expenses');
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(ok);
    await t.pumpAndSettle();
    expect(repo.calls, contains('reject:1:3:Add expenses'));
  });

  testWidgets('new budget defaults currency to the company currency', (
    t,
  ) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final container = ProviderContainer(
      overrides: [repoProvider.overrideWithValue(FakeRepo())],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .signIn(
          Session(
            't',
            DateTime(2099),
            AppUser.fromJson(loginJson['user'] as Json),
            Company.fromJson(loginJson['company'] as Json),
          ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BudgetMasterPage())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'SAR'), findsOneWidget);
  });

  testWidgets(
    'phone screen (390x844): login, dashboard and master render without overflow',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final container = ProviderContainer(
        overrides: [repoProvider.overrideWithValue(FakeRepo())],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CeevoraBudgetApp(),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('username')), 'fmanager');
      await t.enterText(find.byKey(const Key('password')), 'Demo@2027');
      await t.tap(find.text('Sign in').last);
      await t.pumpAndSettle();
      expect(find.text('Net Sales'), findsWidgets);
      expect(
        find.text('Faisal (FINANCE_MANAGER)'),
        findsNothing,
      ); // name moves into the drawer on phones
      await t.tap(find.byTooltip('Open navigation menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Budget Master'));
      await t.pumpAndSettle();
      expect(
        find.text('Fill the header and press Save to create a budget.'),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Open navigation menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Approval'));
      await t.pumpAndSettle();
      expect(find.text('BUD-2028-001'), findsOneWidget);
    },
  );
}
