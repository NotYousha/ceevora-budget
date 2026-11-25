import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/budget_repository.dart';

/// Lookup and read providers. Screens call `ref.invalidate(...)` after writes so data refreshes.
final branchesProvider = FutureProvider<List<Branch>>(
  (ref) => ref.watch(repoProvider).branches(),
);
final yearsProvider = FutureProvider<List<int>>(
  (ref) => ref.watch(repoProvider).years(),
);
final periodsProvider = FutureProvider.family<List<Period>, int>(
  (ref, y) => ref.watch(repoProvider).periods(y),
);
final glAccountsProvider = FutureProvider<List<GlAccount>>(
  (ref) => ref.watch(repoProvider).glAccounts(),
);

typedef SearchArgs = ({String? q, int? year, String? status, int page});
final budgetSearchProvider =
    FutureProvider.family<({List<Budget> items, int total}), SearchArgs>(
      (ref, a) => ref
          .watch(repoProvider)
          .search(q: a.q, year: a.year, status: a.status, page: a.page),
    );

final budgetProvider = FutureProvider.family<Budget, int>(
  (ref, id) => ref.watch(repoProvider).get(id),
);
final entryProvider =
    FutureProvider.family<BudgetEntry, ({int budget, int branch})>(
      (ref, a) => ref.watch(repoProvider).entry(a.budget, a.branch),
    );
final summaryProvider = FutureProvider.family<Json, int>(
  (ref, id) => ref.watch(repoProvider).summary(id),
);
final approvalHistoryProvider =
    FutureProvider.family<List<ApprovalHistory>, ({int budget, int? version})>(
      (ref, a) =>
          ref.watch(repoProvider).approvalHistory(a.budget, version: a.version),
    );
final revisionHistoryProvider =
    FutureProvider.family<
      List<RevisionHistory>,
      ({int budget, int? version, String? status})
    >(
      (ref, a) => ref
          .watch(repoProvider)
          .revisionHistory(a.budget, version: a.version, status: a.status),
    );

/// Query maps are converted to a stable string key so identical filters share one cached request.
final dashboardProvider = FutureProvider.family<Json, String>(
  (ref, q) => ref.watch(repoProvider).dashboard(_decode(q)),
);
final dailyPerfProvider = FutureProvider.family<Json, String>(
  (ref, q) => ref.watch(repoProvider).dailyPerformance(_decode(q)),
);
final dailyPlProvider = FutureProvider.family<Json, String>(
  (ref, q) => ref.watch(repoProvider).dailyPl(_decode(q)),
);
final reportProvider = FutureProvider.family<ReportData, (String, String)>(
  (ref, a) => ref.watch(repoProvider).report(a.$1, _decode(a.$2)),
);

String queryKey(Map<String, Object?> q) =>
    (q.entries
            .where((e) => e.value != null)
            .map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}')
            .toList()
          ..sort())
        .join('&');
Json _decode(String key) => key.isEmpty ? {} : Uri.splitQueryString(key);
