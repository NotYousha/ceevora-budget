import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/security/session.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/budget_repository.dart';

/// Branch -> GL accounts -> posted JV lines. The server enforces DRILLDOWN_VIEW and branch access.
void showDrillDialog(
  BuildContext context,
  WidgetRef ref,
  String from,
  String to,
  int branchId,
  String branchName,
  String? category,
) {
  if (!ref.read(sessionProvider)!.can('DRILLDOWN_VIEW')) return;
  showDialog(
    context: context,
    builder: (_) => _DrillDialog(
      from: from,
      to: to,
      branchId: branchId,
      branchName: branchName,
      category: category,
    ),
  );
}

class _DrillDialog extends ConsumerStatefulWidget {
  final String from, to, branchName;
  final int branchId;
  final String? category;
  const _DrillDialog({
    required this.from,
    required this.to,
    required this.branchId,
    required this.branchName,
    this.category,
  });
  @override
  ConsumerState<_DrillDialog> createState() => _DrillState();
}

class _DrillState extends ConsumerState<_DrillDialog> {
  late Future<List> _gl;
  Json? _account;
  Future<Json>? _tx;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _gl = ref.read(repoProvider).drillGl({
      'date_from': widget.from,
      'date_to': widget.to,
      'branch_id': widget.branchId,
      'category': widget.category,
    });
  }

  void _openTx(Json a, int page) {
    setState(() {
      _account = a;
      _page = page;
      _tx = ref.read(repoProvider).drillTransactions({
        'date_from': widget.from,
        'date_to': widget.to,
        'branch_id': widget.branchId,
        'gl_account_id': a['gl_account_id'],
        'page': page,
        'page_size': 50,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    final lang = ar ? 'ar' : 'en';
    return Dialog(
      child: SizedBox(
        width: 1000,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_account != null)
                    IconButton(
                      icon: const BackButtonIcon(),
                      onPressed: () => setState(() => _account = null),
                    ),
                  Expanded(
                    child: Text(
                      '${context.tr('drilldown')}: ${widget.branchName} (${widget.from} - ${widget.to})'
                      '${_account == null ? '' : ' / ${_account!['gl_code']}'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('close')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _account == null
                    ? FutureBuilder<List>(
                        future: _gl,
                        builder: (c, s) => AsyncView<List>(
                          value: s.hasError
                              ? AsyncValue.error(s.error!, StackTrace.empty)
                              : s.hasData
                              ? AsyncValue.data(s.data!)
                              : const AsyncValue.loading(),
                          isEmpty: (l) => l.isEmpty,
                          builder: (l) => DataGrid(
                            headers: [
                              'gl_code',
                              'gl_description',
                              'category',
                              'budget',
                              'actual',
                              'variance',
                              'achievement',
                            ].map(context.tr).toList(),
                            numeric: const [
                              false,
                              false,
                              false,
                              true,
                              true,
                              true,
                              true,
                            ],
                            onRowTap: (i) => _openTx(l[i], 1),
                            rows: [
                              for (final g in l)
                                [
                                  Text(g['gl_code']),
                                  Text(
                                    ar
                                        ? g['gl_name_ar'] ?? g['gl_name']
                                        : g['gl_name'],
                                  ),
                                  Text(context.tr(g['category'])),
                                  money(g['budget']),
                                  money(g['actual']),
                                  VarianceText(
                                    g['variance'],
                                    favourable: g['favourable'] == true,
                                  ),
                                  Text(fmtPct(g['achievement_pct'])),
                                ],
                            ],
                          ),
                        ),
                      )
                    : FutureBuilder<Json>(
                        future: _tx,
                        builder: (c, s) => AsyncView<Json>(
                          value: s.hasError
                              ? AsyncValue.error(s.error!, StackTrace.empty)
                              : s.hasData
                              ? AsyncValue.data(s.data!)
                              : const AsyncValue.loading(),
                          builder: (j) {
                            final items = List<Json>.from(j['items']);
                            final total = j['total'] as int;
                            return Column(
                              children: [
                                Expanded(
                                  child: DataGrid(
                                    headers: [
                                      'jv_no',
                                      'jv_date',
                                      'jv_type',
                                      'description',
                                      'debit',
                                      'credit',
                                      'amount',
                                    ].map(context.tr).toList(),
                                    numeric: const [
                                      false,
                                      false,
                                      false,
                                      false,
                                      true,
                                      true,
                                      true,
                                    ],
                                    rows: [
                                      for (final t in items)
                                        [
                                          Text(t['jv_no']),
                                          Text(fmtDate(t['jv_date'], lang)),
                                          Text(t['jv_type']),
                                          Text(t['description'] ?? ''),
                                          money(t['debit']),
                                          money(t['credit']),
                                          money(t['amount']),
                                        ],
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${context.tr('page')} $_page ${context.tr('of')} ${((total + 49) ~/ 50).clamp(1, 99999)}',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left),
                                      onPressed: _page > 1
                                          ? () => _openTx(_account!, _page - 1)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right),
                                      onPressed: _page * 50 < total
                                          ? () => _openTx(_account!, _page + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
