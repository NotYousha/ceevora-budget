import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/localization/strings.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/budget_repository.dart';

/// Administrator: role-permission matrix and segregation-of-duties switch (server-enforced).
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});
  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  late Future<Json> _load = ref.read(repoProvider).permissions();
  Map<String, Set<String>>? _matrix;
  bool _sod = true;

  @override
  Widget build(BuildContext context) => PageFrame(
    title: context.tr('nav_admin'),
    actions: [
      BusyButton(
        label: context.tr('save'),
        icon: Icons.save,
        filled: true,
        onPressed: _matrix == null
            ? null
            : () async {
                await ref
                    .read(repoProvider)
                    .savePermissions(
                      _matrix!.map((k, v) => MapEntry(k, v.toList())),
                    );
                await ref.read(repoProvider).saveSettings(_sod);
                if (context.mounted) showInfo(context, context.tr('saved'));
              },
      ),
      OutlinedButton(
        onPressed: () => setState(() {
          _matrix = null;
          _load = ref.read(repoProvider).permissions();
        }),
        child: Text(context.tr('cancel')),
      ),
    ],
    child: FutureBuilder<Json>(
      future: _load,
      builder: (c, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final j = s.data!;
        final roles = List<String>.from(j['roles']);
        final perms = List<String>.from(j['permissions']);
        _matrix ??= {
          for (final r in roles) r: Set<String>.from(j['matrix'][r] ?? []),
        };
        if (_matrix!.isNotEmpty &&
            s.connectionState == ConnectionState.done &&
            !_init) {
          _init = true;
          _sod = j['sod_enforced'] == true;
        }
        return ListView(
          children: [
            SwitchListTile(
              value: _sod,
              title: Text(context.tr('sod')),
              onChanged: (v) => setState(() => _sod = v),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('permissions'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(context.tr('role'))),
                  ...perms.map((p) => DataColumn(label: Text(p))),
                ],
                rows: [
                  for (final r in roles)
                    DataRow(
                      cells: [
                        DataCell(Text(r)),
                        for (final p in perms)
                          DataCell(
                            Checkbox(
                              value: _matrix![r]!.contains(p),
                              semanticLabel: '$r $p',
                              // ADMIN keeps ADMIN_CONFIG so nobody can lock the module out.
                              onChanged: r == 'ADMIN' && p == 'ADMIN_CONFIG'
                                  ? null
                                  : (v) => setState(
                                      () => v!
                                          ? _matrix![r]!.add(p)
                                          : _matrix![r]!.remove(p),
                                    ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  bool _init = false;
}
