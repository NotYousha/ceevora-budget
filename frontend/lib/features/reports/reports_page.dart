import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/utils/export.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/repositories/budget_repository.dart';

const reportCodes = ['R01', 'R02', 'R03', 'R04', 'R05', 'R06'];

/// R01-R06 on one framework: filters -> server report -> sortable, paged grid -> Excel / PDF / print.
class ReportsPage extends ConsumerStatefulWidget {
  final String? initialCode;
  const ReportsPage({super.key, this.initialCode});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late String _code = reportCodes.contains(widget.initialCode)
      ? widget.initialCode!
      : 'R01';
  String _type = 'MONTHLY';
  DateTime _date = DateTime(2027, 1, 31);
  DateTime? _from, _to;
  int _year = 2027;
  int _periodNo = 1;
  int? _branch;
  String? _category, _sort;
  bool _desc = false;
  int _page = 1;
  static const _pageSize = 50;

  Map<String, Object?> _query({bool all = false}) => {
    'period_type': _type,
    if (_type == 'DAILY' || _type == 'MTD' || _type == 'YTD')
      'date': isoDate(_date),
    if (_type == 'MONTHLY' || _type == 'YEARLY') 'year': _year,
    if (_type == 'MONTHLY') 'period_no': _periodNo,
    if (_type == 'CUSTOM' && _from != null) 'date_from': isoDate(_from!),
    if (_type == 'CUSTOM' && _to != null) 'date_to': isoDate(_to!),
    'branch_id': _branch,
    'category': _category,
    'sort': _sort,
    'desc': _desc ? 'true' : null,
    'page': all ? 1 : _page,
    'page_size': all ? 1000 : _pageSize,
  };

  /// Report column label: translated when a key exists, else the server's English label (e.g. branch names in R06).
  String _label(ReportColumn c) {
    final t = context.tr(c.key);
    return t == c.key ? c.label : t;
  }

  String _cellText(ReportColumn c, Object? v) => switch (c.type) {
    'money' => fmtMoney(v),
    'pct' => fmtPct(v),
    _ =>
      c.key == 'line' || c.key == 'status' || c.key == 'category'
          ? context.tr('${v ?? ''}')
          : '${v ?? ''}',
  };

  Future<ExportTable> _exportTable() async {
    final r = await ref
        .read(repoProvider)
        .report(_code, _json(queryKey(_query(all: true))));
    if (!mounted) throw StateError('closed');
    final rows = [...r.rows, if (r.totals != null) r.totals!];
    return ExportTable(
      context.tr(_code),
      [
        '${context.tr('company')}: ${r.company}',
        '${context.tr('branch')}: ${r.branches}',
        '${context.tr('period')}: ${r.periodLabel}',
        '${context.tr('currency')}: ${r.currency}',
        '${context.tr('generated')}: ${fmtDateTime(r.generatedAt)}',
        if (r.provisional) context.tr('provisional'),
      ],
      r.columns.map(_label).toList(),
      [
        for (final row in rows)
          [
            for (final c in r.columns)
              c.type == 'money'
                  ? decOr0(row[c.key]).toDouble()
                  : _cellText(c, row[c.key]),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = queryKey(_query());
    final data = ref.watch(reportProvider((_code, key)));
    return PageFrame(
      title: context.tr('nav_reports'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('refresh')),
          onPressed: () => ref.invalidate(reportProvider((_code, key))),
        ),
        BusyButton(
          label: context.tr('export_excel'),
          icon: Icons.table_view,
          onPressed: () async => exportExcel(await _exportTable()),
        ),
        BusyButton(
          label: context.tr('export_pdf'),
          icon: Icons.print,
          onPressed: () async {
            final t = await _exportTable();
            if (context.mounted) await previewPdf(context, t);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filters(),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncView<ReportData>(
              value: data,
              onRetry: () => ref.invalidate(reportProvider((_code, key))),
              builder: (r) => _grid(r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final ar = context.isArabic;
    final branches = ref.watch(branchesProvider).value ?? [];
    final years = ref.watch(yearsProvider).value ?? [_year];
    final periods = ref.watch(periodsProvider(_year)).value ?? [];
    void set(VoidCallback f) => setState(() {
      f();
      _page = 1;
    });
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
        dd<String>(
          'report',
          _code,
          [for (final c in reportCodes) (c, context.tr(c))],
          (v) => set(() {
            _code = v!;
            _sort = null;
          }),
          340,
        ),
        dd<String>('period_type', _type, [
          for (final t in [
            'DAILY',
            'MTD',
            'MONTHLY',
            'YTD',
            'YEARLY',
            'CUSTOM',
          ])
            (t, context.tr(t)),
        ], (v) => set(() => _type = v!)),
        if (_type == 'DAILY' || _type == 'MTD' || _type == 'YTD')
          DateField(
            label: context.tr('business_date'),
            value: _date,
            onChanged: (d) => set(() => _date = d),
          ),
        if (_type == 'MONTHLY' || _type == 'YEARLY')
          dd<int>(
            'fin_year',
            _year,
            [for (final y in years) (y, '$y')],
            (v) => set(() => _year = v!),
            120,
          ),
        if (_type == 'MONTHLY')
          dd<int>(
            'period',
            _periodNo,
            [for (final p in periods) (p.no, p.name)],
            (v) => set(() => _periodNo = v!),
            140,
          ),
        if (_type == 'CUSTOM') ...[
          DateField(
            label: context.tr('date_from'),
            value: _from,
            onChanged: (d) => set(() => _from = d),
          ),
          DateField(
            label: context.tr('date_to'),
            value: _to,
            onChanged: (d) => set(() => _to = d),
          ),
        ],
        dd<int>(
          'branch',
          _branch,
          [
            (null, context.tr('all_branches')),
            for (final b in branches) (b.id, b.label(ar)),
          ],
          (v) => set(() => _branch = v),
          200,
        ),
        dd<String>('category', _category, [
          (null, context.tr('all')),
          for (final c in ['SALES', 'DISCOUNT', 'RETURN', 'COGS', 'OPEX'])
            (c, context.tr(c)),
        ], (v) => set(() => _category = v)),
      ],
    );
  }

  Widget _grid(ReportData r) {
    final sortIdx = r.columns.indexWhere((c) => c.key == _sort);
    final pages = ((r.totalRows + _pageSize - 1) ~/ _pageSize).clamp(1, 99999);
    Widget cell(ReportColumn c, Json row, {bool bold = false}) {
      final v = row[c.key];
      if (c.key == 'variance' && row['favourable'] != null) {
        return VarianceText(v, favourable: row['favourable'] == true);
      }
      if (c.key == 'status' && v != null) return StatusChip('$v');
      return Text(
        _cellText(c, v),
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProvisionalBanner(r.provisional),
        Text(
          '${context.tr(r.code)}  |  ${r.company}  |  ${r.branches}  |  ${r.periodLabel}  |  ${r.currency}  |  '
          '${context.tr('generated')}: ${fmtDateTime(r.generatedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: r.rows.isEmpty
              ? Center(child: Text(context.tr('no_data')))
              : DataGrid(
                  headers: r.columns.map(_label).toList(),
                  numeric: r.columns.map((c) => c.type != 'text').toList(),
                  sortColumn: sortIdx < 0 ? null : sortIdx,
                  sortAscending: !_desc,
                  onSort: (i, asc) => setState(() {
                    _sort = r.columns[i].key;
                    _desc = !asc;
                    _page = 1;
                  }),
                  rows: [
                    for (final row in r.rows)
                      [for (final c in r.columns) cell(c, row)],
                    if (r.totals != null)
                      [
                        for (final c in r.columns)
                          cell(c, r.totals!, bold: true),
                      ],
                  ],
                ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${r.totalRows} rows  |  ${context.tr('page')} $_page ${context.tr('of')} $pages',
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _page > 1 ? () => setState(() => _page--) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _page < pages ? () => setState(() => _page++) : null,
            ),
          ],
        ),
      ],
    );
  }
}

Json _json(String key) => key.isEmpty ? {} : Uri.splitQueryString(key);
