import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/security/session.dart';
import '../../core/utils/export.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../dashboard/drilldown_dialog.dart';

const _cols = [
  'daily_budget',
  'daily_actual',
  'daily_variance',
  'daily_achievement_pct',
  'mtd_budget',
  'mtd_actual',
  'mtd_variance',
  'mtd_achievement_pct',
  'remaining_target',
  'days_remaining',
  'required_avg_daily',
];

/// Screen 06 - Daily Budget Performance (net sales), per branch and consolidated.
class DailyPerformancePage extends ConsumerStatefulWidget {
  const DailyPerformancePage({super.key});
  @override
  ConsumerState<DailyPerformancePage> createState() => _State();
}

class _State extends ConsumerState<DailyPerformancePage> {
  DateTime _date = DateTime(2027, 1, 31);
  int? _branch;

  String _fmt(String k, Object? v) => k.endsWith('pct')
      ? fmtPct(v)
      : k == 'days_remaining'
      ? '$v'
      : fmtMoney(v);

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    final key = queryKey({'date': isoDate(_date), 'branch_id': _branch});
    final data = ref.watch(dailyPerfProvider(key));
    final branches = ref.watch(branchesProvider).value ?? [];
    String name(Json r) =>
        ar ? r['branch_name_ar'] ?? r['branch_name'] : r['branch_name'];
    List<Json> all(Json d) => [
      ...List<Json>.from(d['rows']),
      d['consolidated'],
    ];

    return PageFrame(
      title: context.tr('nav_daily_perf'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('refresh')),
          onPressed: () => ref.invalidate(dailyPerfProvider(key)),
        ),
        for (final pdf in [false, true])
          BusyButton(
            label: context.tr(pdf ? 'export_pdf' : 'export_excel'),
            icon: pdf ? Icons.print : Icons.table_view,
            onPressed: data.value == null
                ? null
                : () async {
                    final s = ref.read(sessionProvider)!;
                    final t = ExportTable(
                      context.tr('nav_daily_perf'),
                      [
                        '${context.tr('company')}: ${s.company.name}',
                        '${context.tr('business_date')}: ${isoDate(_date)}',
                        '${context.tr('currency')}: ${s.company.currency}',
                        '${context.tr('generated')}: ${DateTime.now()}',
                      ],
                      [context.tr('branch'), ..._cols.map(context.tr)],
                      [
                        for (final r in all(data.value!))
                          [
                            name(r),
                            ..._cols.map(
                              (k) =>
                                  k.endsWith('pct') ||
                                      k == 'days_remaining' ||
                                      r[k] == null
                                  ? _fmt(k, r[k])
                                  : decOr0(r[k]).toDouble(),
                            ),
                          ],
                      ],
                    );
                    pdf ? await previewPdf(context, t) : await exportExcel(t);
                  },
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              DateField(
                label: context.tr('business_date'),
                value: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _branch,
                  decoration: InputDecoration(labelText: context.tr('branch')),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.tr('all_branches')),
                    ),
                    for (final b in branches)
                      DropdownMenuItem(value: b.id, child: Text(b.label(ar))),
                  ],
                  onChanged: (v) => setState(() => _branch = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncView<Json>(
              value: data,
              onRetry: () => ref.invalidate(dailyPerfProvider(key)),
              builder: (d) {
                final rows = all(d);
                final from = '${d['period']['start_date']}'.substring(0, 10);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProvisionalBanner(
                      rows.any((r) => r['provisional'] == true),
                    ),
                    Expanded(
                      child: DataGrid(
                        headers: [
                          context.tr('branch'),
                          ..._cols.map(context.tr),
                        ],
                        numeric: [false, ..._cols.map((_) => true)],
                        onRowTap: (i) => i < rows.length - 1
                            ? showDrillDialog(
                                context,
                                ref,
                                from,
                                isoDate(_date),
                                rows[i]['branch_id'],
                                name(rows[i]),
                                'SALES',
                              )
                            : null,
                        rows: [
                          for (var i = 0; i < rows.length; i++)
                            [
                              Text(
                                name(rows[i]),
                                style: i == rows.length - 1
                                    ? const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      )
                                    : null,
                              ),
                              for (final k in _cols)
                                k.endsWith('variance')
                                    ? VarianceText(rows[i][k])
                                    : Text(
                                        _fmt(k, rows[i][k]),
                                        textAlign: TextAlign.end,
                                      ),
                            ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
