import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/env.dart';
import '../../core/localization/strings.dart';
import '../../core/network/in_browser_backend.dart';
import '../../core/security/session.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/common.dart';
import '../../shared/models/models.dart';
import '../../shared/repositories/budget_repository.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _tenant = TextEditingController(text: Env.defaultTenant);
  final _user = TextEditingController();
  final _pass = TextEditingController();

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final r = await ref
        .read(repoProvider)
        .login(_tenant.text.trim(), _user.text.trim(), _pass.text);
    ref
        .read(sessionProvider.notifier)
        .signIn(
          Session(
            r['token'],
            DateTime.parse(r['expires_at']),
            AppUser.fromJson(r['user']),
            Company.fromJson(r['company']),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final expired = ref.read(sessionProvider.notifier).expired;
    String? req(String? v) =>
        (v == null || v.trim().isEmpty) ? context.tr('required') : null;
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('app_title'),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: AppColors.navy),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: () =>
                              ref.read(localeProvider.notifier).toggle(),
                          child: Text(context.tr('language')),
                        ),
                      ),
                      if (Env.inBrowserBackend) const _DemoPanel(),
                      if (expired)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            context.tr('session_expired'),
                            style: const TextStyle(color: AppColors.warning),
                          ),
                        ),
                      TextFormField(
                        controller: _tenant,
                        decoration: InputDecoration(
                          labelText: context.tr('tenant'),
                        ),
                        validator: req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('username'),
                        controller: _user,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: context.tr('username'),
                        ),
                        validator: req,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('password'),
                        controller: _pass,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: context.tr('password'),
                        ),
                        validator: req,
                        onFieldSubmitted: (_) => _login().catchError((e) {
                          if (context.mounted) showError(context, e);
                        }),
                      ),
                      const SizedBox(height: 20),
                      BusyButton(
                        label: context.tr('login'),
                        icon: Icons.login,
                        filled: true,
                        onPressed: _login,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// GitHub Pages demo: starts the in-browser backend, lists demo users, offers a data reset.
class _DemoPanel extends StatefulWidget {
  const _DemoPanel();
  @override
  State<_DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends State<_DemoPanel> {
  late final Future<void> _ready = browserBackendReady();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.header,
      borderRadius: BorderRadius.circular(8),
    ),
    child: FutureBuilder<void>(
      future: _ready,
      builder: (c, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('demo_title'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          if (s.connectionState != ConnectionState.done) ...[
            Text(context.tr('demo_starting')),
            const SizedBox(height: 6),
            const LinearProgressIndicator(),
          ] else if (s.hasError)
            Text(
              '${s.error}',
              style: const TextStyle(color: AppColors.unfavourable),
            )
          else ...[
            Text(context.tr('demo_users')),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () async {
                  if (await confirmDialog(
                    context,
                    context.tr('demo_reset_confirm'),
                  )) {
                    await resetBrowserBackend();
                  }
                },
                child: Text(context.tr('demo_reset')),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
