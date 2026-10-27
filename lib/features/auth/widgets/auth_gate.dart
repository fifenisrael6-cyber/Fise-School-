import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/session_service.dart';
import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/pending_progress.dart';
import '../../../core/offline/sync_service.dart';
import '../../admin/pages/admin_dashboard_page.dart';
import '../../public/pages/public_home_page.dart';
import '../../student/pages/student_main_page.dart';
import '../../../core/services/push_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/user_profile.dart';
import '../../teacher/pages/teacher_main_page.dart';
import '../../teacher/pages/create_course_page.dart';
import '../../teacher/pages/teacher_past_papers_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../messages/pages/private_messages_page.dart';
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
  String? _syncingStudentId;
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;
  List<SharedMediaFile> _pendingSharedFiles = const [];
  bool _shareRouteOpen = false;

  @override
  void initState() {
    super.initState();

    _subscription = widget.sessionService.changes.listen((state) {
      _eventCount++;
      _updateState(state);
    });
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
      onError: (Object error) => debugPrint('Shared media stream failed: $error'),
    );
    unawaited(_loadInitialSharedFiles());
    _load();
    _connectivitySubscription = ConnectivityService().connectionStream.listen((online) {
      if (online && _state.status == SessionStatus.authenticated) {
        _syncStudentOfflineCache(_state.profile!);
      }
    });
  }


  Future<void> _loadInitialSharedFiles() async {
    try {
      final files = await ReceiveSharingIntent.instance.getInitialMedia();
      if (files.isNotEmpty) _handleSharedFiles(files);
    } catch (error) {
      debugPrint('Could not read initial shared media: $error');
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty || !mounted) return;
    setState(() => _pendingSharedFiles = List<SharedMediaFile>.unmodifiable(files));
    if (_state.status == SessionStatus.authenticated && !_shareRouteOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedMediaDestination());
    }
  }

  String _mimeForSharedName(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'mp4':
      case 'm4v': return 'video/mp4';
      case 'mov': return 'video/quicktime';
      case 'mp3': return 'audio/mpeg';
      case 'wav': return 'audio/wav';
      case 'm4a': return 'audio/mp4';
      case 'aac': return 'audio/aac';
      case 'ogg':
      case 'opus': return 'audio/ogg';
      default: return 'application/octet-stream';
    }
  }

  Future<List<PickedAttachment>> _readSharedAttachments(List<SharedMediaFile> files) async {
    final attachments = <PickedAttachment>[];
    for (final file in files) {
      final path = file.path?.trim() ?? '';
      if (path.isEmpty) continue;
      try {
        final bytes = await File(path).readAsBytes();
        if (bytes.isEmpty) continue;
        final name = path.split('/').last;
        final mime = file.mimeType?.trim();
        attachments.add(PickedAttachment(
          bytes: bytes,
          name: name.isEmpty ? 'shared-file' : name,
          mimeType: mime == null || mime.isEmpty ? _mimeForSharedName(name) : mime,
        ));
      } catch (error) {
        debugPrint('Could not read shared file $path: $error');
      }
    }
    return attachments;
  }

  Future<void> _openSharedMediaDestination() async {
    if (!mounted || _shareRouteOpen || _pendingSharedFiles.isEmpty ||
        _state.status != SessionStatus.authenticated || _state.profile == null) {
      return;
    }
    final files = _pendingSharedFiles;
    _pendingSharedFiles = const [];
    final profile = _state.profile!;
    _shareRouteOpen = true;
    String? destination;
    try {
      destination = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (routeContext) => SharedMediaDestinationPage(
            locale: widget.locale,
            profile: profile,
            files: files,
            onChoose: (value) => Navigator.of(routeContext).pop(value),
            onCancel: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not open shared media destination: $error');
    } finally {
      _shareRouteOpen = false;
    }

    try {
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {}

    if (!mounted || destination == null) {
      if (mounted && _pendingSharedFiles.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedMediaDestination());
      }
      return;
    }

    final attachments = await _readSharedAttachments(files);
    if (!mounted) return;
    if (attachments.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(widget.locale.languageCode == 'fr'
            ? 'Impossible de lire le fichier partagé. Réessayez depuis le fichier original.'
            : 'Could not read the shared file. Please share it again from the original app.'),
      ));
      return;
    }

    final first = attachments.first;
    final role = profile.role.toLowerCase();
    final Route<void>? route = switch (destination) {
      'courses' when role == 'teacher' || role == 'admin' =>
        MaterialPageRoute<void>(builder: (_) => CreateCoursePage(
          locale: widget.locale, profile: profile, initialSharedAttachments: attachments,
        )),
      'annals' when role == 'teacher' || role == 'admin' =>
        MaterialPageRoute<void>(builder: (_) => TeacherPastPapersPage(
          locale: widget.locale, profile: profile, initialSharedAttachments: attachments,
        )),
      'private' => MaterialPageRoute<void>(builder: (_) => PrivateMessagesPage(
        locale: widget.locale, profile: profile, initialAttachment: first,
      )),
      'groups' => MaterialPageRoute<void>(builder: (_) => MessagesHubPage(
        locale: widget.locale, profile: profile, initialSharedAttachment: first,
      )),
      _ => null,
    };
    if (route != null) {
      if ((destination == 'private' || destination == 'groups') && attachments.length > 1) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(widget.locale.languageCode == 'fr'
              ? 'La messagerie accepte une pièce jointe par message. Le premier fichier est prêt à être envoyé.'
              : 'Messaging accepts one attachment per message. The first file is ready to send.'),
        ));
      }
      await Navigator.of(context).push(route);
    }

    if (mounted && _pendingSharedFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedMediaDestination());
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
        _pendingSharedFiles.isNotEmpty && !_shareRouteOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedMediaDestination());
    }

    if (state.status == SessionStatus.authenticated &&
        state.profile?.role.toLowerCase() == 'student') {
      _syncStudentOfflineCache(state.profile!);
    } else if (state.status == SessionStatus.signedOut) {
      _syncedStudentId = null;
    }
  }

  Future<void> _syncStudentOfflineCache(UserProfile profile) async {
    if (_syncingStudentId == profile.id) return;
    try {
      if (!await ConnectivityService().isOnline()) return;
      _syncingStudentId = profile.id;
      // Also flush progress queued before the session finished restoring.
      // Connectivity events can arrive before authentication is ready.
      await PendingProgress.instance.flush(Supabase.instance.client);
      final sync = SyncService();
      await sync.syncPendingAssignments(profile.id);
      await sync.syncPendingSmartExercises(profile.id);
      if (_syncedStudentId == profile.id) {
        await sync.retryChapterMediaPrefetch(profile.id);
        return;
      }
      await sync.syncStudentCourses(profile.id);
      _syncedStudentId = profile.id;
    } catch (_) {
      // The app remains usable with whatever cache is already available.
    } finally {
      if (_syncingStudentId == profile.id) _syncingStudentId = null;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _shareSubscription?.cancel();
    _connectivitySubscription?.cancel();
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
        return _authenticatedPage(_state, texts);

      case SessionStatus.profileMissing:
        return _messagePage(texts.profileUnavailable, texts, canRetry: true);

      case SessionStatus.error:
        return _messagePage(
          texts.sessionError,
          texts,
          detail: _state.message,
          canRetry: true,
        );
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

  Widget _messagePage(
    String message,
    AppTexts texts, {
    String? detail,
    bool canRetry = false,
  }) {
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
              // Le détail technique (en anglais) n'est utile qu'au développeur.
              if (detail != null && kDebugMode) ...[
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              if (canRetry) ...[
                FilledButton(
                  onPressed: () {
                    setState(() => _state = const SessionState.loading());
                    _load();
                  },
                  child: Text(texts.retry),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    await widget.sessionService.signOut();
                  },
                  child: Text(texts.signOut),
                ),
              ] else
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
