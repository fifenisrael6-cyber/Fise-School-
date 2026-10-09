import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/private_message.dart';

class PrivateMessageService {
  PrivateMessageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<MessageContact>> listContacts() async {
    final result = await _client.rpc('list_private_message_contacts');
    return (result as List)
        .map((item) => MessageContact.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<bool> unlockTeacher(String code) async {
    final result = await _client.rpc(
      'unlock_teacher_private_messages',
      params: {'p_code': code.trim()},
    );
    return result == true;
  }

  Future<List<PrivateMessage>> listConversation(String contactId) async {
    final result = await _client.rpc(
      'list_private_messages',
      params: {'target_user_id': contactId},
    );
    return (result as List)
        .map((item) => PrivateMessage.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> send({
    required String recipientId,
    required String body,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentType,
    bool viewOnce = false,
  }) async {
    if (viewOnce && (attachmentBytes == null || attachmentName == null)) {
      throw ArgumentError('View-once messages must include an attachment.');
    }
    final senderId = _client.auth.currentUser!.id;
    String? path;

    if (attachmentBytes != null && attachmentName != null) {
      final safeName = attachmentName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      path = '$senderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await _client.storage.from('private-message-attachments').uploadBinary(
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

    await _client.from('private_messages').insert({
      'sender_id': senderId,
      'recipient_id': recipientId,
      'body': body.trim(),
      'attachment_path': path,
      'attachment_name': attachmentName,
      'attachment_type': attachmentType,
      'attachment_size': attachmentBytes?.length,
      'view_once': viewOnce,
    });
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _client.storage
        .from('private-message-attachments')
        .createSignedUrl(path, 3600);
  }

  Future<void> markConversationDelivered(String senderId) async {
    final userId = _client.auth.currentUser!.id;
    await _client
        .from('private_messages')
        .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
        .eq('sender_id', senderId)
        .eq('recipient_id', userId)
        .isFilter('delivered_at', null);
  }

  Future<void> markConversationRead(String contactId) async {
    final userId = _client.auth.currentUser!.id;
    await _client
        .from('private_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('sender_id', contactId)
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
  }

  /// Atomically consumes a view-once attachment and asks the Edge Function
  /// to return a short-lived signed URL. The URL is never persisted in a row.
  Future<String> openViewOnceAttachment(String messageId) async {
    final response = await _client.functions.invoke(
      'open-view-once',
      body: {'message_id': messageId, 'scope': 'private'},
    );
    final data = response.data;
    if (data is Map && data['url'] is String && (data['url'] as String).isNotEmpty) {
      return data['url'] as String;
    }
    throw StateError('The one-time attachment is unavailable.');
  }

  Future<void> deleteMessage(
    PrivateMessage message, {
    required bool forEveryone,
  }) async {
    final userId = _client.auth.currentUser!.id;
    if (forEveryone && message.senderId != userId) {
      throw StateError('Only the sender can delete a message for everyone.');
    }

    final result = await _client.rpc(
      'delete_private_message',
      params: {
        'p_message_id': message.id,
        'p_for_everyone': forEveryone,
      },
    );

    // The database function clears the attachment path before returning it.
    // Storage cleanup is best-effort and does not affect the deletion state.
    if (result is String && result.isNotEmpty) {
      try {
        await _client.storage
            .from('private-message-attachments')
            .remove([result]);
      } catch (_) {}
    }
  }
}
