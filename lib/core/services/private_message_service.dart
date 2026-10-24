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
import '../../models/private_message.dart';

class PrivateMessageService {
  PrivateMessageService({SupabaseClient? client})
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

  String get _userId => _client.auth.currentUser!.id;

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<List<MessageContact>> listContacts() async {
    try {
      final result = await _client.rpc('list_private_message_contacts').timeout(const Duration(seconds: 8));
      final contacts = (result as List)
          .map((item) => MessageContact.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      for (final contact in contacts) {
        await _db.cacheMessageContact(_userId, contact.id, jsonEncode({
          'id': contact.id, 'first_name': contact.firstName, 'last_name': contact.lastName,
          'role': contact.role, 'class_name': contact.className, 'avatar_path': contact.avatarPath,
        }));
      }
      return contacts;
    } catch (_) {
      final rows = await _db.getCachedMessageContacts(_userId);
      return rows.map((row) => MessageContact.fromMap(
        Map<String, dynamic>.from(jsonDecode(row.read<String>('data_json')) as Map),
      )).toList();
    }
  }

  Future<List<PrivateMessage>> listConversation(String contactId) async {
    try {
      unawaited(syncPending());
      await _client.rpc('mark_private_messages_delivered', params: {'p_sender_id': contactId}).timeout(const Duration(seconds: 8));
      final result = await _client.rpc(
        'list_private_messages',
        params: {'target_user_id': contactId},
      ).timeout(const Duration(seconds: 8));
      final messages = (result as List)
          .map((item) => PrivateMessage.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      await _db.beginMessageCacheRefresh(_userId, 'private', contactId);
      for (final message in messages) {
        await _db.cacheMessage({
          'id': message.id, 'user_id': _userId, 'kind': 'private', 'thread_id': contactId,
          'sender_id': message.senderId, 'recipient_id': message.recipientId, 'body': message.body,
          'created_at': message.createdAt.toUtc().toIso8601String(),
          'delivered_at': message.deliveredAt?.toUtc().toIso8601String(),
          'read_at': message.readAt?.toUtc().toIso8601String(),
          'deleted_at': message.deletedAt?.toUtc().toIso8601String(),
          'attachment_path': message.attachmentPath, 'attachment_name': message.attachmentName,
          'attachment_type': message.attachmentType, 'reply_to_id': message.replyToId, 'sync_status': 'sent',
        });
      }
      return messages;
    } catch (_) {
      return _readPrivateCache(contactId);
    }
  }

  /// Returns the local snapshot without waiting for Supabase. Used to paint chats instantly.
  Future<List<PrivateMessage>> getCachedConversation(String contactId) =>
      _readPrivateCache(contactId);

  Future<List<PrivateMessage>> _readPrivateCache(String contactId, {List<dynamic>? fallbackRows}) async {
    final rows = fallbackRows ?? await _db.getCachedMessages(_userId, 'private', contactId);
    return rows.map((row) => PrivateMessage.fromMap({
      'id': row.read<String>('id'),
      'sender_id': row.read<String>('sender_id'),
      'recipient_id': row.readNullable<String>('recipient_id') ?? '',
      'body': row.read<String>('body'),
      'created_at': row.read<String>('created_at'),
      'delivered_at': row.data.containsKey('delivered_at') ? row.readNullable<String>('delivered_at') : null,
      'delivered_at': row.data.containsKey('delivered_at') ? row.readNullable<String>('delivered_at') : null,
      'read_at': row.readNullable<String>('read_at'),
      'deleted_at': row.data.containsKey('deleted_at') ? row.readNullable<String>('deleted_at') : null,
      'attachment_path': row.readNullable<String>('attachment_path'),
      'attachment_name': row.readNullable<String>('attachment_name'),
      'attachment_type': row.readNullable<String>('attachment_type'),
      'local_attachment_path': row.readNullable<String>('local_attachment_path'),
      'reply_to_id': row.readNullable<String>('reply_to_id'),
      'is_pending': row.read<String>('sync_status') == 'pending',
    })).toList();
  }

  Future<void> send({
    required String recipientId,
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
      'id': id, 'user_id': _userId, 'kind': 'private', 'thread_id': recipientId,
      'sender_id': _userId, 'recipient_id': recipientId, 'body': trimmed,
      'created_at': now, 'attachment_name': attachmentName, 'attachment_type': attachmentType,
      'local_attachment_path': localPath, 'attachment_local_path': localPath,
      'reply_to_id': replyToId,
    });
    // The local outbox/cache is the source of truth for immediate UI feedback.
    // Network delivery continues in the background; the message stays visible
    // with a pending check until Supabase confirms it.
    _lastRejectedMessageId = null;
    unawaited(syncPending());
  }

  Future<void>? _syncPendingFuture;
  String? _lastRejectedMessageId;

  Future<void> syncPending() {
    final active = _syncPendingFuture;
    if (active != null) return active;
    final task = _syncPendingImpl();
    _syncPendingFuture = task;
    return task.whenComplete(() {
      if (identical(_syncPendingFuture, task)) {
        _syncPendingFuture = null;
      }
    });
  }

  Future<void> _syncPendingImpl() async {
    if (_client.auth.currentUser == null) return;
    final pending = await _db.getQueuedMessages(_userId, 'private');
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
          remotePath = '$_userId/${id}_$safeName';
          try {
            await _client.storage.from('private-message-attachments').uploadBinary(
              remotePath, await file.readAsBytes(),
              fileOptions: FileOptions(upsert: false, contentType: row.readNullable<String>('attachment_type') ?? 'application/octet-stream'),
            );
          } catch (_) {
            // A previous attempt may have uploaded the same stable path before the network failed.
            await _client.storage.from('private-message-attachments').remove([remotePath]);
            await _client.storage.from('private-message-attachments').uploadBinary(
              remotePath, await file.readAsBytes(),
              fileOptions: FileOptions(upsert: false, contentType: row.readNullable<String>('attachment_type') ?? 'application/octet-stream'),
            );
          }
        }
        try {
          // A timed-out request may already have committed on the server.
          // Reusing the stable local ID must therefore be idempotent.
          await _client.from('private_messages').upsert({
            'id': id,
            'sender_id': _userId,
            'recipient_id': row.read<String>('thread_id'),
            'body': row.read<String>('body'),
            'attachment_path': remotePath,
            'attachment_name': name,
            'attachment_type': row.readNullable<String>('attachment_type'),
            'attachment_size': localPath == null ? null : await File(localPath).length(),
            'reply_to_id': row.readNullable<String>('reply_to_id'),
          }, onConflict: 'id', ignoreDuplicates: true)
              .timeout(const Duration(seconds: 12));
        } catch (insertError) {
          final denial = MessageQuotaEvents.kindFrom(insertError);
          if (denial != null) {
            await _db.discardRejectedMessage(id);
            _lastRejectedMessageId = id;
            MessageQuotaEvents.notify(denial);
            continue;
          }
          rethrow;
        }
        await _db.markMessageSent(id, attachmentPath: remotePath);
      } catch (_) {
        await _db.incrementMessageAttempts(id);
      }
    }
  }

  Future<void> deleteMessage(String messageId, {required bool forEveryone}) async {
    final path = await _client.rpc('delete_private_message', params: {
      'p_message_id': messageId,
      'p_for_everyone': forEveryone,
    });
    if (forEveryone && path is String && path.isNotEmpty) {
      try {
        await _client.storage.from('private-message-attachments').remove([path]);
      } catch (_) {
        // Message tombstone is already saved; storage cleanup is best-effort.
      }
    }
  }

  Future<String?> signedAttachmentUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from('private-message-attachments').createSignedUrl(path, 3600);
  }

  Future<void> markConversationRead(String contactId) async {
    try {
      await _client.rpc(
        'mark_private_messages_read',
        params: {'p_sender_id': contactId},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Keep cached messages readable while offline; read receipts sync on next open.
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
  }
}
