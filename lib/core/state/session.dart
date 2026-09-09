import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_services.dart';
import '../models/models.dart';

/// Global session state: current user, active team, all teams.
/// Mirrors the web client's useUser context.
class SessionState {
  const SessionState({
    this.status = SessionStatus.bootstrapping,
    this.user,
    this.team,
    this.teams = const [],
    this.needsInit = false,
  });

  final SessionStatus status;
  final User? user;
  final Team? team;
  final List<Team> teams;
  final bool needsInit;

  bool get isLoggedIn => status == SessionStatus.loggedIn && user != null;
  bool get hasTeam => team != null;

  SessionState copyWith({
    SessionStatus? status,
    User? user,
    Team? team,
    List<Team>? teams,
    bool? needsInit,
    bool clearUser = false,
    bool clearTeam = false,
  }) =>
      SessionState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        team: clearTeam ? null : (team ?? this.team),
        teams: teams ?? this.teams,
        needsInit: needsInit ?? this.needsInit,
      );
}

enum SessionStatus { bootstrapping, loggedOut, loggedIn }

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    return const SessionState();
  }

  ApiServices get _api => ref.read(apiProvider);

  /// Bootstrap on app start: probes /user/me.
  Future<void> bootstrap() async {
    state = SessionState(status: SessionStatus.bootstrapping);
    try {
      final me = await _api.me();
      if (me.user.id != 0) {
        state = SessionState(
          status: SessionStatus.loggedIn,
          user: me.user,
          team: me.team,
          teams: me.teams,
        );
      } else {
        state = SessionState(status: SessionStatus.loggedOut);
      }
    } on ApiException catch (e) {
      if (e.code == 'init_required') {
        state = SessionState(status: SessionStatus.loggedOut, needsInit: true);
        return;
      }
      // Dev convenience (flutter run --dart-define): auto-login demo account.
      if (e.code == 'login') {
        await _tryDemoLogin();
        return;
      }
      // Server unreachable etc: stay logged out so user can fix the URL.
      state = SessionState(status: SessionStatus.loggedOut);
    }
  }

  static const _demoEmail = String.fromEnvironment('MOSONA_DEMO_EMAIL');
  static const _demoPass = String.fromEnvironment('MOSONA_DEMO_PASS');

  Future<void> _tryDemoLogin() async {
    if (_demoEmail.isEmpty || _demoPass.isEmpty) {
      state = SessionState(status: SessionStatus.loggedOut);
      return;
    }
    try {
      final env = await _api.login(_demoEmail, _demoPass, rememberMe: true);
      if (env.isOk) {
        await bootstrap();
        return;
      }
      if (env.code == '2fa_required' || env.code == 'verify') {
        // demo account has no 2FA; treat as failure
      }
    } on ApiException {
      // fall through to logged out
    }
    state = SessionState(status: SessionStatus.loggedOut);
  }

  /// Called after a successful login / 2FA completion.
  Future<void> afterLogin() => bootstrap();

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {}
    state = SessionState(status: SessionStatus.loggedOut);
  }

  Future<void> switchTeam(int teamId) async {
    await _api.setActiveTeam(teamId);
    await bootstrap();
  }

  Future<void> refresh() => bootstrap();
}

final sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Team-scoped lookups (categories / keys / alerts) refreshed together.
class TeamDataState {
  const TeamDataState({this.categories = const [], this.keys = const [], this.loaded = false});

  final List<Category> categories;
  final List<SshKey> keys;
  final bool loaded;
}

class TeamDataController extends Notifier<TeamDataState> {
  @override
  TeamDataState build() {
    final sess = ref.watch(sessionProvider.select((s) => s.hasTeam));
    if (!sess) return const TeamDataState();
    Future.microtask(refresh);
    return const TeamDataState();
  }

  ApiServices get _api => ref.read(apiProvider);

  Future<void> refresh() async {
    try {
      final results = await Future.wait([_api.categoryList(), _api.keyList()]);
      state = TeamDataState(
        categories: results[0] as List<Category>,
        keys: results[1] as List<SshKey>,
        loaded: true,
      );
    } catch (_) {
      state = TeamDataState(loaded: true);
    }
  }
}

final teamDataProvider =
    NotifierProvider<TeamDataController, TeamDataState>(TeamDataController.new);

/// Simple observable for one-off global events (e.g. servers changed).
class MutationBus extends ChangeNotifier {
  int _serversVersion = 0;
  int get serversVersion => _serversVersion;

  void notifyServersChanged() {
    _serversVersion++;
    notifyListeners();
  }
}

final mutationBusProvider = Provider<MutationBus>((ref) {
  final bus = MutationBus();
  ref.onDispose(bus.dispose);
  return bus;
});
