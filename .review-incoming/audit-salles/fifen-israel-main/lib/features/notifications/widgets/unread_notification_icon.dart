import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';

/// Displays the signed-in user's unread notification count on the home page.
class UnreadNotificationIcon extends StatefulWidget {
  final String userId;
  final double size;

  const UnreadNotificationIcon({
    super.key,
    required this.userId,
    this.size = 24,
  });

  @override
  State<UnreadNotificationIcon> createState() =>
      _UnreadNotificationIconState();
}

class _UnreadNotificationIconState extends State<UnreadNotificationIcon> {
  final NotificationService _service = NotificationService();
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _subscribe();
    // Also refresh periodically in case realtime updates are temporarily absent.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCount(),
    );
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('unread-notification-count-${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _refreshCount(),
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(covariant UnreadNotificationIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _channel?.unsubscribe();
      _channel = null;
      _subscribe();
      _refreshCount();
    }
  }

  Future<void> _refreshCount() async {
    try {
      final count = await _service.unreadCount(widget.userId);
      if (mounted && count != _count) {
        setState(() => _count = count);
      }
    } catch (_) {
      // Preserve the last known number when the connection is unavailable.
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.notifications_outlined,
          size: widget.size,
          color: const Color(0xFF166534),
        ),
        if (_count > 0)
          Positioned(
            top: -7,
            right: -9,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                _count > 99 ? '99+' : '$_count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
