import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/utils/export.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/providers.dart';

/// Screens 01A / 01B: read-only approval and revision history with version filter and Excel export.
Future<void> showHistoryDialog(BuildContext context, Budget budget) =>
    showDialog(
      context: context,
      builder: (_) => HistoryDialog(budget: budget),
    );

class HistoryDialog extends ConsumerStatefulWidget {
  final Budget budget;
  const HistoryDialog({super.key, required this.budget});
  @override
  ConsumerState<HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends ConsumerState<HistoryDialog>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  int? _version;

  @override
  Widget build(BuildContext context) {
    final b = widget.budget;
    final lang = context.isArabic ? 'ar' : 'en';
    final approvals = ref.watch(
      approvalHistoryProvider((budget: b.id, version: _version)),
    );
    final revisions = ref.watch(
      revisionHistoryProvider((budget: b.id, version: _version, status: null)),
    );
    final aHead = [
      'action_at',
      'action',
      'prev_status',
      'new_status',
      'version',
      'user',
      'remarks',
      'rejection_reason',
    ];
    final rHead = [
      'version',
      'branch',
      'period',
      'gl_code',
      'gl_description',
      'original_amount',
      'prev_approved',
      'revised_amount',
      'difference',
      'pct',
      'status',
      'reason',
      'revised_by',
      'revised_at',
      'approved_by',
      'approved_at',
    ];
    List<List<Object?>> aRows(List<ApprovalHistory> l) => [
      for (final h in l)
        [
          fmtDateTime(h.actionAt, lang),
          h.action,
          h.prevStatus ?? '',
          h.newStatus ?? '',
          h.versionNo,
          h.actionBy,
          h.remarks ?? '',
          h.rejectionReason ?? '',
        ],
    ];
    List<List<Object?>> rRows(List<RevisionHistory> l) => [
      for (final r in l)
        [
          r.versionNo ?? '-',
          context.isArabic ? (r.branchNameAr ?? r.branchName) : r.branchName,
          r.periodNo,
          r.glCode,
          context.isArabic ? (r.glNameAr ?? r.glName) : r.glName,
          r.original.toDouble(),
          r.previous.toDouble(),
          r.revised.toDouble(),
          r.difference.toDouble(),
          r.pct == null ? 'N/A' : fmtPct(r.pct.toString()),
          r.status,
          r.reason,
          r.revisedBy,
          fmtDateTime(r.revisedAt, lang),
          r.approvedBy ?? '',
          fmtDateTime(r.approvedAt, lang),
        ],
    ];
    Future<void> export() async {
      final first = _tabs.index == 0;
      final rows = first
          ? aRows(approvals.value ?? [])
          : rRows(revisions.value ?? []);
      await exportExcel(
        ExportTable(
          '${b.budgetNo} ${context.tr(first ? 'approval_history' : 'revision_history')}',
          [
            '${b.budgetName} (${b.finYear})',
            '${context.tr('version')}: ${_version ?? context.tr('all_versions')}',
          ],
          (first ? aHead : rHead).map(context.tr).toList(),
          rows,
        ),
      );
    }

    Widget grid(
      List<String> head,
      List<List<Object?>> rows,
      Set<int> numericCols,
    ) => DataGrid(
      headers: head.map(context.tr).toList(),
      numeric: [for (var i = 0; i < head.length; i++) numericCols.contains(i)],
      rows: [
        for (final r in rows)
          [
            for (var i = 0; i < r.length; i++)
              numericCols.contains(i) && r[i] is double
                  ? Text(fmtMoney(r[i].toString()))
                  : (head[i] == 'status' || head[i] == 'action' && false)
                  ? StatusChip('${r[i]}')
                  : Text('${r[i] ?? ''}'),
          ],
      ],
    );

    return Dialog(
      child: SizedBox(
        width: 1200,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${b.budgetNo} - ${b.budgetName}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      initialValue: _version,
                      decoration: InputDecoration(
                        labelText: context.tr('version'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(context.tr('all_versions')),
                        ),
                        for (var v = 0; v <= b.versionNo; v++)
                          DropdownMenuItem(value: v, child: Text('v$v')),
                      ],
                      onChanged: (v) => setState(() => _version = v),
                    ),
                  ),
                  BusyButton(
                    label: context.tr('export_excel'),
                    icon: Icons.table_view,
                    onPressed: export,
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('close')),
                  ),
                ],
              ),
              TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: context.tr('approval_history')),
                  Tab(text: context.tr('revision_history')),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    AsyncView(
                      value: approvals,
                      isEmpty: (l) => l.isEmpty,
                      builder: (l) => grid(aHead, aRows(l), const {4}),
                    ),
                    AsyncView(
                      value: revisions,
                      isEmpty: (l) => l.isEmpty,
                      builder: (l) => grid(rHead, rRows(l), const {5, 6, 7, 8}),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
