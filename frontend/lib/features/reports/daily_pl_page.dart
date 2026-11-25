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

/// Screen 07 - Daily P&L (day or month-to-date), branch or consolidated.
class DailyPlPage extends ConsumerStatefulWidget {
  const DailyPlPage({super.key});
  @override
  ConsumerState<DailyPlPage> createState() => _State();
}

class _State extends ConsumerState<DailyPlPage> {
  DateTime _date = DateTime(2027, 1, 31);
  int? _branch;
  String _basis = 'DAY';

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    final key = queryKey({
      'date': isoDate(_date),
      'branch_id': _branch,
      'basis': _basis,
    });
    final data = ref.watch(dailyPlProvider(key));
    final branches = ref.watch(branchesProvider).value ?? [];
    final branchName = _branch == null
        ? context.tr('consolidated')
        : branches
                  .where((b) => b.id == _branch)
                  .map((b) => b.label(ar))
                  .firstOrNull ??
              '';
    const cols = [
      'budget',
      'actual',
      'variance',
      'achievement_pct',
      'pct_of_net_sales',
    ];
    return PageFrame(
      title: context.tr('nav_daily_pl'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('refresh')),
          onPressed: () => ref.invalidate(dailyPlProvider(key)),
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
                      context.tr('nav_daily_pl'),
                      [
                        '${context.tr('company')}: ${s.company.name}',
                        '${context.tr('branch')}: $branchName',
                        '${context.tr('business_date')}: ${isoDate(_date)} (${context.tr(_basis)})',
                        '${context.tr('currency')}: ${s.company.currency}',
                        '${context.tr('generated')}: ${DateTime.now()}',
                        if (data.value!['provisional'] == true)
                          context.tr('provisional'),
                      ],
                      [context.tr('line'), ...cols.map(context.tr)],
                      [
                        for (final l in List<Json>.from(data.value!['lines']))
                          [
                            context.tr(l['line']),
                            decOr0(l['budget']).toDouble(),
                            decOr0(l['actual']).toDouble(),
                            decOr0(l['variance']).toDouble(),
                            fmtPct(l['achievement_pct']),
                            fmtPct(l['pct_of_net_sales']),
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
            crossAxisAlignment: WrapCrossAlignment.center,
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
                      child: Text(context.tr('consolidated')),
                    ),
                    for (final b in branches)
                      DropdownMenuItem(value: b.id, child: Text(b.label(ar))),
                  ],
                  onChanged: (v) => setState(() => _branch = v),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  for (final b in ['DAY', 'MTD'])
                    ButtonSegment(value: b, label: Text(context.tr(b))),
                ],
                selected: {_basis},
                onSelectionChanged: (s) => setState(() => _basis = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncView<Json>(
              value: data,
              onRetry: () => ref.invalidate(dailyPlProvider(key)),
              builder: (d) {
                final lines = List<Json>.from(d['lines']);
                const totals = {
                  'NET_SALES',
                  'GROSS_PROFIT',
                  'OPERATING_PROFIT',
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProvisionalBanner(d['provisional'] == true),
                    Text(
                      '${fmtDate(d['date_from'])} - ${fmtDate(d['date_to'])}  |  $branchName',
                    ),
                    Expanded(
                      child: DataGrid(
                        headers: [context.tr('line'), ...cols.map(context.tr)],
                        numeric: const [false, true, true, true, true, true],
                        onRowTap: _branch == null
                            ? null
                            : (_) => showDrillDialog(
                                context,
                                ref,
                                '${d['date_from']}'.substring(0, 10),
                                isoDate(_date),
                                _branch!,
                                branchName,
                                null,
                              ),
                        rows: [
                          for (final l in lines)
                            [
                              Text(
                                context.tr(l['line']),
                                style: totals.contains(l['line'])
                                    ? const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      )
                                    : null,
                              ),
                              money(
                                l['budget'],
                                bold: totals.contains(l['line']),
                              ),
                              money(
                                l['actual'],
                                bold: totals.contains(l['line']),
                              ),
                              VarianceText(
                                l['variance'],
                                favourable: l['favourable'] == true,
                              ),
                              Text(fmtPct(l['achievement_pct'])),
                              Text(fmtPct(l['pct_of_net_sales'])),
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
