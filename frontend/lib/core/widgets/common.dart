import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../localization/strings.dart';
import '../network/api_client.dart';
import '../theme/theme.dart';
import '../utils/format.dart';

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.unfavourable,
      content: Text(e is ApiException ? e.message : '$e'),
    ),
  );
}

void showInfo(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Loading / error / empty states for any AsyncValue.
class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
  });

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    ),
    error: (e, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.unfavourable,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              e is ApiException ? e.message : '$e',
              textAlign: TextAlign.center,
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(context.tr('retry'))),
          ],
        ),
      ),
    ),
    data: (d) => (isEmpty?.call(d) ?? false)
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(context.tr('no_data')),
            ),
          )
        : builder(d),
  );
}

/// Button that disables itself while its async action runs (prevents duplicate submissions).
class BusyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  final bool filled;
  const BusyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = false,
  });
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onPressed == null || _busy ? null : _run;
    final icon = _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.check, size: 18);
    return widget.filled
        ? FilledButton.icon(
            onPressed: onTap,
            icon: icon,
            label: Text(widget.label),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: icon,
            label: Text(widget.label),
          );
  }
}

Future<bool> confirmDialog(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('confirm')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.tr('no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.tr('yes')),
          ),
        ],
      ),
    ) ??
    false;

/// Asks for remarks; when [required] the OK button stays disabled until text is entered.
Future<String?> reasonDialog(
  BuildContext context,
  String title, {
  bool required = true,
}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctl,
            autofocus: true,
            maxLines: 3,
            maxLength: 1000,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(
              labelText: c.tr('reason'),
              helperText: required ? c.tr('rejection_required') : null,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.tr('cancel')),
          ),
          FilledButton(
            onPressed: required && ctl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(c, ctl.text.trim()),
            child: Text(c.tr('ok')),
          ),
        ],
      ),
    ),
  );
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'APPROVED' || 'FAVOURABLE' => AppColors.favourable,
      'SUBMITTED' || 'PENDING' => AppColors.warning,
      'REJECTED' || 'UNFAVOURABLE' || 'UNBUDGETED' => AppColors.unfavourable,
      _ => AppColors.navyLight,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.tr(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class ProvisionalBanner extends StatelessWidget {
  final bool show;
  const ProvisionalBanner(this.show, {super.key});
  @override
  Widget build(BuildContext context) => !show
      ? const SizedBox.shrink()
      : Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          color: AppColors.warning.withValues(alpha: 0.12),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('provisional'),
                  style: const TextStyle(color: AppColors.warning),
                ),
              ),
            ],
          ),
        );
}

/// Money text coloured by favourable (true) / unfavourable (false).
class VarianceText extends StatelessWidget {
  final Object? value;
  final bool? favourable;
  final bool pct;
  const VarianceText(
    this.value, {
    super.key,
    this.favourable,
    this.pct = false,
  });
  @override
  Widget build(BuildContext context) {
    final fav = favourable ?? (dec(value)?.sign ?? 0) >= 0;
    return Text(
      pct ? fmtPct(value) : fmtMoney(value),
      textAlign: TextAlign.end,
      semanticsLabel:
          '${pct ? fmtPct(value) : fmtMoney(value)} ${context.tr(fav ? 'favourable' : 'unfavourable')}',
      style: TextStyle(
        color: value == null
            ? null
            : (fav ? AppColors.favourable : AppColors.unfavourable),
      ),
    );
  }
}

/// Page frame: title row with actions, then body.
class PageFrame extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget child;
  const PageFrame({
    super.key,
    required this.title,
    this.actions = const [],
    required this.child,
  });

  /// Phones and narrow windows: one swipeable action row, and the page scrolls with a minimum body height
  /// so grids and charts keep a usable size.
  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700;

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrow(context);
    final heading = Text(
      title,
      style:
          (narrow
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineSmall)
              ?.copyWith(color: AppColors.navy),
    );
    if (!narrow) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                heading,
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
            const Divider(height: 24),
            Expanded(child: child),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final a in actions)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: a,
                    ),
                ],
              ),
            ),
            const Divider(height: 20),
            SizedBox(
              height: box.maxHeight < 760 ? 760 : box.maxHeight - 120,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic data grid: header + rows, both-axis scroll, optional sorting and row tap.
class DataGrid extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<bool> numeric;
  final int? sortColumn;
  final bool sortAscending;
  final void Function(int column, bool ascending)? onSort;
  final void Function(int row)? onRowTap;
  final Set<int>? selected;
  final void Function(int row, bool selected)? onSelect;
  const DataGrid({
    super.key,
    required this.headers,
    required this.rows,
    required this.numeric,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
    this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final table = DataTable(
      sortColumnIndex: sortColumn,
      sortAscending: sortAscending,
      columnSpacing: 20,
      headingRowHeight: 40,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 48,
      showCheckboxColumn: onSelect != null,
      border: const TableBorder(
        horizontalInside: BorderSide(color: AppColors.grid),
      ),
      columns: [
        for (var i = 0; i < headers.length; i++)
          DataColumn(
            label: Text(
              headers[i],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            numeric: numeric[i],
            onSort: onSort == null ? null : (c, asc) => onSort!(c, asc),
          ),
      ],
      rows: [
        for (var r = 0; r < rows.length; r++)
          DataRow(
            selected: selected?.contains(r) ?? false,
            onSelectChanged: onSelect != null
                ? (v) => onSelect!(r, v ?? false)
                : (onRowTap == null ? null : (_) => onRowTap!(r)),
            cells: rows[r].map((w) => DataCell(w)).toList(),
          ),
      ],
    );
    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    );
  }
}

Widget money(Object? v, {bool bold = false}) => Text(
  fmtMoney(v),
  textAlign: TextAlign.end,
  style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
);

/// Date picker field.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: InkWell(
      onTap: !enabled
          ? null
          : () async {
              final d = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) onChanged(d);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          enabled: enabled,
        ),
        child: Text(value == null ? '' : isoDate(value!)),
      ),
    ),
  );
}
