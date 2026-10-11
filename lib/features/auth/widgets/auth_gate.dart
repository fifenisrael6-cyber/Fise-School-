import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/session_service.dart';
import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/sync_service.dart';
import '../../admin/pages/admin_dashboard_page.dart';
import '../../public/pages/public_home_page.dart';
import '../../student/pages/student_main_page.dart';
import '../../../core/services/push_service.dart';
import '../../../models/user_profile.dart';
import '../../teacher/pages/teacher_main_page.dart';
import '../../teacher/pages/teacher_courses_page.dart';
import '../../teacher/pages/teacher_past_papers_page.dart';
import '../../teacher/pages/teacher_qcm_hub_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../share/pages/shared_media_destination_page.dart';

class AuthGate extends StatefulWidget {
  final Locale locale;
  final ValueChanged<Locale> onLanguageChanged;
  final SessionService sessionService;

  const AuthGate({
    super.key,
    required this.locale,
    required this.onLanguageChanged,
    required this.sessionService,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  SessionState _state = const SessionState.loading();
  StreamSubscription<SessionState>? _subscription;
  int _eventCount = 0;
  StreamSubscription<bool>? _connectivitySubscription;
  String? _syncedStudentId;
  StreamSubscription<List<SharedMediaFile>>? _sharedMediaSubscription;
  List<SharedMediaFile>? _sharedFiles;

  @override
  void initState() {
    super.initState();

    _subscription = widget.sessionService.changes.listen((state) {
      _eventCount++;
      _updateState(state);
    });
    _load();
    _sharedMediaSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedMedia, onError: (_) {});
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedMedia)
        .catchError((_) {});
    _connectivitySubscription = ConnectivityService().connectionStream.listen((online) {
      if (online && _state.status == SessionStatus.authenticated) {
        _syncStudentOfflineCache(_state.profile!);
      }
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    final usable = files.where((file) => file.path.trim().isNotEmpty).toList();
    if (!mounted || usable.isEmpty) return;
    setState(() => _sharedFiles = usable);
    ReceiveSharingIntent.instance.reset();
  }

  Future<void> _openSharedDestination(String destination) async {
    final files = _sharedFiles;
    if (files == null || files.isEmpty) return;
    setState(() => _sharedFiles = null);
    final profile = _state.profile;
    if (profile == null) return;
    Widget? page;
    switch (destination) {
      case 'courses':
        if (profile.role.toLowerCase() == 'teacher' || profile.role.toLowerCase() == 'admin') {
          page = TeacherCoursesPage(locale: widget.locale, profile: profile);
        }
        break;
      case 'annals':
        if (profile.role.toLowerCase() == 'teacher' || profile.role.toLowerCase() == 'admin') {
          page = TeacherPastPapersPage(locale: widget.locale, profile: profile);
        }
        break;
      case 'qcm':
        if (profile.role.toLowerCase() == 'teacher' || profile.role.toLowerCase() == 'admin') {
          page = TeacherQcmHubPage(locale: widget.locale, profile: profile);
        }
        break;
      case 'private':
      case 'groups':
        page = MessagesHubPage(locale: widget.locale, profile: profile);
        break;
    }
    if (page != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
    }
  }

  Future<void> _load() async {
    final eventsBefore = _eventCount;
    final state = await widget.sessionService.load();
    // Un événement d'authentification plus récent a déjà mis l'état à jour :
    // on ignore ce résultat ancien pour ne pas revenir à l'accueil.
    if (_eventCount != eventsBefore) {
      return;
    }
    _updateState(state);
  }

  void _updateState(SessionState state) {
    if (!mounted) {
      return;
    }

    setState(() {
      _state = state;
    });

    if (state.status == SessionStatus.authenticated && state.profile != null) {
      PushService.registerForUser(state.profile!.id);
    }

    if (state.status == SessionStatus.authenticated &&
        state.profile?.role.toLowerCase() == 'student') {
      _syncStudentOfflineCache(state.profile!);
    } else if (state.status == SessionStatus.signedOut) {
      _syncedStudentId = null;
    }
  }

  Future<void> _syncStudentOfflineCache(UserProfile profile) async {
    try {
      if (!await ConnectivityService().isOnline()) {
        return;
      }
      final sync = SyncService();
      await sync.syncPendingAssignments(profile.id);
      await sync.syncPendingSmartExercises(profile.id);
      if (_syncedStudentId == profile.id) {
        return;
      }
      _syncedStudentId = profile.id;
      await sync.syncStudentCourses(profile.id);
    } catch (_) {
      // The app remains usable with whatever cache is already available.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _connectivitySubscription?.cancel();
    _sharedMediaSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    switch (_state.status) {
      case SessionStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));

      case SessionStatus.signedOut:
        return PublicHomePage(
          locale: widget.locale,
          onLanguageChanged: widget.onLanguageChanged,
        );

      case SessionStatus.authenticated:
        if (_sharedFiles != null && _sharedFiles!.isNotEmpty) {
          return SharedMediaDestinationPage(
            locale: widget.locale,
            profile: _state.profile!,
            files: _sharedFiles!,
            onChoose: _openSharedDestination,
            onCancel: () => setState(() => _sharedFiles = null),
          );
        }
        return _authenticatedPage(_state, texts);

      case SessionStatus.profileMissing:
        return _messagePage(texts.profileUnavailable, texts);

      case SessionStatus.error:
        return _messagePage(texts.sessionError, texts, detail: _state.message);
    }
  }

  Widget _authenticatedPage(SessionState state, AppTexts texts) {
    final profile = state.profile!;

    switch (profile.role.toLowerCase()) {
      case 'student':
        return StudentMainPage(
          locale: widget.locale,
          profile: profile,
          onSignOut: () async {
            await widget.sessionService.signOut();
          },
        );

      case 'teacher':
        return TeacherMainPage(
          locale: widget.locale,
          profile: profile,
          onSignOut: () async {
            await widget.sessionService.signOut();
          },
        );

      case 'admin':
        return AdminDashboardPage(
          locale: widget.locale,
          onSignOut: () async {
            await widget.sessionService.signOut();
          },
        );

      default:
        return _messagePage(texts.accessDenied, texts);
    }
  }

  Widget _messagePage(String message, AppTexts texts, {String? detail}) {
    return Scaffold(
      appBar: AppBar(title: Text(texts.appName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 54),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  await widget.sessionService.signOut();
                },
                child: Text(texts.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
