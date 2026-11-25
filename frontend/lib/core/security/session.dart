import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/models.dart';

/// Signed-in state. The token lives only in memory (never written to disk or local storage).
class Session {
  final String token;
  final DateTime expiresAt;
  final AppUser user;
  final Company company;
  const Session(this.token, this.expiresAt, this.user, this.company);
  bool can(String permission) => user.permissions.contains(permission);
}

class SessionNotifier extends Notifier<Session?> {
  bool expired = false;

  @override
  Session? build() => null;

  void signIn(Session s) {
    expired = false;
    state = s;
  }

  void signOut({bool becauseExpired = false}) {
    expired = becauseExpired;
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

class LocaleNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  void toggle() => state = state == 'en' ? 'ar' : 'en';
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);
