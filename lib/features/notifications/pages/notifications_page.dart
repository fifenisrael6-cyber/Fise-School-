import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/notification_service.dart';
import '../../../models/notification.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/user_profile.dart';
import '../../student/pages/course_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  final Locale locale;
  final String userId;
  final NotificationService? notificationService;

  const NotificationsPage({
    super.key,
    required this.locale,
    required this.userId,
    this.notificationService,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationService _service =
      widget.notificationService ?? NotificationService();

  late Future<List<AppNotification>> _future = _service.listForUser(widget.userId);
  RealtimeChannel? _realtime;

  @override
  void initState() {
    super.initState();
    final channel = Supabase.instance.client.channel('notifications-${widget.userId}');
    _realtime = channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) {
            if (mounted) {
              setState(() => _future = _service.listForUser(widget.userId));
            }
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
        title: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snapshot) {
            final unread = (snapshot.data ?? const <AppNotification>[])
                .where((item) => !item.isRead).length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(widget.locale.languageCode == 'en' ? 'Notifications' : 'Notifications')),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(color: Theme.of(context).colorScheme.onError, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          IconButton(tooltip: widget.locale.languageCode == 'en' ? 'Delete all' : 'Tout supprimer', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _deleteAll),
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
                trailing: IconButton(tooltip: widget.locale.languageCode == 'en' ? 'Delete' : 'Supprimer', icon: const Icon(Icons.delete_outline), onPressed: () => _deleteOne(item)),
                onTap: () => _openNotification(item),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'message': return Icons.chat_bubble_outline;
      case 'assignment': return Icons.assignment_outlined;
      case 'course': return Icons.menu_book_outlined;
      case 'timetable': return Icons.calendar_month_outlined;
      case 'submission': return Icons.task_alt_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }


  Future<void> _openNotification(AppNotification item) async {
    try {
      if (!item.isRead) {
        await _service.markRead(item.id, userId: widget.userId);
        if (mounted) setState(() => _future = _service.listForUser(widget.userId));
      }
      if (item.targetType == 'course' && item.targetId != null && mounted) {
        final client = Supabase.instance.client;
        final row = await client.from('profiles').select().eq('id', widget.userId).single();
        final profile = UserProfile.fromMap(Map<String, dynamic>.from(row));
        final course = await CourseService().getCourse(item.targetId!);
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CourseDetailPage(locale: widget.locale, profile: profile, course: course),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        widget.locale.languageCode == 'en' ? 'Could not open destination: $error' : 'Impossible d’ouvrir le contenu notifié : $error',
      )));
    }
  }

  Future<void> _deleteOne(AppNotification item) async {
    try {
      await _service.deleteOne(item.id, userId: widget.userId);
      if (mounted) setState(() => _future = _service.listForUser(widget.userId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.locale.languageCode == 'en' ? 'Delete all notifications?' : 'Supprimer toutes les notifications ?'),
        content: Text(widget.locale.languageCode == 'en' ? 'This only deletes your notifications.' : 'Cela supprime uniquement vos notifications.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(widget.locale.languageCode == 'en' ? 'Cancel' : 'Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(widget.locale.languageCode == 'en' ? 'Delete all' : 'Tout supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteAll(widget.userId);
      if (mounted) setState(() => _future = _service.listForUser(widget.userId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _markAll() async {
    try {
      await _service.markAllRead(widget.userId);
      if (mounted) {
        setState(() => _future = _service.listForUser(widget.userId));
      }
    } catch (_) {
      if (mounted) {
        final message = widget.locale.languageCode == 'en'
            ? 'Could not mark notifications as read. Please retry.'
            : 'Impossible de marquer les notifications comme lues. Réessayez.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }
}
