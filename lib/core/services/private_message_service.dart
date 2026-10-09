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
      'view_once': path == null ? false : viewOnce,
    });
  }

  Future<String?> signedAttachmentUrl(String? path, {bool shortLived = false}) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _client.storage
        .from('private-message-attachments')
        .createSignedUrl(path, shortLived ? 60 : 3600);
  }

  Future<bool> markViewedOnce(String messageId) async {
    final result = await _client.rpc(
      'mark_private_message_viewed_once',
      params: {'p_message_id': messageId},
    );
    return result == true;
  }

  Future<void> markConversationDelivered(String senderId) async {
    await _client.rpc(
      'mark_private_messages_delivered',
      params: {'p_sender_id': senderId},
    );
  }

  Future<void> markConversationRead(String senderId) async {
    await _client.rpc(
      'mark_private_messages_read',
      params: {'p_sender_id': senderId},
    );
  }

  Future<void> deleteMessage(PrivateMessage message) async {
    await _client.rpc(
      'delete_private_message',
      params: {'p_message_id': message.id},
    );
    final path = message.attachmentPath;
    if (path != null && path.isNotEmpty) {
      try {
        await _client.storage.from('private-message-attachments').remove([path]);
      } catch (_) {
        // Le message est supprimé. Un éventuel nettoyage du fichier peut être
        // repris séparément si la politique Storage interdit sa suppression.
      }
    }
  }
}
