import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/notification.dart';

class NotificationService {
  final SupabaseClient _client;

  NotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<AppNotification>> listForUser(String userId) async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => AppNotification.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<int> unreadCount(String userId) async {
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return rows.length;
  }

  Future<void> markRead(String id, {required String userId}) async {
    final updated = await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('user_id', userId)
        .select('id, is_read');

    // PostgREST can return zero updated rows under RLS. Verify the row is now
    // read instead of silently presenting a successful action to the user.
    if (updated.isEmpty) {
      final existing = await _client
          .from('notifications')
          .select('id, is_read')
          .eq('id', id)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing == null || existing['is_read'] != true) {
        throw StateError('La notification n’a pas pu être marquée comme lue.');
      }
    }
  }

  Future<void> markAllRead(String userId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false)
        .select('id');
  }
}
