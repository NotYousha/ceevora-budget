import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../core/localization/strings.dart';
import '../../core/security/session.dart';
import '../../core/theme/theme.dart';
import '../../core/utils/export.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/repositories/budget_repository.dart';
import '../budget_master/budget_search_dialog.dart';
import 'entry_math.dart';

/// Screen 02 - Branch-wise Budget Entry: GL rows x monthly periods with fixed account columns.
class BudgetEntryPage extends ConsumerStatefulWidget {
  final int? budgetId;
  const BudgetEntryPage({super.key, this.budgetId});
  @override
  ConsumerState<BudgetEntryPage> createState() => _BudgetEntryPageState();
}

class _Row {
  final GlAccount account;
  final List<TextEditingController> cells;
  _Row(this.account, List<Decimal> amounts)
    : cells = amounts
          .map(
            (a) => TextEditingController(
              text: a == Decimal.zero ? '' : a.toStringAsFixed(2),
            ),
          )
          .toList();
  List<Decimal?> get values => cells.map((c) => parseAmount(c.text)).toList();
}

class _BudgetEntryPageState extends ConsumerState<BudgetEntryPage> {
  Budget? _budget;
  int? _branch;
  BudgetEntry? _entry;
  List<_Row> _rows = [];
  int? _selRow, _selCol;
  bool _dirty = false, _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.budgetId != null) {
      ref
          .read(repoProvider)
          .get(widget.budgetId!)
          .then((b) => setState(() => _budget = b))
          .catchError((e) {
            if (mounted) showError(context, e);
          });
    }
  }

  Future<void> _load() async {
    if (_budget == null || _branch == null) return;
    setState(() => _loading = true);
    try {
      final e = await ref.read(repoProvider).entry(_budget!.id, _branch!);
      _apply(e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _apply(BudgetEntry e) {
    _entry = e;
    _budget = e.budget;
    _rows = e.lines.map((l) => _Row(l.account, l.amounts)).toList();
    _dirty = false;
    _selRow = _selCol = null;
    setState(() {});
  }

  bool get _editable =>
      _budget != null &&
      _budget!.isDraft &&
      ref.read(sessionProvider)!.can('BUDGET_CREATE') &&
      _entry != null;
  bool get _valid => _rows.every((r) => r.values.every((v) => v != null));

  Future<bool> _discardOk() async =>
      !_dirty || await confirmDialog(context, context.tr('unsaved_changes'));

  Future<void> _save() async {
    final lines = _rows
        .map((r) => EntryLine(r.account, r.values.map((v) => v!).toList()))
        .toList();
    _apply(
      await ref
          .read(repoProvider)
          .saveEntry(_budget!.id, _branch!, _budget!.rowVersion, lines),
    );
    ref.invalidate(summaryProvider(_budget!.id));
    if (mounted) showInfo(context, context.tr('saved'));
  }

  Future<void> _submit() async {
    if (!await confirmDialog(context, context.tr('confirm_submit'))) return;
    await ref.read(repoProvider).submit(_budget!.id, _budget!.rowVersion);
    ref.invalidate(budgetSearchProvider);
    await _load();
  }

  Future<void> _addAccount() async {
    final all = await ref.read(glAccountsProvider.future);
    final used = _rows.map((r) => r.account.id).toSet();
    if (!mounted) return;
    final ar = context.isArabic;
    GlAccount? picked;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('add_account')),
        content: DropdownMenu<GlAccount>(
          width: 460,
          enableFilter: true,
          requestFocusOnTap: true,
          label: Text(c.tr('select_account')),
          dropdownMenuEntries: [
            for (final g in all.where((g) => !used.contains(g.id)))
              DropdownMenuEntry(value: g, label: '${g.code} - ${g.label(ar)}'),
          ],
          onSelected: (g) {
            picked = g;
            Navigator.pop(c);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.tr('cancel')),
          ),
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        _rows = [
          ..._rows,
          _Row(picked!, List.filled(_entry!.periods.length, Decimal.zero)),
        ]..sort((a, b) => a.account.code.compareTo(b.account.code));
        _dirty = true;
      });
    }
  }

  void _copyPrevMonth() {
    final c = _selCol;
    if (c == null || c == 0) {
      return showInfo(context, context.tr('select_cell_first'));
    }
    setState(() {
      for (final r in _rows) {
        r.cells[c].text = r.cells[c - 1].text;
      }
      _dirty = true;
    });
  }

  void _copyAllMonths() {
    if (_selRow == null || _selCol == null) {
      return showInfo(context, context.tr('select_cell_first'));
    }
    final row = _rows[_selRow!];
    setState(() {
      for (final cell in row.cells) {
        cell.text = row.cells[_selCol!].text;
      }
      _dirty = true;
    });
  }

  ExportTable _exportTable() {
    final ar = context.isArabic;
    final periods = _entry!.periods;
    final branch =
        ref
            .read(branchesProvider)
            .value
            ?.firstWhere((b) => b.id == _branch)
            .label(ar) ??
        '';
    return ExportTable(
      '${_budget!.budgetNo} ${context.tr('budget_entry')}',
      [
        _budget!.budgetName,
        '${context.tr('branch')}: $branch',
        '${context.tr('currency')}: ${_budget!.currency}',
        '${context.tr('generated')}: ${DateTime.now()}',
      ],
      [
        context.tr('gl_code'),
        context.tr('gl_description'),
        ...periods.map((p) => p.name),
        context.tr('annual_total'),
      ],
      [
        for (final r in _rows)
          [
            r.account.code,
            r.account.label(ar),
            ...r.values.map((v) => (v ?? Decimal.zero).toDouble()),
            r.values
                .fold<Decimal>(Decimal.zero, (a, v) => a + (v ?? Decimal.zero))
                .toDouble(),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final branches = ref.watch(branchesProvider);
    final ar = context.isArabic;
    final editable = _editable;
    return PageFrame(
      title: context.tr('nav_entry'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 18),
          label: Text(context.tr('search')),
          onPressed: () async {
            if (!await _discardOk() || !context.mounted) return;
            final b = await showBudgetSearch(context);
            if (b != null && context.mounted) context.go('/entry?id=${b.id}');
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.playlist_add, size: 18),
          label: Text(context.tr('add_account')),
          onPressed: editable ? _addAccount : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.playlist_remove, size: 18),
          label: Text(context.tr('remove_account')),
          onPressed: editable && _selRow != null
              ? () => setState(() {
                  _rows.removeAt(_selRow!);
                  _selRow = _selCol = null;
                  _dirty = true;
                })
              : null,
        ),
        OutlinedButton(
          onPressed: editable ? _copyPrevMonth : null,
          child: Text(context.tr('copy_prev_month')),
        ),
        OutlinedButton(
          onPressed: editable ? _copyAllMonths : null,
          child: Text(context.tr('copy_all_months')),
        ),
        BusyButton(
          label: context.tr('save'),
          icon: Icons.save,
          filled: true,
          onPressed: editable && _dirty && _valid ? _save : null,
        ),
        BusyButton(
          label: context.tr('submit'),
          icon: Icons.send,
          onPressed:
              editable && !_dirty && _rows.isNotEmpty && s.can('BUDGET_SUBMIT')
              ? _submit
              : null,
        ),
        BusyButton(
          label: context.tr('export_excel'),
          icon: Icons.table_view,
          onPressed: _entry == null ? null : () => exportExcel(_exportTable()),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: Text(context.tr('cancel')),
          onPressed: () async {
            if (await _discardOk()) _load();
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.tr('nav_master'),
                  ),
                  child: Text(
                    _budget == null
                        ? context.tr('select_budget')
                        : '${_budget!.budgetNo} - ${_budget!.budgetName}',
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.tr('fin_year'),
                  ),
                  child: Text('${_budget?.finYear ?? ''}'),
                ),
              ),
              SizedBox(
                width: 240,
                child: branches.when(
                  data: (bs) => DropdownButtonFormField<int>(
                    isExpanded: true,
                    key: const Key('branch'),
                    initialValue: _branch,
                    decoration: InputDecoration(
                      labelText: context.tr('branch'),
                    ),
                    items: bs
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.label(ar)),
                          ),
                        )
                        .toList(),
                    onChanged: _budget == null
                        ? null
                        : (v) async {
                            if (!await _discardOk()) return;
                            _branch = v;
                            _load();
                          },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              if (_budget != null) StatusChip(_budget!.status),
              if (_budget != null && !_budget!.isDraft)
                Text(context.tr('read_only_budget')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entry == null
                ? Center(
                    child: Text(
                      context.tr(
                        _budget == null ? 'select_budget' : 'select_branch',
                      ),
                    ),
                  )
                : _grid(editable),
          ),
          if (_entry != null) _summary(),
        ],
      ),
    );
  }

  Widget _grid(bool editable) {
    final periods = _entry!.periods;
    final ar = context.isArabic;
    final cols = 2 + periods.length + 1;
    final narrow = PageFrame.isNarrow(context);
    Widget cell(Widget child, {Color? color, bool end = false}) => Container(
      alignment: end
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppColors.grid, width: 0.5),
      ),
      child: child,
    );
    return TableView.builder(
      pinnedRowCount: 1,
      pinnedColumnCount: 2,
      columnCount: cols,
      rowCount: _rows.length + 1,
      columnBuilder: (i) => TableSpan(
        extent: FixedTableSpanExtent(
          i == 0
              ? (narrow ? 56 : 90)
              : i == 1
              ? (narrow ? 120 : 220)
              : (narrow ? 100 : 120),
        ),
      ),
      rowBuilder: (i) => const TableSpan(extent: FixedTableSpanExtent(40)),
      cellBuilder: (context, v) {
        final r = v.row - 1, c = v.column;
        if (v.row == 0) {
          final label = c == 0
              ? context.tr('gl_code')
              : c == 1
              ? context.tr('gl_description')
              : c == cols - 1
              ? context.tr('annual_total')
              : periods[c - 2].name;
          return TableViewCell(
            child: cell(
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              color: AppColors.header,
            ),
          );
        }
        final row = _rows[r];
        final selected = _selRow == r;
        if (c == 0) {
          return TableViewCell(
            child: cell(
              Text(row.account.code),
              color: selected ? AppColors.header : null,
            ),
          );
        }
        if (c == 1) {
          return TableViewCell(
            child: InkWell(
              onTap: () => setState(() => _selRow = r),
              child: cell(
                Text(row.account.label(ar), overflow: TextOverflow.ellipsis),
                color: selected ? AppColors.header : null,
              ),
            ),
          );
        }
        if (c == cols - 1) {
          final total = row.values.fold<Decimal>(
            Decimal.zero,
            (a, v) => a + (v ?? Decimal.zero),
          );
          return TableViewCell(
            child: cell(
              Text(
                fmtMoney(total.toString()),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              color: AppColors.header,
              end: true,
            ),
          );
        }
        final ctl = row.cells[c - 2];
        final bad = parseAmount(ctl.text) == null;
        return TableViewCell(
          child: cell(
            editable
                ? Focus(
                    onFocusChange: (f) {
                      if (f) {
                        setState(() {
                          _selRow = r;
                          _selCol = c - 2;
                        });
                      }
                    },
                    child: TextField(
                      controller: ctl,
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        errorText: bad ? '!' : null,
                        errorStyle: const TextStyle(height: 0, fontSize: 0),
                      ),
                      style: TextStyle(
                        color: bad ? AppColors.unfavourable : null,
                      ),
                      onChanged: (_) => setState(() => _dirty = true),
                    ),
                  )
                : Text(
                    fmtMoney(
                      ctl.text.isEmpty ? '0' : ctl.text,
                      blankZero: true,
                    ),
                  ),
            color: bad
                ? AppColors.unfavourable.withValues(alpha: 0.08)
                : (_selRow == r && _selCol == c - 2 ? AppColors.header : null),
            end: true,
          ),
        );
      },
    );
  }

  Widget _summary() {
    final n = _entry!.periods.length;
    final lines = _rows
        .map(
          (r) => (
            category: r.account.category,
            amounts: r.values.map((v) => v ?? Decimal.zero).toList(),
          ),
        )
        .toList();
    final s = entrySummary(lines, n);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            for (final k in [
              'NET_SALES',
              'COGS',
              'GROSS_PROFIT',
              'OPEX',
              'OPERATING_PROFIT',
            ])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(k),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    fmtMoney(s[k].toString()),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: k.endsWith('PROFIT') && s[k]! < Decimal.zero
                          ? AppColors.unfavourable
                          : AppColors.navy,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
