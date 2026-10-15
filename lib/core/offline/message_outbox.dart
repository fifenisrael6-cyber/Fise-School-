import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'json_cache.dart';

/// Un message écrit sur cet appareil et pas encore reçu par le serveur.
class OutboxMessage {
  /// Identifiant unique choisi par l'appareil. Il devient l'identifiant du
  /// message sur le serveur : si l'envoi est refait après une coupure, le
  /// serveur refuse le doublon au lieu de créer un second message.
  final String localId;

  /// `private` (message privé) ou `group` (message de groupe).
  final String scope;

  /// Destinataire (privé) ou groupe (group).
  final String targetId;
  final String senderId;
  final String body;

  /// Nom du fichier de la pièce jointe dans le dossier de la file d'attente.
  final String? attachmentFile;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;
  final bool viewOnce;
  final DateTime createdAt;

  /// Refusé définitivement par le serveur (droits, contenu invalide...).
  final bool failed;

  const OutboxMessage({
    required this.localId,
    required this.scope,
    required this.targetId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.attachmentFile,
    this.attachmentName,
    this.attachmentType,
    this.attachmentSize,
    this.viewOnce = false,
    this.failed = false,
  });

  factory OutboxMessage.fromMap(Map<String, dynamic> map) {
    return OutboxMessage(
      localId: map['local_id'] as String,
      scope: map['scope'] as String,
      targetId: map['target_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      attachmentFile: map['attachment_file'] as String?,
      attachmentName: map['attachment_name'] as String?,
      attachmentType: map['attachment_type'] as String?,
      attachmentSize: (map['attachment_size'] as num?)?.toInt(),
      viewOnce: map['view_once'] == true,
      failed: map['failed'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'local_id': localId,
        'scope': scope,
        'target_id': targetId,
        'sender_id': senderId,
        'body': body,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attachment_file': attachmentFile,
        'attachment_name': attachmentName,
        'attachment_type': attachmentType,
        'attachment_size': attachmentSize,
        'view_once': viewOnce,
        'failed': failed,
      };
}

/// File d'attente d'envoi des messages (façon WhatsApp).
///
/// - Un message est d'abord enregistré sur le téléphone : il apparaît tout de
///   suite dans la conversation avec une horloge, même sans réseau.
/// - Dès que le réseau est là, les messages partent dans l'ordre où ils ont
///   été écrits (une pièce jointe d'abord, puis le message).
/// - Une coupure en plein envoi ne crée jamais de doublon (identifiant fixe).
/// - Un message refusé par le serveur est marqué « échec » : on peut le
///   renvoyer ou le supprimer, il ne bloque pas les suivants.
class MessageOutbox {
  MessageOutbox._();

  static final MessageOutbox instance = MessageOutbox._();

  static const String _key = 'message_outbox';
  static const String _privateBucket = 'private-message-attachments';
  static const String _groupBucket = 'group-message-attachments';
  static const Duration _uploadTimeout = Duration(minutes: 3);
  static const Duration _retryDelay = Duration(seconds: 20);

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void> _tail = Future<void>.value();
  bool _flushing = false;
  bool _dirty = false;
  Timer? _retryTimer;

  /// Émet à chaque changement de la file (ajout, envoi réussi, échec...).
  Stream<void> get changes => _changes.stream;

  // ------------------------------------------------------------------
  // Stockage
  // ------------------------------------------------------------------

  /// Exécute les accès au fichier JSON l'un après l'autre pour qu'un ajout
  /// et un envoi simultanés ne s'écrasent jamais.
  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<List<OutboxMessage>> _readAll() async {
    final raw = await JsonCache.instance.read(_key);
    if (raw is! List) return <OutboxMessage>[];
    final items = <OutboxMessage>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        items.add(OutboxMessage.fromMap(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // Entrée illisible : ignorée plutôt que de bloquer toute la file.
      }
    }
    return items;
  }

  Future<void> _writeAll(List<OutboxMessage> items) =>
      JsonCache.instance.write(_key, items.map((e) => e.toMap()).toList());

  Future<Directory> _attachmentDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'fise_outbox'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _deleteAttachment(String? fileName) async {
    if (fileName == null) return;
    try {
      final dir = await _attachmentDir();
      final file = File(p.join(dir.path, fileName));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Lecture
  // ------------------------------------------------------------------

  /// Messages en attente de l'utilisateur connecté (les plus anciens d'abord).
  Future<List<OutboxMessage>> pending({String? scope, String? targetId}) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return <OutboxMessage>[];
    final items = await _locked(_readAll);
    final mine = items.where((m) {
      if (m.senderId != me) return false;
      if (scope != null && m.scope != scope) return false;
      if (targetId != null && m.targetId != targetId) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return mine;
  }

  /// Nombre de messages qui attendent d'être envoyés (échecs exclus).
  Future<int> count() async {
    try {
      final items = await _locked(_readAll);
      return items.where((m) => !m.failed).length;
    } catch (_) {
      return 0;
    }
  }

  // ------------------------------------------------------------------
  // Ajout
  // ------------------------------------------------------------------

  /// Enregistre un message sur le téléphone. N'envoie rien : voir [flush].
  /// Retourne null si le message est vide.
  Future<OutboxMessage?> enqueue({
    required String scope,
    required String targetId,
    required String body,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentType,
    bool viewOnce = false,
  }) async {
    final senderId = Supabase.instance.client.auth.currentUser?.id;
    if (senderId == null) {
      throw StateError('Session expirée : reconnecte-toi pour envoyer.');
    }
    final hasAttachment = attachmentBytes != null && attachmentName != null;
    if (viewOnce && !hasAttachment) {
      throw ArgumentError('View-once messages must include an attachment.');
    }
    final text = body.trim();
    if (text.isEmpty && !hasAttachment) return null;

    final id = _uuidV4();
    String? fileName;
    if (hasAttachment) {
      fileName = '$id.bin';
      final dir = await _attachmentDir();
      await File(p.join(dir.path, fileName))
          .writeAsBytes(attachmentBytes, flush: true);
    }

    final message = OutboxMessage(
      localId: id,
      scope: scope,
      targetId: targetId,
      senderId: senderId,
      body: text,
      createdAt: DateTime.now(),
      attachmentFile: fileName,
      attachmentName: hasAttachment ? attachmentName : null,
      attachmentType: hasAttachment ? attachmentType : null,
      attachmentSize: hasAttachment ? attachmentBytes.length : null,
      viewOnce: viewOnce,
    );

    await _locked(() async {
      final items = await _readAll();
      items.add(message);
      await _writeAll(items);
    });
    _dirty = true;
    _changes.add(null);
    return message;
  }

  // ------------------------------------------------------------------
  // Envoi
  // ------------------------------------------------------------------

  /// Envoie ce qui peut l'être. Ne lève jamais d'erreur : ce qui ne part pas
  /// reste en file et sera retenté au retour du réseau.
  /// Retourne le nombre de messages envoyés.
  Future<int> flush([SupabaseClient? client]) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    var networkProblem = false;
    try {
      final c = client ?? Supabase.instance.client;
      final me = c.auth.currentUser?.id;
      if (me == null) return 0;

      _dirty = false;
      final queue = (await _locked(_readAll))
          .where((m) => m.senderId == me && !m.failed)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final message in queue) {
        try {
          await _deliver(c, message);
          await _remove(message.localId);
          sent++;
          _changes.add(null);
        } catch (error) {
          if (_isPermanent(error)) {
            await _markFailed(message.localId);
            _changes.add(null);
            continue;
          }
          // Réseau coupé ou serveur injoignable : on s'arrête pour garder
          // l'ordre des messages et on réessaiera plus tard.
          networkProblem = true;
          break;
        }
      }
    } catch (_) {
      networkProblem = true;
    } finally {
      _flushing = false;
    }

    if (networkProblem) {
      _scheduleRetry();
    } else if (_dirty) {
      // Un message a été ajouté pendant l'envoi.
      unawaited(flush(client));
    }
    return sent;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () async {
      try {
        if (await ConnectivityService().isOnline()) {
          await flush();
        } else {
          _scheduleRetry();
        }
      } catch (_) {}
    });
  }

  bool _isPermanent(Object error) {
    if (error is _OutboxPermanentError) return true;
    if (error is PostgrestException) {
      final text = '${error.code} ${error.message}'.toLowerCase();
      // Jeton expiré : se corrige tout seul à la reconnexion, pas un refus.
      if (text.contains('jwt') || text.contains('pgrst301')) return false;
      final code = error.code ?? '';
      // Erreurs serveur 5xx (ex. 503) : temporaire.
      if (code.startsWith('5')) return false;
      return true;
    }
    if (error is StorageException) {
      final status = error.statusCode ?? '';
      if (status == '401' || status.startsWith('5')) return false;
      return status.startsWith('4');
    }
    return false;
  }

  Future<void> _deliver(SupabaseClient c, OutboxMessage m) async {
    String? path;
    if (m.attachmentFile != null && m.attachmentName != null) {
      final dir = await _attachmentDir();
      final file = File(p.join(dir.path, m.attachmentFile!));
      if (!await file.exists()) {
        throw _OutboxPermanentError('Pièce jointe introuvable sur l’appareil.');
      }
      final bytes = await file.readAsBytes();
      final safeName =
          m.attachmentName!.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      // Chemin déterministe : une reprise après coupure retrouve le même
      // fichier (« déjà existant » = déjà envoyé) au lieu d'en créer un autre.
      final folder = m.scope == 'private' ? m.senderId : m.targetId;
      path = '$folder/${m.localId}_$safeName';
      final bucket = m.scope == 'private' ? _privateBucket : _groupBucket;
      try {
        await c.storage.from(bucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                upsert: false,
                contentType: m.attachmentType ?? 'application/octet-stream',
              ),
            ).timeout(_uploadTimeout);
      } on StorageException catch (error) {
        if (error.statusCode != '409') rethrow;
      }
    }

    final row = <String, dynamic>{
      'id': m.localId,
      'sender_id': m.senderId,
      'body': m.body,
      'attachment_path': path,
      'attachment_name': m.attachmentName,
      'attachment_type': m.attachmentType,
      'view_once': m.viewOnce,
    };
    final String table;
    if (m.scope == 'private') {
      table = 'private_messages';
      row['recipient_id'] = m.targetId;
      row['attachment_size'] = m.attachmentSize;
    } else {
      table = 'message_group_messages';
      row['group_id'] = m.targetId;
    }

    try {
      await c.from(table).insert(row).timeout(JsonCache.networkTimeout);
    } on PostgrestException catch (error) {
      // 23505 : ce message est déjà chez le serveur (envoi précédent réussi
      // mais réponse perdue) → c'est un succès.
      if (error.code != '23505') rethrow;
    }
  }

  Future<void> _remove(String localId) async {
    String? file;
    await _locked(() async {
      final items = await _readAll();
      for (final m in items) {
        if (m.localId == localId) file = m.attachmentFile;
      }
      items.removeWhere((m) => m.localId == localId);
      await _writeAll(items);
    });
    await _deleteAttachment(file);
  }

  Future<void> _markFailed(String localId, {bool failed = true}) {
    return _locked(() async {
      final items = await _readAll();
      final index = items.indexWhere((m) => m.localId == localId);
      if (index < 0) return;
      final m = items[index];
      items[index] = OutboxMessage(
        localId: m.localId,
        scope: m.scope,
        targetId: m.targetId,
        senderId: m.senderId,
        body: m.body,
        createdAt: m.createdAt,
        attachmentFile: m.attachmentFile,
        attachmentName: m.attachmentName,
        attachmentType: m.attachmentType,
        attachmentSize: m.attachmentSize,
        viewOnce: m.viewOnce,
        failed: failed,
      );
      await _writeAll(items);
    });
  }

  /// Remet un message en échec dans la file et relance l'envoi.
  Future<void> retry(String localId) async {
    await _markFailed(localId, failed: false);
    _changes.add(null);
    await flush();
  }

  /// Supprime un message qui n'est pas encore parti.
  Future<void> discard(String localId) async {
    await _remove(localId);
    _changes.add(null);
  }

  /// Vide la file (déconnexion : le téléphone peut changer de compte).
  Future<void> clear() async {
    _retryTimer?.cancel();
    try {
      await _locked(() => JsonCache.instance.remove(_key));
      final dir = await _attachmentDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _changes.add(null);
  }

  String _uuidV4() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}

class _OutboxPermanentError implements Exception {
  final String message;
  _OutboxPermanentError(this.message);

  @override
  String toString() => message;
}
