import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/assignment_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/notification.dart';
import '../../../models/user_profile.dart';
import '../../admin/pages/admin_timetable_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../student/pages/assignment_detail_page.dart';
import '../../student/pages/assignments_page.dart';
import '../../student/pages/bulletin_page.dart';
import '../../student/pages/course_detail_page.dart';
import '../../student/pages/courses_page.dart';
import '../../student/pages/student_evaluations_page.dart';
import '../../student/pages/timetable_page.dart';
import '../../teacher/pages/teacher_evaluations_page.dart';
import '../../teacher/pages/teacher_qcm_hub_page.dart';
import '../../teacher/pages/teacher_timetable_page.dart';

class NotificationsPage extends StatefulWidget {
  final Locale locale;
  final String userId;
  final UserProfile? profile;
  final NotificationService? notificationService;
  final String? initialNotificationId;
  final String? initialType;
  final String? initialTargetType;
  final String? initialTargetId;

  const NotificationsPage({
    super.key,
    required this.locale,
    required this.userId,
    this.profile,
    this.notificationService,
    this.initialNotificationId,
    this.initialType,
    this.initialTargetType,
    this.initialTargetId,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationService _service =
      widget.notificationService ?? NotificationService();

  late Future<List<AppNotification>> _future = _service.listForUser(widget.userId);
  RealtimeChannel? _realtime;
  bool _initialNotificationHandled = false;

  @override
  void initState() {
    super.initState();
    final channel = Supabase.instance.client.channel('notifications-${widget.userId}');
    _realtime = channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (_) {
            if (mounted) setState(() => _future = _service.listForUser(widget.userId));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _realtime?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(onPressed: _markAll, child: Text(texts.markAllRead)),
        ],
      ),
      body: FutureBuilder<List<AppNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(texts.notificationsError));
          }

          final items = snapshot.data ?? const <AppNotification>[];
          if (!_initialNotificationHandled &&
              (widget.initialNotificationId != null || widget.initialType != null)) {
            AppNotification? match;
            for (final item in items) {
              if (item.id == widget.initialNotificationId) {
                match = item;
                break;
              }
            }
            final selectedNotification = match;
            _initialNotificationHandled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (selectedNotification != null) {
                _openNotification(selectedNotification);
              } else {
                _openTarget(
                  type: widget.initialType ?? 'info',
                  targetType: widget.initialTargetType,
                  targetId: widget.initialTargetId,
                );
              }
            });
          }

          if (items.isEmpty) {
            return Center(child: Text(texts.noNotifications));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                tileColor: item.isRead ? null : const Color(0xFFEAF5ED),
                leading: CircleAvatar(child: Icon(_iconFor(item.type))),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${item.body}\n${_formatTime(item.createdAt)}'),
                isThreeLine: true,
                onTap: () => _openNotification(item),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openNotification(AppNotification item) async {
    try {
      await _service.markRead(item.id);
    } catch (_) {
      // Navigation must still work if the read receipt cannot sync.
    }
    if (!mounted) return;
    setState(() => _future = _service.listForUser(widget.userId));
    await _openTarget(
      type: item.type,
      targetType: item.targetType,
      targetId: item.targetId,
    );
  }

  Future<void> _openTarget({
    required String type,
    String? targetType,
    String? targetId,
  }) async {
    final profile = widget.profile;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.locale.languageCode == 'fr'
            ? 'Connectez-vous pour ouvrir ce contenu.'
            : 'Sign in to open this content.')),
      );
      return;
    }

    final kind = type.toLowerCase();
    final target = (targetType ?? '').toLowerCase();
    final isTeacher = profile.role == 'teacher';
    final isAdmin = profile.role == 'admin';

    if (target == 'group' ||
        target == 'private_message' ||
        kind == 'message' ||
        kind == 'group_member') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MessagesHubPage(
          locale: widget.locale,
          profile: profile,
          initialTargetType: target.isEmpty
              ? (kind == 'group_member' ? 'group' : null)
              : target,
          initialTargetId: targetId,
        ),
      ));
      return;
    }

    if (target == 'evaluation' || kind.startsWith('evaluation_')) {
      if (kind == 'evaluation_review' || isTeacher || isAdmin) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherEvaluationsPage(
            locale: widget.locale,
            profile: profile,
          ),
        ));
      } else {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StudentEvaluationsPage(
            locale: widget.locale,
            profile: profile,
          ),
        ));
      }
      return;
    }

    if (kind == 'submission' || target == 'assignment_submission') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TeacherQcmHubPage(
          locale: widget.locale,
          profile: profile,
        ),
      ));
      return;
    }

    if (kind == 'assignment' || target == 'assignment') {
      if (!isTeacher && !isAdmin && targetId != null) {
        try {
          final assignments = await AssignmentService().listStudentAssignments(
            studentId: profile.id,
          );
          for (final assignment in assignments) {
            if (assignment.id == targetId && mounted) {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AssignmentDetailPage(
                  locale: widget.locale,
                  profile: profile,
                  assignment: assignment,
                ),
              ));
              return;
            }
          }
        } catch (_) {
          // Open the assignment list if the exact item is not in the local list.
        }
      }
      if (isTeacher || isAdmin) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherQcmHubPage(locale: widget.locale, profile: profile),
        ));
      } else {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AssignmentsPage(locale: widget.locale, profile: profile),
        ));
      }
      return;
    }

    if (kind == 'course' || target == 'course') {
      if (targetId != null) {
        try {
          final course = await CourseService().getCourse(targetId);
          if (!mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CourseDetailPage(
              locale: widget.locale,
              profile: profile,
              course: course,
            ),
          ));
          return;
        } catch (_) {
          // Legacy notifications may not carry a resolvable course ID.
        }
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CoursesPage(locale: widget.locale, profile: profile),
      ));
      return;
    }

    if (kind == 'timetable' || target == 'timetable') {
      final page = isAdmin
          ? AdminTimetablePage(locale: widget.locale)
          : isTeacher
              ? TeacherTimetablePage(locale: widget.locale, profile: profile)
              : TimetablePage(locale: widget.locale, profile: profile);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      return;
    }

    if (kind == 'bulletin' || target == 'bulletin_period') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BulletinPage(
          locale: widget.locale,
          studentId: profile.id,
          studentName: '${profile.firstName} ${profile.lastName}'.trim(),
          className: profile.className,
        ),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.locale.languageCode == 'fr'
          ? 'Le contenu associé à cette notification n’est pas disponible.'
          : 'The content linked to this notification is unavailable.')),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'assignment': return Icons.assignment_outlined;
      case 'course': return Icons.menu_book_outlined;
      case 'timetable': return Icons.calendar_month_outlined;
      case 'forum': return Icons.chat_bubble_outline;
      case 'submission': return Icons.task_alt_outlined;
      case 'evaluation_new':
      case 'evaluation_receipt':
      case 'evaluation_review':
      case 'evaluation_result':
      case 'evaluation_reminder': return Icons.fact_check_outlined;
      case 'bulletin': return Icons.grading_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _markAll() async {
    await _service.markAllRead(widget.userId);
    if (mounted) {
      setState(() => _future = _service.listForUser(widget.userId));
    }
  }
}
