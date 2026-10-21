import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'message_quota_events.dart';

import '../offline/app_database.dart';
import '../../models/message_group.dart';

class GroupMessageService {
  GroupMessageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncPending());
      }
    });
  }

  final SupabaseClient _client;
  final AppDatabase _db = AppDatabase();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static const String bucket = 'group-message-attachments';
  String get _userId => _client.auth.currentUser!.id;

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<List<MessageGroup>> listGroups() async {
    final byId = <String, MessageGroup>{};

    // Primary list includes groups the current account belongs to.
    try {
      final result = await _client
          .rpc('list_my_message_groups')
          .timeout(const Duration(seconds: 8));
      if (result is List) {
        for (final row in result) {
          final group = MessageGroup.fromMap(
            Map<String, dynamic>.from(row as Map),
          );
          byId[group.id] = group;
        }
      }
    } catch (_) {
      // Continue to the owner-only recovery RPC below.
    }

    // Recovery list includes every group owned by this teacher, even if the
    // normal membership-based list is stale or returns no rows.
    try {
      final result = await _client
          .rpc('list_teacher_owned_message_groups')
          .timeout(const Duration(seconds: 8));
      if (result is List) {
        for (final row in result) {
          final group = MessageGroup.fromMap(
            Map<String, dynamic>.from(row as Map),
          );
          // Keep the primary RPC's richer preview/unread data when available.
          byId.putIfAbsent(group.id, () => group);
        }
      }
    } catch (_) {
      // Students and older deployments may not expose this teacher-only RPC.
    }

    final fetchedGroups = byId.values.toList(growable: false);
    if (fetchedGroups.isNotEmpty) {
      // Every group owned by a teacher displays the same canonical FISE code
      // used by payments. Keep each group's legacy invite code in the database
      // so older invitations remain valid, but don't present them as separate
      // teacher codes in the UI.
      String? sharedTeacherCode;
      if (fetchedGroups.any((group) => group.ownerId == _userId)) {
        try {
          final codeRow = await _client
              .from('teacher_group_access_codes')
              .select('code')
              .eq('teacher_id', _userId)
              .eq('is_active', true)
              .maybeSingle();
          sharedTeacherCode = codeRow?['code']?.toString();
        } catch (_) {
          // Keep the server-provided invitation as a compatibility fallback.
        }
      }
      final groups = fetchedGroups.map((group) {
        if (group.ownerId != _userId || sharedTeacherCode == null) {
          return group;
        }
        return MessageGroup(
          id: group.id,
          name: group.name,
          classId: group.classId,
          className: group.className,
          ownerId: group.ownerId,
          inviteCode: sharedTeacherCode,
          memberCount: group.memberCount,
          lastBody: group.lastBody,
          lastAt: group.lastAt,
        );
      }).toList(growable: false);

      for (final group in groups) {
        try {
          await _db.cacheMessageGroup(
            _userId,
            group.id,
            jsonEncode({
              'id': group.id,
              'name': group.name,
              'class_id': group.classId,
              'class_name': group.className,
              'owner_id': group.ownerId,
              'invite_code': group.inviteCode,
              'member_count': group.memberCount,
              'last_body': group.lastBody,
              'last_at': group.lastAt?.toUtc().toIso8601String(),
            }),
          );
        } catch (_) {
          // A local cache write must never hide groups fetched successfully.
        }
      }
      return groups;
    }

    // Only use offline cache when neither remote RPC produced any groups.
    try {
      final rows = await _db.getCachedMessageGroups(_userId);
      return rows
          .map((row) => MessageGroup.fromMap(
                Map<String, dynamic>.from(
                  jsonDecode(row.read<String>('data_json')) as Map,
                ),
              ))
          .toList(growable: false);
    } catch (_) {
      return const <MessageGroup>[];
    }
  }

  Future<String> createGroup({required String name, String? classId}) async {
    final id = await _client.rpc('create_message_group', params: {
      'p_name': name, 'p_class_ids': classId == null ? <String>[] : <String>[classId],
    });
    return id as String;
  }

  Future<String> joinWithCode(String code) async {
    final id = await _client.rpc('join_message_group', params: {'p_code': code});
    // A valid shared FISE code can grant evaluation access even when the
    // teacher has not created a group for this classroom yet.
    return id?.toString() ?? '';
  }

  Future<List<GroupMessage>> listMessages(String groupId) async {
    try {
      await syncPending();
      // Opening a group conversation marks incoming messages as delivered and read.
      // Keep these calls on the server so the WhatsApp-style receipts are reliable
      // across devices and are not inferred from the local/offline cache.
      await _client.rpc('mark_group_messages_delivered', params: {
        'p_group_id': groupId,
      }).timeout(const Duration(seconds: 8));
      await _client.rpc('mark_group_messages_read', params: {
        'p_group_id': groupId,
      }).timeout(const Duration(seconds: 8));
      final result = await _client.rpc('list_message_group_messages', params: {'p_group_id': groupId})
          .timeout(const Duration(seconds: 8));
      final remote = (result as List)
          .map((row) => GroupMessage.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
      await _db.beginMessageCacheRefresh(_userId, 'group', groupId);
      for (final message in remote) {
        await _db.cacheMessage({
          'id': message.id, 'user_id': _userId, 'kind': 'group', 'thread_id': groupId,
          'sender_id': message.senderId, 'sender_name': message.senderName, 'sender_role': message.senderRole, 'recipient_id': null, 'body': message.body,
          'created_at': message.createdAt.toUtc().toIso8601String(),
          'attachment_path': message.attachmentPath, 'attachment_name': message.attachmentName,
          'attachment_type': message.attachmentType, 'reply_to_id': message.replyToId, 'sync_status': 'sent',
        });
      }
      return _readCache(groupId);
    } catch (_) {
      return _readCache(groupId);
    }
  }

  Future<List<GroupMessage>> _readCache(String groupId, {List<dynamic>? fallbackRows}) async {
    final rows = fallbackRows ?? await _db.getCachedMessages(_userId, 'group', groupId);
    return rows.map((row) => GroupMessage.fromMap({
      'id': row.read<String>('id'),
      'sender_id': row.read<String>('sender_id'),
      'sender_name': row.read<String>('sender_name'),
      'sender_role': row.read<String>('sender_role'),
      'body': row.read<String>('body'),
      'created_at': row.read<String>('created_at'),
      'attachment_path': row.readNullable<String>('attachment_path'),
      'attachment_name': row.readNullable<String>('attachment_name'),
      'attachment_type': row.readNullable<String>('attachment_type'),
      'local_attachment_path': row.readNullable<String>('local_attachment_path'),
      'reply_to_id': row.readNullable<String>('reply_to_id'),
      'is_pending': row.read<String>('sync_status') == 'pending',
    })).toList();
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final result = await _client.rpc('list_message_group_members', params: {'p_group_id': groupId});
    return (result as List).map((row) => GroupMember.fromMap(Map<String, dynamic>.from(row as Map))).toList();
  }

  Future<bool> getAnnouncementsOnly(String groupId) async {
    final result = await _client.rpc('get_message_group_settings', params: {'p_group_id': groupId});
    if (result is Map) return result['announcements_only'] == true;
    return false;
  }

  Future<void> setAnnouncementsOnly(String groupId, bool enabled) async {
    await _client.rpc('set_message_group_announcements_only', params: {
      'p_group_id': groupId, 'p_enabled': enabled,
    });
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _client.rpc('remove_message_group_member', params: {
      'p_group_id': groupId, 'p_user_id': userId,
    });
  }

  Future<void> leaveGroup(String groupId) async {
    await _client.rpc('leave_message_group', params: {'p_group_id': groupId});
  }

  Future<void> clearGroupForMe(String groupId) async {
    await _client.rpc('clear_message_group_for_me', params: {'p_group_id': groupId});
  }

  Future<void> deleteGroup(String groupId) async {
    await _client.rpc('delete_message_group', params: {'p_group_id': groupId});
  }

  Future<void> send({
    required String groupId,
    required String body,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentType,
    String? replyToId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty && attachmentBytes == null) return;
    final id = _newId();
    String? localPath;
    if (attachmentBytes != null && attachmentName != null) {
      final dir = await getApplicationSupportDirectory();
      final safeName = attachmentName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      localPath = '${dir.path}/message_${id}_$safeName';
      await File(localPath).writeAsBytes(attachmentBytes, flush: true);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.queueMessage({
      'id': id, 'user_id': _userId, 'kind': 'group', 'thread_id': groupId,
      'sender_id': _userId, 'recipient_id': null, 'body': trimmed, 'created_at': now,
      'attachment_name': attachmentName, 'attachment_type': attachmentType,
      'local_attachment_path': localPath, 'attachment_local_path': localPath,
      'reply_to_id': replyToId,
    });
    unawaited(syncPending());
  }

  Future<void> syncPending() async {
    if (_client.auth.currentUser == null) return;
    final pending = await _db.getQueuedMessages(_userId, 'group');
    for (final row in pending) {
      final id = row.read<String>('id');
      try {
        String? remotePath;
        final localPath = row.readNullable<String>('attachment_local_path');
        final name = row.readNullable<String>('attachment_name');
        if (localPath != null && name != null) {
          final file = File(localPath);
          if (!await file.exists()) throw StateError('Pending attachment is missing');
          final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
          remotePath = '${row.read<String>('thread_id')}/${id}_$safeName';
          try {
            await _client.storage.from(bucket).uploadBinary(
              remotePath, await file.readAsBytes(),
              fileOptions: FileOptions(upsert: false, contentType: row.readNullable<String>('attachment_type') ?? 'application/octet-stream'),
            );
          } catch (_) {
            // A previous attempt may have uploaded the same stable path before the network failed.
            await _client.storage.from(bucket).remove([remotePath]);
            await _client.storage.from(bucket).uploadBinary(
              remotePath, await file.readAsBytes(),
              fileOptions: FileOptions(upsert: false, contentType: row.readNullable<String>('attachment_type') ?? 'application/octet-stream'),
            );
          }
        }
        try {
          await _client.from('message_group_messages').insert({
            'id': id, 'group_id': row.read<String>('thread_id'), 'sender_id': _userId,
            'body': row.read<String>('body'), 'attachment_path': remotePath,
            'attachment_name': name, 'attachment_type': row.readNullable<String>('attachment_type'),
            'reply_to_id': row.readNullable<String>('reply_to_id'),
          }).timeout(const Duration(seconds: 12));
        } catch (insertError) {
          final denial = MessageQuotaEvents.kindFrom(insertError);
          if (denial != null) {
            await _db.discardRejectedMessage(id);
            MessageQuotaEvents.notify(denial);
            continue;
          }
          final existing = await _client.from('message_group_messages').select('id')
              .eq('id', id).maybeSingle().timeout(const Duration(seconds: 8));
          if (existing == null) rethrow;
        }
        await _db.markMessageSent(id, attachmentPath: remotePath);
      } catch (_) {
        await _db.incrementMessageAttempts(id);
      }
    }
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(bucket).createSignedUrl(path, 3600);
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
  }
}
