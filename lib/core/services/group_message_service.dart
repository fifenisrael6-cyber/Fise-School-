import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/message_group.dart';

class GroupMessageService {
  GroupMessageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String bucket = 'group-message-attachments';

  Future<List<MessageGroup>> listGroups() async {
    final result = await _client.rpc('list_my_message_groups');
    return (result as List)
        .map((row) => MessageGroup.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  /// Création réservée aux enseignants (vérifiée côté serveur).
  Future<String> createGroup({required String name, String? classId}) async {
    final id = await _client.rpc(
      'create_message_group',
      params: {'p_name': name, 'p_class_id': classId},
    );
    return id as String;
  }

  Future<String> joinWithCode(String code) async {
    final id = await _client.rpc('join_message_group', params: {'p_code': code});
    return id as String;
  }

  Future<String> regenerateCode(String groupId) async {
    final code = await _client.rpc(
      'regenerate_message_group_code',
      params: {'p_group_id': groupId},
    );
    return code as String;
  }

  Future<void> markMessagesDelivered(String groupId) async {
    await _client.rpc(
      'mark_group_messages_delivered',
      params: {'p_group_id': groupId},
    );
  }

  Future<void> markMessagesRead(String groupId) async {
    await _client.rpc(
      'mark_group_messages_read',
      params: {'p_group_id': groupId},
    );
  }

  Future<List<GroupMessage>> listMessages(String groupId) async {
    final result = await _client.rpc(
      'list_message_group_messages',
      params: {'p_group_id': groupId},
    );
    return (result as List)
        .map((row) => GroupMessage.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final result = await _client.rpc(
      'list_message_group_members',
      params: {'p_group_id': groupId},
    );
    return (result as List)
        .map((row) => GroupMember.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _client
        .from('message_group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  Future<void> send({
    required String groupId,
    required String body,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentType,
  }) async {
    final senderId = _client.auth.currentUser!.id;
    String? path;

    if (attachmentBytes != null && attachmentName != null) {
      final safeName = attachmentName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      path = '$groupId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await _client.storage.from(bucket).uploadBinary(
        path,
        attachmentBytes,
        fileOptions: FileOptions(
          upsert: false,
          contentType: attachmentType ?? 'application/octet-stream',
        ),
      );
    }

    if (body.trim().isEmpty && path == null) {
      return;
    }

    await _client.from('message_group_messages').insert({
      'group_id': groupId,
      'sender_id': senderId,
      'body': body.trim(),
      'attachment_path': path,
      'attachment_name': attachmentName,
      'attachment_type': attachmentType,
    });
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _client.storage.from(bucket).createSignedUrl(path, 3600);
  }

  Future<void> deleteMessage({required String groupId, required GroupMessage message}) async {
    final userId = _client.auth.currentUser!.id;
    if (message.senderId != userId) {
      throw StateError('You can only delete messages you sent.');
    }

    // Remove the attachment while the message row still exists; the storage
    // policy verifies ownership through that row.
    if (message.attachmentPath != null && message.attachmentPath!.isNotEmpty) {
      try {
        await _client.storage.from(bucket).remove([message.attachmentPath!]);
      } catch (_) {
        // Still delete the message if an attachment was already removed.
      }
    }

    await _client
        .from('message_group_messages')
        .delete()
        .eq('id', message.id)
        .eq('group_id', groupId)
        .eq('sender_id', userId);
  }
}
