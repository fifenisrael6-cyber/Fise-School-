import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/notification_service.dart';
import '../../../models/notification.dart';

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
                onTap: () async {
                  try {
                    await _service.markRead(item.id, userId: widget.userId);
                    if (mounted) {
                      setState(() => _future = _service.listForUser(widget.userId));
                    }
                  } catch (_) {
                    if (mounted) {
                      final message = widget.locale.languageCode == 'en'
                          ? 'Could not mark this notification as read. Please retry.'
                          : 'Impossible de marquer cette notification comme lue. Réessayez.';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }
                  }
                },
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
