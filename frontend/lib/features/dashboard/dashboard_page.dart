import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import 'drilldown_dialog.dart';

/// Screen 05 - Budget vs Actual dashboard.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  int? _year, _period, _branch, _gl;
  String? _category;
  DateTime? _from, _to;

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(yearsProvider);
    _year ??= years.value?.contains(2027) == true
        ? 2027
        : years.value?.lastOrNull;
    final ar = context.isArabic;
    final key = queryKey({
      'year': _year,
      'period_no': _period,
      'branch_id': _branch,
      'category': _category,
      'gl_account_id': _gl,
      if (_from != null && _to != null) 'date_from': isoDate(_from!),
      if (_from != null && _to != null) 'date_to': isoDate(_to!),
    });
    final data = _year == null ? null : ref.watch(dashboardProvider(key));
    return PageFrame(
      title: context.tr('nav_dashboard'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('refresh')),
          onPressed: () => ref.invalidate(dashboardProvider(key)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filters(ar),
          const SizedBox(height: 12),
          Expanded(
            child: data == null
                ? const Center(child: CircularProgressIndicator())
                : AsyncView(
                    value: data,
                    onRetry: () => ref.invalidate(dashboardProvider(key)),
                    builder: (d) => _body(d, ar),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filters(bool ar) {
    final years = ref.watch(yearsProvider).value ?? [];
    final periods = _year == null
        ? <Period>[]
        : ref.watch(periodsProvider(_year!)).value ?? [];
    final branches = ref.watch(branchesProvider).value ?? [];
    final gls = ref.watch(glAccountsProvider).value ?? [];
    Widget dd<T>(
      String label,
      T? value,
      List<(T?, String)> items,
      ValueChanged<T?> on, [
      double w = 170,
    ]) => SizedBox(
      width: w,
      child: DropdownButtonFormField<T?>(
        key: ValueKey('$label$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr(label)),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i.$1,
              child: Text(i.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: on,
      ),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        dd<int>(
          'fin_year',
          _year,
          [for (final y in years) (y, '$y')],
          (v) => setState(() {
            _year = v;
            _period = null;
          }),
          120,
        ),
        dd<int>(
          'period',
          _period,
          [(null, context.tr('all')), for (final p in periods) (p.no, p.name)],
          (v) => setState(() => _period = v),
          140,
        ),
        DateField(
          label: context.tr('date_from'),
          value: _from,
          onChanged: (d) => setState(() => _from = d),
        ),
        DateField(
          label: context.tr('date_to'),
          value: _to,
          onChanged: (d) => setState(() => _to = d),
        ),
        if (_from != null || _to != null)
          IconButton(
            tooltip: context.tr('cancel'),
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _from = _to = null),
          ),
        dd<int>(
          'branch',
          _branch,
          [
            (null, context.tr('all_branches')),
            for (final b in branches) (b.id, b.label(ar)),
          ],
          (v) => setState(() => _branch = v),
          200,
        ),
        dd<String>('category', _category, [
          (null, context.tr('all')),
          for (final c in ['SALES', 'DISCOUNT', 'RETURN', 'COGS', 'OPEX'])
            (c, context.tr(c)),
        ], (v) => setState(() => _category = v)),
        dd<int>(
          'gl_account',
          _gl,
          [
            (null, context.tr('all')),
            for (final g in gls) (g.id, '${g.code} ${g.label(ar)}'),
          ],
          (v) => setState(() => _gl = v),
          240,
        ),
      ],
    );
  }

  Widget _kpi(String label, Json k, {bool expense = false}) => Card(
    child: Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(label),
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${context.tr('budget')}: '),
              Expanded(child: money(k['budget'])),
            ],
          ),
          Row(
            children: [
              Text('${context.tr('actual')}: '),
              Expanded(child: money(k['actual'], bold: true)),
            ],
          ),
          Row(
            children: [
              Text('${context.tr('variance')}: '),
              Expanded(
                child: VarianceText(
                  k['variance'],
                  favourable: k['favourable'] == true,
                ),
              ),
            ],
          ),
          Text(
            '${context.tr(expense ? 'utilization_pct' : 'achievement')}: ${fmtPct(k['achievement_pct'])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _card(
    String title,
    Widget child, {
    double height = 280,
    double width = 520,
  }) => Card(
    child: Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(title),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    ),
  );

  double _d(Object? v) => decOr0(v).toDouble();

  Widget _bars(
    List<Json> rows,
    String bKey,
    String aKey,
    String Function(Json) label, {
    void Function(Json)? onTap,
  }) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchCallback: (e, r) {
            if (onTap != null && e is FlTapUpEvent && r?.spot != null) {
              onTap(rows[r!.spot!.touchedBarGroupIndex]);
            }
          },
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 56),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  label(rows[v.toInt()]),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < rows.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: _d(rows[i][bKey]),
                  color: AppColors.navyLight,
                  width: 14,
                ),
                BarChartRodData(
                  toY: _d(rows[i][aKey]),
                  color: AppColors.teal,
                  width: 14,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legend() => Row(
    children: [
      Container(width: 12, height: 12, color: AppColors.navyLight),
      Text(' ${context.tr('budget')}   '),
      Container(width: 12, height: 12, color: AppColors.teal),
      Text(' ${context.tr('actual')}'),
    ],
  );

  Widget _body(Json d, bool ar) {
    final k = d['kpis'] as Json;
    final branches = List<Json>.from(d['branches']);
    final trend = List<Json>.from(d['trend']);
    final pie = List<Json>.from(d['expense_categories']);
    const palette = [
      AppColors.teal,
      AppColors.navyLight,
      AppColors.warning,
      Color(0xFF6A1B9A),
      Color(0xFF00838F),
      Color(0xFF8D6E63),
    ];
    final pieTotal = pie.fold<double>(0, (a, p) => a + _d(p['actual']));
    String bname(Json r) =>
        ar ? (r['branch_name_ar'] ?? r['branch_name']) : r['branch_name'];
    void drill(Json r) => showDrillDialog(
      context,
      ref,
      isoDateStr(d['date_from']),
      isoDateStr(d['date_to']),
      r['branch_id'],
      bname(r),
      _category,
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProvisionalBanner(d['provisional'] == true),
          Text(
            '${fmtDate(d['date_from'])} - ${fmtDate(d['date_to'])}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kpi('NET_SALES', k['net_sales']),
              _kpi('expense_budget', k['expenses'], expense: true),
              _kpi('GROSS_PROFIT', k['gross_profit']),
              _kpi('OPERATING_PROFIT', k['operating_profit']),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _card(
                'branch_bva',
                Column(
                  children: [
                    _legend(),
                    Expanded(
                      child: _bars(
                        branches,
                        'sales_budget',
                        'sales_actual',
                        bname,
                        onTap: drill,
                      ),
                    ),
                  ],
                ),
              ),
              _card(
                'monthly_trend',
                Column(
                  children: [
                    _legend(),
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 56,
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (v, m) => Text('${v.toInt()}'),
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (final t in trend)
                                  FlSpot(
                                    (t['period_no'] as int).toDouble(),
                                    _d(t['sales_budget']),
                                  ),
                              ],
                              color: AppColors.navyLight,
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: [
                                for (final t in trend.where(
                                  (t) => _d(t['sales_actual']) != 0,
                                ))
                                  FlSpot(
                                    (t['period_no'] as int).toDouble(),
                                    _d(t['sales_actual']),
                                  ),
                              ],
                              color: AppColors.teal,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _card(
                'expense_pie',
                pieTotal == 0
                    ? Center(child: Text(context.tr('no_data')))
                    : Row(
                        children: [
                          Expanded(
                            child: PieChart(
                              PieChartData(
                                sections: [
                                  for (var i = 0; i < pie.length; i++)
                                    PieChartSectionData(
                                      value: _d(pie[i]['actual']),
                                      color: palette[i % palette.length],
                                      radius: 70,
                                      title:
                                          '${(_d(pie[i]['actual']) / pieTotal * 100).toStringAsFixed(0)}%',
                                      titleStyle: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < pie.length; i++)
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      color: palette[i % palette.length],
                                    ),
                                    Text(
                                      ' ${pie[i]['group']}: ${fmtMoney(pie[i]['actual'])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
              _card(
                'utilization',
                ListView(
                  children: [
                    for (final b in branches)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${bname(b)}: ${fmtPct(b['utilization_pct'])}',
                            ),
                            LinearProgressIndicator(
                              value:
                                  ((dec(b['utilization_pct'])?.toDouble() ??
                                              0) /
                                          100)
                                      .clamp(0, 1),
                              minHeight: 10,
                              color:
                                  (dec(b['utilization_pct'])?.toDouble() ?? 0) >
                                      100
                                  ? AppColors.unfavourable
                                  : AppColors.teal,
                              backgroundColor: AppColors.grid,
                              semanticsLabel:
                                  '${bname(b)} ${fmtPct(b['utilization_pct'])}',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _card(
                'profit_comparison',
                Column(
                  children: [
                    _legend(),
                    Expanded(
                      child: _bars(
                        branches,
                        'profit_budget',
                        'profit_actual',
                        bname,
                        onTap: drill,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('drilldown'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
          SizedBox(
            height: 60.0 + 44 * branches.length,
            child: DataGrid(
              headers: [
                'branch',
                'sales_budget',
                'sales_actual',
                'sales_variance',
                'expense_budget',
                'expense_actual',
                'profit_budget',
                'profit_actual',
              ].map(context.tr).toList(),
              numeric: const [false, true, true, true, true, true, true, true],
              onRowTap: (i) => drill(branches[i]),
              rows: [
                for (final b in branches)
                  [
                    Text(bname(b)),
                    money(b['sales_budget']),
                    money(b['sales_actual']),
                    VarianceText(
                      (decOr0(b['sales_actual']) - decOr0(b['sales_budget']))
                          .toString(),
                    ),
                    money(b['expense_budget']),
                    money(b['expense_actual']),
                    money(b['profit_budget']),
                    money(b['profit_actual']),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String isoDateStr(Object? v) => '$v'.substring(0, 10);
