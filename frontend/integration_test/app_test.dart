// End-to-end smoke test against a RUNNING backend with the demo tenant.
//   backend:  python -m uvicorn app.main:app --port 8000   (DEMO tenant seeded)
//   run:      flutter test integration_test -d windows
//             (web: flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome)
import 'package:ceevora_budget/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('finance manager signs in and sees reconciled January figures', (
    t,
  ) async {
    await initializeDateFormatting('en');
    await t.pumpWidget(const ProviderScope(child: CeevoraBudgetApp()));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('username')), 'fmanager');
    await t.enterText(find.byKey(const Key('password')), 'Demo@2027');
    await t.tap(find.text('Sign in').last);
    await t.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Net Sales'), findsWidgets);

    await t.tap(find.text('Management Reports'));
    await t.pumpAndSettle(const Duration(seconds: 3));
    // Default report = R01, Monthly, January 2027: total budget 450,000 / actual 440,000
    expect(find.text('450,000.00'), findsWidgets);
    expect(find.text('440,000.00'), findsWidgets);
  });
}
