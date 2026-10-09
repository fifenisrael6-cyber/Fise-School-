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
    bool viewOnce = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Votre session a expiré. Reconnectez-vous.');
    final senderId = user.id;
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

    if (body.trim().isEmpty && path == null) return;

    try {
      await _client.from('message_group_messages').insert({
        'group_id': groupId,
        'sender_id': senderId,
        'body': body.trim(),
        'attachment_path': path,
        'attachment_name': attachmentName,
        'attachment_type': attachmentType,
        'view_once': path != null && viewOnce,
      });
    } catch (_) {
      if (path != null) {
        try {
          await _client.storage.from(bucket).remove([path]);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(bucket).createSignedUrl(path, 300);
  }

  Future<String?> openAttachmentUrl(GroupMessage message) async {
    final path = message.attachmentPath;
    if (path == null || path.isEmpty) return null;
    if (!message.viewOnce) return signedAttachmentUrl(path);

    final response = await _client.functions.invoke(
      'open-message-attachment',
      body: {'message_id': message.id, 'kind': 'group'},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError('Impossible d’ouvrir cette pièce jointe.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['url'] as String?;
  }

  Future<void> deleteMessage(
    String messageId, {
    required bool forEveryone,
  }) async {
    final result = await _client.rpc(
      'delete_group_message',
      params: {
        'p_message_id': messageId,
        'p_for_everyone': forEveryone,
      },
    );
    final path = result is String ? result : null;
    if (forEveryone && path != null && path.isNotEmpty) {
      try {
        await _client.storage.from(bucket).remove([path]);
      } catch (_) {
        // The message row has already been hidden and the object remains private.
      }
    }
  }
}
