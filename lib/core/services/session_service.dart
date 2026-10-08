import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../offline/course_offline_service.dart';
import '../offline/offline_repository.dart';
import 'profile_service.dart';
import 'push_service.dart';

enum SessionStatus { loading, signedOut, authenticated, profileMissing, error }

class SessionState {
  final SessionStatus status;
  final UserProfile? profile;
  final String? message;

  const SessionState._(this.status, {this.profile, this.message});

  const SessionState.loading() : this._(SessionStatus.loading);

  const SessionState.signedOut() : this._(SessionStatus.signedOut);

  const SessionState.authenticated(UserProfile profile)
    : this._(SessionStatus.authenticated, profile: profile);

  const SessionState.profileMissing() : this._(SessionStatus.profileMissing);

  const SessionState.error(String message)
    : this._(SessionStatus.error, message: message);
}

abstract interface class SessionService {
  Future<SessionState> load();

  Stream<SessionState> get changes;

  Future<void> signOut();
}

class UnavailableSessionService implements SessionService {
  const UnavailableSessionService();

  @override
  Future<SessionState> load() async => const SessionState.signedOut();

  @override
  Stream<SessionState> get changes => const Stream<SessionState>.empty();

  @override
  Future<void> signOut() async {}
}

class SupabaseSessionService implements SessionService {
  final ProfileService _profileService;

  SupabaseSessionService({ProfileService? profileService})
    : _profileService = profileService ?? ProfileService();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<SessionState> load() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        return const SessionState.signedOut();
      }

      final profile = await _fetchProfile();
      if (profile == null) {
        return const SessionState.profileMissing();
      }
      return SessionState.authenticated(profile);
    } on AuthException catch (error) {
      return SessionState.error(error.message);
    } catch (error) {
      return SessionState.error(error.toString());
    }
  }

  /// Le profil est créé par un trigger côté Supabase : juste après une
  /// connexion ou une inscription il peut apparaître avec un léger retard.
  /// On réessaie donc une fois avant de conclure qu'il est absent.
  Future<UserProfile?> _fetchProfile() async {
    var profile = await _profileService.getCurrentProfile();
    if (profile == null) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      profile = await _profileService.getCurrentProfile();
    }
    return profile;
  }

  /// Chaque événement d'authentification (connexion, déconnexion, jeton
  /// rafraîchi...) recalcule l'état. Une erreur du flux ne doit jamais le
  /// couper (sinon l'écran reste figé sur l'accueil après la connexion), et un
  /// résultat ancien ne doit jamais écraser un résultat plus récent.
  @override
  Stream<SessionState> get changes {
    late final StreamController<SessionState> controller;
    StreamSubscription<AuthState>? subscription;
    var generation = 0;

    Future<void> refresh() async {
      final current = ++generation;
      final state = await load();
      if (current == generation && !controller.isClosed) {
        controller.add(state);
      }
    }

    controller = StreamController<SessionState>(
      onListen: () {
        subscription = _client.auth.onAuthStateChange.listen(
          (_) => refresh(),
          onError: (Object _) => refresh(),
        );
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> signOut() async {
    try {
      await PushService.unregister();
    } catch (_) {
      // Push-token cleanup must not prevent local sign-out.
    }
    // Do not leave another user's downloaded courses on a shared device.
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        await CourseOfflineService().deleteUserFiles(userId);
      }
      await OfflineRepository().clearCourses();
      await OfflineRepository().clearLessons();
      await OfflineRepository().clearProgress();
    } catch (_) {
      // Signing out must still succeed if local cache cleanup fails.
    }
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}
