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
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Votre session a expiré. Reconnectez-vous.');
    final senderId = user.id;
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

    if (body.trim().isEmpty && path == null) return;

    try {
      await _client.from('private_messages').insert({
        'sender_id': senderId,
        'recipient_id': recipientId,
        'body': body.trim(),
        'attachment_path': path,
        'attachment_name': attachmentName,
        'attachment_type': attachmentType,
        'attachment_size': attachmentBytes?.length,
        'view_once': path != null && viewOnce,
      });
    } catch (_) {
      // If the database refuses the message, clean up the object already uploaded.
      if (path != null) {
        try {
          await _client.storage.from('private-message-attachments').remove([path]);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _client.storage
        .from('private-message-attachments')
        .createSignedUrl(path, 300);
  }

  Future<String?> openAttachmentUrl(PrivateMessage message) async {
    final path = message.attachmentPath;
    if (path == null || path.isEmpty) return null;

    if (!message.viewOnce) return signedAttachmentUrl(path);

    final response = await _client.functions.invoke(
      'open-message-attachment',
      body: {'message_id': message.id, 'kind': 'private'},
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
      'delete_private_message',
      params: {
        'p_message_id': messageId,
        'p_for_everyone': forEveryone,
      },
    );
    final path = result is String ? result : null;
    if (forEveryone && path != null && path.isNotEmpty) {
      try {
        await _client.storage.from('private-message-attachments').remove([path]);
      } catch (_) {
        // The row is already hidden; a stale private object remains unreadable.
      }
    }
  }

  Future<void> markConversationRead(String contactId) async {
    await _client.rpc(
      'mark_private_messages_read',
      params: {'p_sender_id': contactId},
    );
  }
}
