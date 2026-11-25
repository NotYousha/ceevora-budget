import 'package:decimal/decimal.dart';
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
import '../budget_master/budget_search_dialog.dart';

/// Screen 04 - Budget Revision: request line revisions on an approved budget; approve or reject them.
class RevisionPage extends ConsumerStatefulWidget {
  final int? budgetId;
  const RevisionPage({super.key, this.budgetId});
  @override
  ConsumerState<RevisionPage> createState() => _RevisionPageState();
}

class _RevisionPageState extends ConsumerState<RevisionPage> {
  Budget? _budget;
  int? _branch, _period;
  GlAccount? _gl;
  Json? _line;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _idem = newIdempotencyKey(); // one key per revision attempt: a double click cannot create two rows
  String? _statusFilter = 'PENDING';
  final Set<int> _selected = {};

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

  Future<void> _loadLine() async {
    if (_budget == null || _branch == null || _gl == null || _period == null) {
      return;
    }
    try {
      final l = await ref
          .read(repoProvider)
          .revisionLine(_budget!.id, _branch!, _gl!.id, _period!);
      setState(() => _line = l);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Decimal? get _proposed =>
      _amount.text.trim().isEmpty ? null : parseAmount(_amount.text);

  Future<void> _saveRevision() async {
    await ref.read(repoProvider).requestRevision(_budget!.id, {
      'branch_id': _branch,
      'gl_account_id': _gl!.id,
      'period_no': _period,
      'revised_amount': _proposed!.toStringAsFixed(2),
      'reason': _reason.text.trim(),
    }, _idem);
    _idem = newIdempotencyKey();
    _amount.clear();
    _reason.clear();
    _refresh();
    await _loadLine();
    if (mounted) showInfo(context, context.tr('saved'));
  }

  void _refresh() {
    ref.invalidate(revisionHistoryProvider);
    ref.invalidate(approvalHistoryProvider);
    setState(_selected.clear);
  }

  Future<void> _approve() async {
    if (!await confirmDialog(context, context.tr('confirm_approve_rev'))) {
      return;
    }
    final r = await ref.read(repoProvider).approveRevisions(_selected.toList());
    if ((r['stale_rejected'] as List).isNotEmpty && mounted) {
      showError(context, context.tr('stale_rejected'));
    }
    _budget = await ref.read(repoProvider).get(_budget!.id);
    _refresh();
    await _loadLine();
  }

  Future<void> _reject() async {
    final reason = await reasonDialog(context, context.tr('reject_revision'));
    if (reason == null) return;
    await ref.read(repoProvider).rejectRevisions(_selected.toList(), reason);
    _refresh();
    await _loadLine();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider)!;
    final ar = context.isArabic;
    final b = _budget;
    final branches = ref.watch(branchesProvider);
    final gls = ref.watch(glAccountsProvider);
    final periods = b == null ? null : ref.watch(periodsProvider(b.finYear));
    final current = _line == null ? null : decOr0(_line!['current_amount']);
    final prop = _proposed;
    final diff = current == null || prop == null ? null : prop - current;
    final pct = diff == null || current == Decimal.zero
        ? null
        : (diff * Decimal.fromInt(100) / current!).toDecimal(
            scaleOnInfinitePrecision: 4,
          );
    final hasPending = _line?['pending'] != null;
    final canSave =
        s.can('REVISION_REQUEST') &&
        b?.status == 'APPROVED' &&
        _line != null &&
        !hasPending &&
        prop != null &&
        prop != current &&
        _reason.text.trim().isNotEmpty;
    final canDecide = s.can('REVISION_APPROVE') && _selected.isNotEmpty;

    return PageFrame(
      title: context.tr('nav_revision'),
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.search, size: 18),
          label: Text(context.tr('search')),
          onPressed: () async {
            final picked = await showBudgetSearch(context, status: 'APPROVED');
            if (picked != null && context.mounted) {
              context.go('/revision?id=${picked.id}');
            }
          },
        ),
        BusyButton(
          label: context.tr('save_revision'),
          icon: Icons.save,
          filled: true,
          onPressed: canSave ? _saveRevision : null,
        ),
        BusyButton(
          label: context.tr('approve_revision'),
          icon: Icons.check_circle,
          onPressed: canDecide ? _approve : null,
        ),
        BusyButton(
          label: context.tr('reject_revision'),
          icon: Icons.cancel,
          onPressed: canDecide ? _reject : null,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.history, size: 18),
          label: Text(context.tr('view_history')),
          onPressed: b == null ? null : () => showHistoryDialog(context, b),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: Text(context.tr('close')),
          onPressed: () =>
              context.go('/master${b == null ? '' : '?id=${b.id}'}'),
        ),
      ],
      child: b == null
          ? Center(
              child: Text(
                '${context.tr('select_budget')} (${context.tr('approved_budgets_only')})',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${b.budgetNo} - ${b.budgetName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    StatusChip(b.status),
                    Text('v${b.versionNo}'),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _branch,
                        decoration: InputDecoration(
                          labelText: context.tr('branch'),
                        ),
                        items: (branches.value ?? [])
                            .map(
                              (x) => DropdownMenuItem(
                                value: x.id,
                                child: Text(x.label(ar)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          _branch = v;
                          _loadLine();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _period,
                        decoration: InputDecoration(
                          labelText: context.tr('period'),
                        ),
                        items: (periods?.value ?? [])
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.no,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          _period = v;
                          _loadLine();
                        },
                      ),
                    ),
                    DropdownMenu<GlAccount>(
                      width: 340,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      label: Text(context.tr('gl_account')),
                      dropdownMenuEntries: [
                        for (final g in gls.value ?? <GlAccount>[])
                          DropdownMenuEntry(
                            value: g,
                            label: '${g.code} - ${g.label(ar)}',
                          ),
                      ],
                      onSelected: (g) {
                        _gl = g;
                        _loadLine();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ro(
                      context.tr('original_amount'),
                      fmtMoney(_line?['original_amount']),
                    ),
                    _ro(
                      context.tr('current_amount'),
                      fmtMoney(_line?['current_amount']),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _amount,
                        enabled: _line != null && !hasPending,
                        textAlign: TextAlign.end,
                        decoration: InputDecoration(
                          labelText: context.tr('proposed_amount'),
                          errorText: _amount.text.isNotEmpty && prop == null
                              ? '0.00'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _ro(
                      context.tr('difference'),
                      diff == null ? '' : fmtMoney(diff.toString()),
                    ),
                    _ro(
                      context.tr('pct'),
                      diff == null ? '' : fmtPct(pct?.toString()),
                    ),
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: _reason,
                        enabled: _line != null && !hasPending,
                        maxLength: 1000,
                        decoration: InputDecoration(
                          labelText: '${context.tr('reason')} *',
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (hasPending) StatusChip('PENDING'),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text(
                      context.tr('pending_revisions'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _statusFilter,
                        decoration: InputDecoration(
                          labelText: context.tr('status'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(context.tr('all')),
                          ),
                          for (final st in ['PENDING', 'APPROVED', 'REJECTED'])
                            DropdownMenuItem(
                              value: st,
                              child: Text(context.tr(st)),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _statusFilter = v;
                          _selected.clear();
                        }),
                      ),
                    ),
                  ],
                ),
                Expanded(child: _list(b)),
              ],
            ),
    );
  }

  Widget _ro(String label, String value) => SizedBox(
    width: 160,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, enabled: false),
      child: Text(value, textAlign: TextAlign.end),
    ),
  );

  Widget _list(Budget b) {
    final ar = context.isArabic;
    final lang = ar ? 'ar' : 'en';
    return AsyncView(
      value: ref.watch(
        revisionHistoryProvider((
          budget: b.id,
          version: null,
          status: _statusFilter,
        )),
      ),
      isEmpty: (l) => l.isEmpty,
      builder: (l) => DataGrid(
        headers: [
          '#',
          'branch',
          'period',
          'gl_code',
          'gl_description',
          'prev_approved',
          'revised_amount',
          'difference',
          'pct',
          'status',
          'reason',
          'revised_by',
          'revised_at',
        ].map(context.tr).toList(),
        numeric: const [
          true,
          false,
          true,
          false,
          false,
          true,
          true,
          true,
          true,
          false,
          false,
          false,
          false,
        ],
        selected: {
          for (var i = 0; i < l.length; i++)
            if (_selected.contains(l[i].id)) i,
        },
        onSelect: (i, v) {
          if (l[i].status != 'PENDING') {
            return showInfo(context, context.tr('select_rows'));
          }
          setState(
            () => v ? _selected.add(l[i].id) : _selected.remove(l[i].id),
          );
        },
        rows: [
          for (final r in l)
            [
              Text('${r.id}'),
              Text(ar ? r.branchNameAr ?? r.branchName : r.branchName),
              Text('${r.periodNo}'),
              Text(r.glCode),
              Text(ar ? r.glNameAr ?? r.glName : r.glName),
              money(r.previous.toString()),
              money(r.revised.toString()),
              VarianceText(r.difference.toString()),
              Text(fmtPct(r.pct?.toString())),
              StatusChip(r.status),
              Text(
                r.rejectionReason == null
                    ? r.reason
                    : '${r.reason} / ${r.rejectionReason}',
              ),
              Text(r.revisedBy),
              Text(fmtDateTime(r.revisedAt, lang)),
            ],
        ],
      ),
    );
  }
}
