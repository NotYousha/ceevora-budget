import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';

/// Searchable, paginated budget lookup used by Master, Entry and Revision screens.
Future<Budget?> showBudgetSearch(BuildContext context, {String? status}) =>
    showDialog<Budget>(
      context: context,
      builder: (_) => _BudgetSearchDialog(status: status),
    );

class _BudgetSearchDialog extends ConsumerStatefulWidget {
  final String? status;
  const _BudgetSearchDialog({this.status});
  @override
  ConsumerState<_BudgetSearchDialog> createState() => _State();
}

class _State extends ConsumerState<_BudgetSearchDialog> {
  final _q = TextEditingController();
  late SearchArgs _args = (q: null, year: null, status: widget.status, page: 1);

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(budgetSearchProvider(_args));
    return AlertDialog(
      title: Text(context.tr('search')),
      content: SizedBox(
        width: 760,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                labelText:
                    '${context.tr('budget_no')} / ${context.tr('budget_name')}',
                suffixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (v) => setState(
                () => _args = (
                  q: v.trim(),
                  year: null,
                  status: widget.status,
                  page: 1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: res,
                isEmpty: (r) => r.items.isEmpty,
                onRetry: () => ref.invalidate(budgetSearchProvider(_args)),
                builder: (r) => Column(
                  children: [
                    Expanded(
                      child: DataGrid(
                        headers: [
                          context.tr('budget_no'),
                          context.tr('budget_name'),
                          context.tr('fin_year'),
                          context.tr('status'),
                          context.tr('version'),
                        ],
                        numeric: const [false, false, false, false, true],
                        rows: [
                          for (final b in r.items)
                            [
                              Text(b.budgetNo),
                              Text(b.budgetName),
                              Text('${b.finYear}'),
                              StatusChip(b.status),
                              Text('v${b.versionNo}'),
                            ],
                        ],
                        onRowTap: (i) => Navigator.pop(context, r.items[i]),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${context.tr('page')} ${_args.page} ${context.tr('of')} ${((r.total + 19) ~/ 20).clamp(1, 9999)}',
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _args.page > 1
                              ? () => setState(
                                  () => _args = (
                                    q: _args.q,
                                    year: null,
                                    status: _args.status,
                                    page: _args.page - 1,
                                  ),
                                )
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _args.page * 20 < r.total
                              ? () => setState(
                                  () => _args = (
                                    q: _args.q,
                                    year: null,
                                    status: _args.status,
                                    page: _args.page + 1,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('close')),
        ),
      ],
    );
  }
}
