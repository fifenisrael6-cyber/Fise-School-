import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/private_message.dart';
import '../offline/json_cache.dart';
import '../offline/message_outbox.dart';

class PrivateMessageService {
  PrivateMessageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _userId => _client.auth.currentUser?.id ?? 'anonymous';

  /// Liste des contacts. Sans réseau : dernière liste connue.
  Future<List<MessageContact>> listContacts() {
    return JsonCache.instance.cachedRead<List<MessageContact>>(
      key: 'pm_contacts_$_userId',
      fetch: () async => await _client.rpc('list_private_message_contacts') as Object?,
      decode: (raw) => (raw as List)
          .map((item) => MessageContact.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Future<bool> unlockTeacher(String code) async {
    final result = await _client.rpc(
      'unlock_teacher_private_messages',
      params: {'p_code': code.trim()},
    );
    return result == true;
  }

  /// Conversation avec un contact : messages du serveur (ou dernière copie
  /// locale sans réseau) suivis des messages en attente d'envoi.
  Future<List<PrivateMessage>> listConversation(String contactId) async {
    final queued = await MessageOutbox.instance
        .pending(scope: 'private', targetId: contactId);
    List<PrivateMessage> server;
    try {
      server = await JsonCache.instance.cachedRead<List<PrivateMessage>>(
        key: 'pm_conv_${_userId}_$contactId',
        fetch: () async => await _client.rpc(
          'list_private_messages',
          params: {'target_user_id': contactId},
        ) as Object?,
        decode: (raw) => (raw as List)
            .map((item) => PrivateMessage.fromMap(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
    } catch (_) {
      // Rien sur le serveur ni en cache : on n'affiche que les messages en
      // attente, et on relance l'erreur s'il n'y en a aucun.
      if (queued.isEmpty) rethrow;
      server = <PrivateMessage>[];
    }
    final knownIds = server.map((m) => m.id).toSet();
    return <PrivateMessage>[
      ...server,
      for (final m in queued)
        if (!knownIds.contains(m.localId))
          PrivateMessage(
            id: m.localId,
            senderId: m.senderId,
            recipientId: m.targetId,
            body: m.body,
            createdAt: m.createdAt,
            attachmentName: m.attachmentName,
            attachmentType: m.attachmentType,
            viewOnce: m.viewOnce,
            pending: !m.failed,
            failed: m.failed,
          ),
    ];
  }

  /// Enregistre le message dans la file d'envoi puis tente de l'envoyer.
  /// Sans réseau, il reste en attente (horloge) et part au retour du réseau.
  Future<void> send({
    required String recipientId,
    required String body,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentType,
    bool viewOnce = false,
  }) async {
    final queued = await MessageOutbox.instance.enqueue(
      scope: 'private',
      targetId: recipientId,
      body: body,
      attachmentBytes: attachmentBytes,
      attachmentName: attachmentName,
      attachmentType: attachmentType,
      viewOnce: viewOnce,
    );
    if (queued == null) return;
    await MessageOutbox.instance.flush(_client);
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
    // Use the authorized RPC so delivery receipts share the database's
    // conversation-access checks rather than relying on direct table updates.
    await _client.rpc(
      'mark_private_messages_delivered',
      params: {'p_sender_id': senderId},
    );
  }

  Future<void> markConversationRead(String contactId) async {
    // The RPC atomically marks both delivery and read receipts and applies
    // the same authorization check as the private-message conversation.
    await _client.rpc(
      'mark_private_messages_read',
      params: {'p_sender_id': contactId},
    );
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
