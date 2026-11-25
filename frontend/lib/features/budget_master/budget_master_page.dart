import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/security/session.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';
import '../../shared/repositories/budget_repository.dart';
import '../budget_history/history_dialog.dart';
import 'budget_search_dialog.dart';

/// Screen 01 - Budget Master.
class BudgetMasterPage extends ConsumerStatefulWidget {
  final int? budgetId;
  const BudgetMasterPage({super.key, this.budgetId});
  @override
  ConsumerState<BudgetMasterPage> createState() => _BudgetMasterPageState();
}

class _BudgetMasterPageState extends ConsumerState<BudgetMasterPage> {
  final _form = GlobalKey<FormState>();
  final _no = TextEditingController();
  final _name = TextEditingController();
  final _currency = TextEditingController();
  final _remarks = TextEditingController();
  Budget? _budget;
  int? _year;
  DateTime? _start, _end;
  String _alloc = 'CALENDAR_DAYS';
  bool _dirty = false, _loading = false;

  @override
  void initState() {
    super.initState();
    // A new budget defaults to the company's base currency (SAR in the demo).
    _currency.text = ref.read(sessionProvider)!.company.currency;
    if (widget.budgetId != null) _load(widget.budgetId!);
  }

  Future<void> _load(int id) async {
    setState(() => _loading = true);
    try {
      _fill(await ref.read(repoProvider).get(id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(Budget? b) {
    _budget = b;
    _no.text = b?.budgetNo ?? '';
    _name.text = b?.budgetName ?? '';
    _currency.text = b?.currency ?? ref.read(sessionProvider)!.company.currency;
    _remarks.text = b?.remarks ?? '';
    _year = b?.finYear;
    _start = b == null ? null : DateTime.parse(b.startDate);
    _end = b == null ? null : DateTime.parse(b.endDate);
    _alloc = b?.allocationMethod ?? 'CALENDAR_DAYS';
    _dirty = false;
    setState(() {});
  }

  bool get _editable =>
      ref.read(sessionProvider)!.can('BUDGET_CREATE') &&
      (_budget == null || _budget!.isDraft);

  Future<bool> _discardOk() async =>
      !_dirty || await confirmDialog(context, context.tr('unsaved_changes'));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      throw Exception(
        '${context.tr('end_date')} > ${context.tr('start_date')}',
      );
    }
    final repo = ref.read(repoProvider);
    final body = {
      'budget_name': _name.text.trim(),
      'currency_code': _currency.text.trim().toUpperCase(),
      'allocation_method': _alloc,
      'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      'start_date': _start == null ? null : isoDate(_start!),
      'end_date': _end == null ? null : isoDate(_end!),
    };
    final saved = _budget == null
        ? await repo.create({
            ...body,
            'budget_no': _no.text.trim(),
            'fin_year': _year,
          })
        : await repo.update(_budget!.id, {
            ...body,
            'row_version': _budget!.rowVersion,
          });
    ref.invalidate(budgetSearchProvider);
    _fill(saved);
    if (mounted) showInfo(context, context.tr('saved'));
    if (widget.budgetId != saved.id && mounted) {
      context.go('/master?id=${saved.id}');
    }
  }

  Future<void> _submit() async {
    if (!await confirmDialog(context, context.tr('confirm_submit'))) return;
    _fill(
      await ref.read(repoProvider).submit(_budget!.id, _budget!.rowVersion),
    );
    ref.invalidate(budgetSearchProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final years = ref.watch(yearsProvider);
    final b = _budget;
    final editable = _editable;
    final lang = context.isArabic ? 'ar' : 'en';
    void dirty([_]) => setState(() => _dirty = true);
    Widget field(Widget w, [double width = 260]) =>
        SizedBox(width: width, child: w);
    Widget ro(String label, String value) => field(
      InputDecorator(
        decoration: InputDecoration(
          labelText: context.tr(label),
          enabled: false,
        ),
        child: Text(value),
      ),
    );

    return PageFrame(
      title: context.tr('nav_master'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.tr('new')),
          onPressed: !s.can('BUDGET_CREATE')
              ? null
              : () async {
                  if (await _discardOk()) {
                    _fill(null);
                    if (context.mounted && widget.budgetId != null) {
                      context.go('/master');
                    }
                  }
                },
        ),
        BusyButton(
          label: context.tr('save'),
          icon: Icons.save,
          filled: true,
          onPressed: editable && _dirty ? _save : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 18),
          label: Text(context.tr('search')),
          onPressed: () async {
            if (!await _discardOk() || !context.mounted) return;
            final picked = await showBudgetSearch(context);
            if (picked != null && context.mounted) {
              context.go('/master?id=${picked.id}');
            }
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.grid_on, size: 18),
          label: Text(context.tr('budget_entry')),
          onPressed: b == null ? null : () => context.go('/entry?id=${b.id}'),
        ),
        BusyButton(
          label: context.tr('submit'),
          icon: Icons.send,
          onPressed: b != null && b.isDraft && !_dirty && s.can('BUDGET_SUBMIT')
              ? _submit
              : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.history, size: 18),
          label: Text(context.tr('view_history')),
          onPressed: b == null ? null : () => showHistoryDialog(context, b),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: Text(context.tr('cancel')),
          onPressed: () async {
            if (await _discardOk()) b == null ? _fill(null) : _load(b.id);
          },
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(context.tr('new_budget_hint')),
                      ),
                    if (b != null && !b.isDraft)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(context.tr('read_only_budget')),
                      ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        ro('budget_id', b?.id.toString() ?? '-'),
                        field(
                          TextFormField(
                            controller: _no,
                            enabled: b == null && editable,
                            decoration: InputDecoration(
                              labelText: '${context.tr('budget_no')} *',
                            ),
                            validator: (v) =>
                                v == null ||
                                    !RegExp(r'^[A-Za-z0-9\-_/]{1,30}$')
                                        .hasMatch(v.trim())
                                ? context.tr('required')
                                : null,
                            onChanged: dirty,
                          ),
                        ),
                        field(
                          TextFormField(
                            controller: _name,
                            enabled: editable,
                            maxLength: 200,
                            decoration: InputDecoration(
                              labelText: '${context.tr('budget_name')} *',
                              counterText: '',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? context.tr('required')
                                : null,
                            onChanged: dirty,
                          ),
                          400,
                        ),
                        ro(
                          'company',
                          context.isArabic
                              ? (s.company.nameAr ?? s.company.name)
                              : s.company.name,
                        ),
                        field(
                          years.when(
                            data: (ys) => DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: _year,
                              decoration: InputDecoration(
                                labelText: '${context.tr('fin_year')} *',
                              ),
                              items: ys
                                  .map(
                                    (y) => DropdownMenuItem(
                                      value: y,
                                      child: Text('$y'),
                                    ),
                                  )
                                  .toList(),
                              validator: (v) =>
                                  v == null ? context.tr('required') : null,
                              onChanged: b != null || !editable
                                  ? null
                                  : (y) => setState(() {
                                      _year = y;
                                      _start = DateTime(y!, 1, 1);
                                      _end = DateTime(y, 12, 31);
                                      _dirty = true;
                                    }),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (e, _) => Text('$e'),
                          ),
                        ),
                        DateField(
                          label: context.tr('start_date'),
                          value: _start,
                          enabled: editable,
                          onChanged: (d) => setState(() {
                            _start = d;
                            _dirty = true;
                          }),
                        ),
                        DateField(
                          label: context.tr('end_date'),
                          value: _end,
                          enabled: editable,
                          onChanged: (d) => setState(() {
                            _end = d;
                            _dirty = true;
                          }),
                        ),
                        field(
                          TextFormField(
                            controller: _currency,
                            enabled: editable,
                            decoration: InputDecoration(
                              labelText: '${context.tr('currency')} *',
                            ),
                            validator: (v) =>
                                v == null ||
                                    !RegExp(r'^[A-Za-z]{3}$').hasMatch(v.trim())
                                ? context.tr('required')
                                : null,
                            onChanged: dirty,
                          ),
                          120,
                        ),
                        field(
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _alloc,
                            decoration: InputDecoration(
                              labelText: context.tr('allocation_method'),
                            ),
                            items: ['CALENDAR_DAYS', 'WORKING_DAYS']
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(context.tr(m)),
                                  ),
                                )
                                .toList(),
                            onChanged: editable
                                ? (v) => setState(() {
                                    _alloc = v!;
                                    _dirty = true;
                                  })
                                : null,
                          ),
                        ),
                        field(
                          InputDecorator(
                            decoration: InputDecoration(
                              labelText: context.tr('status'),
                            ),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StatusChip(b?.status ?? 'DRAFT'),
                            ),
                          ),
                          160,
                        ),
                        ro('version', 'v${b?.versionNo ?? 0}'),
                        field(
                          TextFormField(
                            controller: _remarks,
                            enabled: editable,
                            maxLines: 2,
                            maxLength: 1000,
                            decoration: InputDecoration(
                              labelText: context.tr('remarks'),
                            ),
                            onChanged: dirty,
                          ),
                          540,
                        ),
                        ro('created_by', b?.createdBy ?? ''),
                        ro('created_at', fmtDateTime(b?.createdAt, lang)),
                        ro('updated_by', b?.updatedBy ?? ''),
                        ro('updated_at', fmtDateTime(b?.updatedAt, lang)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
