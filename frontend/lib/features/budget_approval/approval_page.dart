import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/security/session.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/repositories/budget_repository.dart';
import '../budget_history/history_dialog.dart';

/// Screen 03 - Budget Approval: submitted budgets with branch and company summaries.
class ApprovalPage extends ConsumerStatefulWidget {
  const ApprovalPage({super.key});
  @override
  ConsumerState<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends ConsumerState<ApprovalPage> {
  static const _args = (q: null, year: null, status: 'SUBMITTED', page: 1);
  Budget? _sel;

  void _refresh() {
    ref.invalidate(budgetSearchProvider);
    if (_sel != null) ref.invalidate(summaryProvider(_sel!.id));
  }

  Future<void> _approve() async {
    if (!await confirmDialog(context, context.tr('confirm_approve'))) return;
    await ref.read(repoProvider).approve(_sel!.id, _sel!.rowVersion);
    setState(() => _sel = null);
    _refresh();
  }

  Future<void> _reject() async {
    final reason = await reasonDialog(context, context.tr('reject'));
    if (reason == null) return;
    await ref.read(repoProvider).reject(_sel!.id, _sel!.rowVersion, reason);
    setState(() => _sel = null);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final list = ref.watch(budgetSearchProvider(_args));
    final canApprove = s.can('BUDGET_APPROVE') && _sel != null;
    return PageFrame(
      title: context.tr('nav_approval'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility, size: 18),
          label: Text(context.tr('view_details')),
          onPressed: _sel == null
              ? null
              : () => context.go('/entry?id=${_sel!.id}'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.history, size: 18),
          label: Text(context.tr('view_history')),
          onPressed: _sel == null
              ? null
              : () => showHistoryDialog(context, _sel!),
        ),
        BusyButton(
          label: context.tr('approve'),
          icon: Icons.check_circle,
          filled: true,
          onPressed: canApprove ? _approve : null,
        ),
        BusyButton(
          label: context.tr('reject'),
          icon: Icons.cancel,
          onPressed: canApprove ? _reject : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('refresh')),
          onPressed: _refresh,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: Text(context.tr('close')),
          onPressed: () => setState(() => _sel = null),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('submitted_budgets'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(
            height: 200,
            child: AsyncView(
              value: list,
              isEmpty: (r) => r.items.isEmpty,
              onRetry: _refresh,
              builder: (r) => DataGrid(
                headers: [
                  context.tr('budget_no'),
                  context.tr('budget_name'),
                  context.tr('fin_year'),
                  context.tr('status'),
                  context.tr('created_by'),
                ],
                numeric: const [false, false, false, false, false],
                selected: {
                  for (var i = 0; i < r.items.length; i++)
                    if (r.items[i].id == _sel?.id) i,
                },
                onSelect: (i, v) =>
                    setState(() => _sel = v ? r.items[i] : null),
                rows: [
                  for (final b in r.items)
                    [
                      Text(b.budgetNo),
                      Text(b.budgetName),
                      Text('${b.finYear}'),
                      StatusChip(b.status),
                      Text(b.createdBy),
                    ],
                ],
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: _sel == null
                ? Center(child: Text(context.tr('select_budget')))
                : _summary(_sel!),
          ),
        ],
      ),
    );
  }

  Widget _summary(Budget b) {
    final ar = context.isArabic;
    const keys = [
      'GROSS_SALES',
      'DISCOUNTS',
      'RETURNS',
      'NET_SALES',
      'COGS',
      'GROSS_PROFIT',
      'OPEX',
      'OPERATING_PROFIT',
    ];
    return AsyncView(
      value: ref.watch(summaryProvider(b.id)),
      builder: (j) {
        final rows = List<Json>.from(j['branches']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${context.tr('budget_summary')} - ${b.budgetNo} (${b.currency})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Expanded(
              child: DataGrid(
                headers: [context.tr('branch'), ...keys.map(context.tr)],
                numeric: [false, ...keys.map((_) => true)],
                rows: [
                  for (final r in rows)
                    [
                      Text(
                        ar
                            ? r['branch_name_ar'] ?? r['branch_name']
                            : r['branch_name'],
                      ),
                      ...keys.map((k) => money(r[k])),
                    ],
                  [
                    Text(
                      context.tr('company_total'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...keys.map((k) => money(j['company'][k], bold: true)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
