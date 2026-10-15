import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../widgets/voice_message_bubble.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/offline/message_outbox.dart';
import '../../../core/offline/message_attachment_offline.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/services/private_message_service.dart';
import '../../../models/private_message.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/photo_service.dart';

class PrivateMessagesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final PickedAttachment? initialAttachment;

  const PrivateMessagesPage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialAttachment,
  });

  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  final _service = PrivateMessageService();
  final _composer = TextEditingController();
  late Future<List<MessageContact>> _contactsFuture;
  MessageContact? _selected;
  List<PrivateMessage> _messages = const [];
  bool _loadingMessages = false;
  bool _sending = false;
  PickedAttachment? _attachment;
  bool _viewOnce = false;
  final PhotoService _photoService = PhotoService();
  final AudioRecorder _recorder = AudioRecorder();
  bool _recordingVoice = false;
  Timer? _voiceLimitTimer;
  final Stopwatch _voiceStopwatch = Stopwatch();
  Timer? _voiceTicker;
  Duration _voiceElapsed = Duration.zero;
  RealtimeChannel? _channel;
  StreamSubscription<void>? _outboxSubscription;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _contactsFuture = _service.listContacts();
    _attachment = widget.initialAttachment;
    // Messages en attente : on rafraîchit la conversation quand la file change
    // (envoi réussi au retour du réseau, échec...), et on relance l'envoi.
    _outboxSubscription = MessageOutbox.instance.changes.listen((_) {
      final selected = _selected;
      if (selected != null && mounted) unawaited(_refreshMessages(selected));
    });
    unawaited(MessageOutbox.instance.flush());
    _channel = Supabase.instance.client.channel('private-messages-${widget.profile.id}')
      ..onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'private_messages', callback: (payload) {
        final row = payload.newRecord;
        if (row['sender_id'] == widget.profile.id || row['recipient_id'] == widget.profile.id) {
          if (row['recipient_id'] == widget.profile.id && row['sender_id'] != widget.profile.id) {
            unawaited(_service.markConversationDelivered(row['sender_id'] as String).catchError((_) {}));
          }
          final selected = _selected;
          if (selected != null && (row['sender_id'] == selected.id || row['recipient_id'] == selected.id)) {
            _select(selected);
          }
          if (mounted) {
            setState(() => _contactsFuture = _service.listContacts());
          }
        }
      })
      ..onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'private_messages', callback: (payload) {
        final row = payload.newRecord;
        final selected = _selected;
        if (selected != null &&
            ((row['sender_id'] == widget.profile.id && row['recipient_id'] == selected.id) ||
             (row['sender_id'] == selected.id && row['recipient_id'] == widget.profile.id))) {
          _select(selected);
        }
      })
      .subscribe();
  }

  @override
  void dispose() {
    _composer.dispose();
    _channel?.unsubscribe();
    _outboxSubscription?.cancel();
    _voiceLimitTimer?.cancel();
    _voiceTicker?.cancel();
    _voiceStopwatch.stop();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _unlockTeacher() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Contacter un enseignant' : 'Contact a teacher'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: _isFrench ? 'Code unique de l’enseignant' : 'Teacher access code',
            hintText: 'FISE-…',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_isFrench ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(_isFrench ? 'Valider' : 'Continue')),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    try {
      final unlocked = await _service.unlockTeacher(code);
      if (!unlocked) {
        if (mounted) _showMessage(_isFrench ? 'Code invalide ou enseignant non associé à votre classe.' : 'Invalid code or teacher not assigned to your class.');
        return;
      }
      if (mounted) {
        setState(() => _contactsFuture = _service.listContacts());
        _showMessage(_isFrench ? 'Enseignant autorisé. Vous pouvez maintenant ouvrir la conversation.' : 'Teacher unlocked. You can now open the conversation.');
      }
    } catch (error) {
      if (mounted) _showMessage('${_isFrench ? 'Impossible de valider le code' : 'Could not validate code'}: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Recharge les messages sans écran de chargement (messages du serveur ou
  /// copie locale, plus les messages en attente d'envoi).
  Future<void> _refreshMessages(MessageContact contact) async {
    try {
      final messages = await _service.listConversation(contact.id);
      if (mounted && _selected?.id == contact.id) {
        setState(() => _messages = messages);
      }
    } catch (_) {
      // Hors ligne sans copie locale : on garde ce qui est affiché.
    }
  }

  Future<void> _select(MessageContact contact) async {
    setState(() {
      _selected = contact;
      _loadingMessages = true;
    });
    try {
      try {
        await _service.markConversationRead(contact.id);
      } catch (_) {
        // Hors ligne : l'accusé de lecture sera renvoyé à la prochaine ouverture.
      }
      final messages = await _service.listConversation(contact.id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _contactsFuture = _service.listContacts();
        });
      }
    } catch (_) {
      if (mounted) {
        _showMessage(_isFrench
            ? 'Impossible de charger la conversation sans connexion.'
            : 'Could not load the conversation while offline.');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMessages = false);
      }
    }
  }

  Future<void> _pendingActions(PrivateMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(_isFrench ? 'Renvoyer' : 'Retry'),
              onTap: () => Navigator.pop(sheetContext, 'retry'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(_isFrench ? 'Supprimer' : 'Delete'),
              onTap: () => Navigator.pop(sheetContext, 'discard'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'retry') {
      await MessageOutbox.instance.retry(message.id);
    } else if (action == 'discard') {
      await MessageOutbox.instance.discard(message.id);
    }
  }

  Future<void> _send() async {
    final contact = _selected;
    final body = _composer.text.trim();
    if (contact == null || _sending) {
      return;
    }
    if (body.isEmpty && _attachment == null) {
      return;
    }

    setState(() => _sending = true);
    try {
      await _service.send(
        recipientId: contact.id,
        body: body,
        attachmentBytes: _attachment?.bytes,
        attachmentName: _attachment?.name,
        attachmentType: _attachment?.mimeType,
        viewOnce: _viewOnce,
      );
      _composer.clear();
      if (mounted) {
        setState(() {
          _attachment = null;
          _viewOnce = false;
        });
      }
      await _refreshMessages(contact);
    } catch (error) {
      if (mounted) _showMessage('${_isFrench ? 'Échec de l’envoi' : 'Message failed to send'}: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _takePhoto() async {
    final file = await _photoService.takePhoto();
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _attachment = PickedAttachment(
        bytes: bytes,
        name: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );
    });
  }

  Future<void> _pickGalleryPhoto() async {
    final file = await _photoService.pickFromGallery();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final extension = file.name.toLowerCase().split('.').last;
    setState(() {
      _attachment = PickedAttachment(
        bytes: bytes,
        name: file.name.isEmpty
            ? 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg'
            : file.name,
        mimeType: extension == 'png'
            ? 'image/png'
            : extension == 'webp'
                ? 'image/webp'
                : 'image/jpeg',
      );
    });
  }

  Future<void> _pickAttachment() async {
    final attachment = await _photoService.pickFile(
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'webp', 'pdf', 'mp4', 'mov',
        'mp3', 'm4a', 'aac', 'txt', 'csv', 'doc', 'docx',
        'xls', 'xlsx', 'ppt', 'pptx',
      ],
    );
    if (attachment != null && mounted) {
      setState(() => _attachment = attachment);
    }
  }

  Future<void> _chooseAttachment() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(_isFrench ? 'Prendre une photo' : 'Take a photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(_isFrench ? 'Choisir une photo' : 'Choose a photo'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(_isFrench ? 'Fichier ou PDF' : 'File or PDF'),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'camera') {
      await _takePhoto();
    } else if (action == 'gallery') {
      await _pickGalleryPhoto();
    } else if (action == 'file') {
      await _pickAttachment();
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
      _voiceLimitTimer?.cancel();
      _voiceLimitTimer = null;
      _voiceTicker?.cancel();
      _voiceTicker = null;
      _voiceStopwatch.stop();
      try {
        final path = await _recorder.stop();
        if (path == null) {
          if (mounted) setState(() => _recordingVoice = false);
          return;
        }
        final bytes = await File(path).readAsBytes();
        if (!mounted) return;
        setState(() {
          _recordingVoice = false;
          _attachment = PickedAttachment(
            bytes: bytes,
            name: 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
            mimeType: 'audio/mp4',
          );
        });
      } catch (error) {
        if (mounted) {
          setState(() => _recordingVoice = false);
          _showMessage('${_isFrench ? 'Échec de l’enregistrement' : 'Recording failed'}: $error');
        }
      }
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _showMessage(_isFrench
            ? 'Autorise le microphone pour enregistrer un message vocal.'
            : 'Allow microphone access to record a voice message.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/fise_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _voiceStopwatch.reset();
      _voiceStopwatch.start();
      _voiceTicker?.cancel();
      _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recordingVoice) return;
        setState(() => _voiceElapsed = _voiceStopwatch.elapsed);
      });
      if (mounted) setState(() { _recordingVoice = true; _voiceElapsed = Duration.zero; });
      _voiceLimitTimer?.cancel();
      _voiceLimitTimer = Timer(const Duration(minutes: 40), () {
        if (!mounted || !_recordingVoice) return;
        _voiceLimitTimer = null;
        unawaited(_toggleVoiceRecording());
        _showMessage(_isFrench ? 'La limite de 40 minutes est atteinte. Le vocal est en cours de préparation.' : 'The 40-minute limit is reached. Preparing your voice message.');
      });
    } catch (error) {
      if (mounted) {
        _showMessage('${_isFrench ? 'Impossible de démarrer le microphone' : 'Could not start the microphone'}: $error');
      }
    }
  }

  Future<void> _confirmDeleteMessage(PrivateMessage message) async {
    final mine = message.senderId == widget.profile.id;
    final forEveryone = await showDialog<bool?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Supprimer le message ?' : 'Delete message?'),
        content: Text(_isFrench
            ? 'Choisis si tu veux retirer le message uniquement ici ou pour tous les participants.'
            : 'Choose whether to remove the message only for you or for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: Text(_isFrench ? 'Annuler' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_isFrench ? 'Pour moi' : 'For me'),
          ),
          if (mine)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_isFrench ? 'Pour tout le monde' : 'For everyone'),
            ),
        ],
      ),
    );
    if (forEveryone == null) return;

    try {
      await _service.deleteMessage(message, forEveryone: forEveryone);
      final contact = _selected;
      if (contact != null && mounted) {
        await _select(contact);
        _showMessage(forEveryone
            ? (_isFrench ? 'Message supprimé pour tout le monde.' : 'Message deleted for everyone.')
            : (_isFrench ? 'Message retiré de ta conversation.' : 'Message removed from your conversation.'));
      }
    } catch (error) {
      if (mounted) _showMessage('${_isFrench ? 'Suppression impossible' : 'Could not delete message'}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFrench ? 'Messagerie privée' : 'Private messages';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: widget.profile.role == 'student'
            ? [IconButton(tooltip: _isFrench ? 'Utiliser le code d’un enseignant' : 'Use teacher code', onPressed: _unlockTeacher, icon: const Icon(Icons.vpn_key_rounded))]
            : null,
      ),
      body: FutureBuilder<List<MessageContact>>(
        future: _contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final contacts = snapshot.data ?? const <MessageContact>[];
          if (contacts.isEmpty) {
            return Center(
              child: Text(
                _isFrench
                    ? 'Aucun contact disponible. Pour écrire à un enseignant, utilisez son code unique avec le bouton en haut.'
                    : 'No contacts available. To message a teacher, use their unique code with the button above.',
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final list = _contacts(contacts);
              final conversation = _conversation();
              return wide
                  ? Row(
                      children: [
                        SizedBox(width: 280, child: list),
                        conversation,
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(height: 190, child: list),
                        conversation,
                      ],
                    );
            },
          );
        },
      ),
    );
  }

  Widget _contacts(List<MessageContact> contacts) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];
          final selected = contact.id == _selected?.id;
          return ListTile(
            selected: selected,
            leading: CircleAvatar(
              child: Text(
                contact.firstName.isEmpty
                    ? '?'
                    : contact.firstName.substring(0, 1),
              ),
            ),
            title: Text(contact.fullName),
            subtitle: Text(
              contact.role == 'teacher'
                  ? (_isFrench ? 'Enseignant' : 'Teacher')
                  : (_isFrench ? 'Élève' : 'Student'),
            ),
            trailing: contact.unreadCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF166534),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      contact.unreadCount > 99 ? '99+' : '${contact.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  )
                : null,
            onTap: () => _select(contact),
          );
        },
      ),
    );
  }


  String _formatElapsed(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _conversation() {
    final contact = _selected;
    if (contact == null) {
      return Expanded(
        child: Center(
          child: Text(
            _isFrench ? 'Sélectionnez un contact.' : 'Select a contact.',
          ),
        ),
      );
    }
    return Expanded(
      child: Column(
        children: [
          ListTile(
            title: Text(contact.fullName),
            subtitle: Text(contact.className ?? ''),
          ),
          Expanded(
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.senderId == widget.profile.id;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => (message.pending || message.failed)
                              ? _pendingActions(message)
                              : _confirmDeleteMessage(message),
                          child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFFDCFCE7)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message.deletedAt != null)
                                Text(
                                  _isFrench ? 'Ce message a été supprimé' : 'This message was deleted',
                                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
                                )
                              else ...[
                                if (message.body.isNotEmpty) Text(message.body),
                                if (message.attachmentPath == null && message.attachmentName != null)
                                  Text('📎 ${message.attachmentName}', style: const TextStyle(fontStyle: FontStyle.italic)),
                                if (message.attachmentPath != null)
                                  _MessageAttachment(
                                    service: _service,
                                    message: message,
                                    currentUserId: widget.profile.id,
                                    isFrench: _isFrench,
                                  ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(message.createdAt),
                                    style: TextStyle(fontSize: 10, color: mine ? Colors.black54 : Colors.black45),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      message.failed
                                          ? Icons.error_outline_rounded
                                          : message.pending
                                              ? Icons.schedule_rounded
                                              : message.readAt != null
                                          ? Icons.done_all_rounded
                                          : message.deliveredAt != null
                                              ? Icons.done_all_rounded
                                              : Icons.done_rounded,
                                      size: 14,
                                      color: message.failed
                                          ? Colors.red
                                          : message.readAt != null
                                          ? const Color(0xFF166534)
                                          : message.deliveredAt != null
                                              ? Colors.black54
                                              : Colors.black45,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: _isFrench ? 'Ajouter une pièce jointe' : 'Add attachment',
                  onPressed: _sending || _recordingVoice ? null : _chooseAttachment,
                  icon: const Icon(Icons.add_rounded),
                ),
                IconButton(
                  tooltip: _viewOnce
                      ? (_isFrench ? 'Désactiver la vue unique' : 'Turn off view once')
                      : (_isFrench ? 'Envoyer en vue unique' : 'Send as view once'),
                  onPressed: _sending
                      ? null
                      : () {
                          if (_attachment == null) {
                            _showMessage(_isFrench
                                ? 'Ajoute une photo ou un fichier avant d’activer la vue unique.'
                                : 'Attach a photo or file before enabling view once.');
                            return;
                          }
                          setState(() => _viewOnce = !_viewOnce);
                        },
                  icon: Icon(
                    _viewOnce ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: _viewOnce ? const Color(0xFF166534) : null,
                  ),
                ),
                IconButton(
                  tooltip: _recordingVoice
                      ? (_isFrench ? 'Arrêter et joindre le vocal' : 'Stop and attach voice')
                      : (_isFrench ? 'Enregistrer un vocal' : 'Record a voice message'),
                  onPressed: _sending ? null : _toggleVoiceRecording,
                  icon: Icon(
                    _recordingVoice ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _recordingVoice ? Colors.red : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                       maxLines: 8,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _recordingVoice
                          ? '${_isFrench ? 'Enregistrement vocal' : 'Recording voice message'} • ${_formatElapsed(_voiceElapsed)}'
                          : _attachment != null
                          ? (_viewOnce
                              ? (_isFrench
                                  ? 'Vue unique : ${_attachment!.name}'
                                  : 'View once: ${_attachment!.name}')
                              : (_isFrench
                              ? 'Pièce jointe : ${_attachment!.name}'
                              : 'Attachment: ${_attachment!.name}'))
                          : (_isFrench
                              ? 'Écrire un message...'
                              : 'Write a message...'),
                      filled: true,
                      fillColor: const Color(0xFFF4F6F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF166534), width: 1.5)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: _isFrench ? 'Envoyer' : 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _MessageAttachment extends StatefulWidget {
  final PrivateMessageService service;
  final PrivateMessage message;
  final String currentUserId;
  final bool isFrench;

  const _MessageAttachment({
    required this.service,
    required this.message,
    required this.currentUserId,
    required this.isFrench,
  });

  @override
  State<_MessageAttachment> createState() => _MessageAttachmentState();
}

class _MessageAttachmentState extends State<_MessageAttachment> {
  bool _openingViewOnce = false;

  Future<void> _openCachedAttachment(String url) async {
    final message = widget.message;
    final name = message.attachmentName ??
        (widget.isFrench ? 'Pièce jointe' : 'Attachment');
    try {
      final opened = await MessageAttachmentOfflineService().open(
        userId: widget.currentUserId,
        conversationId: 'private-' + message.senderId + '-' + message.recipientId,
        messageId: message.id,
        fileName: name,
        mimeType: message.attachmentType ?? '',
        signedUrl: url,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => OfflineResourceViewer(
          locale: Locale(widget.isFrench ? 'fr' : 'en'),
          userId: widget.currentUserId,
          resource: opened.resource,
          localPath: opened.localPath,
        ),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench
                ? 'Ce fichier doit être ouvert une première fois avec Internet pour rester disponible hors ligne.'
                : 'Open this file once while online to keep it available offline.'),
          ),
        );
      }
    }
  }

  Future<void> _openViewOnce() async {
    if (_openingViewOnce) return;
    setState(() => _openingViewOnce = true);
    try {
      final url = await widget.service.openViewOnceAttachment(widget.message.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PrivateAttachmentViewer(
          url: url,
          name: widget.message.attachmentName ??
              (widget.isFrench ? 'Pièce jointe à vue unique' : 'View-once attachment'),
          mimeType: widget.message.attachmentType ?? '',
          isFrench: widget.isFrench,
        ),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isFrench
                ? 'Cette pièce jointe a déjà été ouverte ou n’est plus disponible.'
                : 'This attachment has already been opened or is unavailable.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingViewOnce = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isFrench = widget.isFrench;
    final type = message.attachmentType ?? '';

    // A view-once attachment must never be signed before its single-use claim.
    if (message.viewOnce) {
      if (message.senderId == widget.currentUserId) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_rounded, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message.viewedAt != null
                      ? (isFrench ? 'Vue unique ouverte' : 'View-once opened')
                      : (isFrench ? 'Envoyé en vue unique' : 'Sent as view once'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
      if (message.viewedAt != null) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_rounded, size: 18),
              const SizedBox(width: 6),
              Text(isFrench ? 'Déjà ouvert' : 'Already opened'),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton.icon(
          onPressed: _openingViewOnce ? null : _openViewOnce,
          icon: _openingViewOnce
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_off_rounded),
          label: Text(
            _openingViewOnce
                ? (isFrench ? 'Ouverture…' : 'Opening…')
                : (isFrench ? 'Ouvrir une fois' : 'Open once'),
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: widget.service.signedAttachmentUrl(message.attachmentPath),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          return TextButton.icon(
            onPressed: () => _openCachedAttachment(''),
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(message.attachmentName ?? (isFrench ? 'Pièce jointe' : 'Attachment')),
          );
        }
        if (type.startsWith('audio/') ||
            (message.attachmentName ?? '').toLowerCase().startsWith('voice-') ||
            (message.attachmentName ?? '').toLowerCase().endsWith('.m4a')) {
          return VoiceMessageBubble(url: url, isFrench: isFrench);
        }
        if (type.startsWith('image/')) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () {
                _openCachedAttachment(url);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  width: 220,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton.icon(
            onPressed: () {
              _openCachedAttachment(url);
            },
            icon: Icon(type == 'application/pdf'
                ? Icons.picture_as_pdf_rounded
                : type.startsWith('video/')
                    ? Icons.videocam_rounded
                    : Icons.attach_file_rounded),
            label: Text(message.attachmentName ?? (isFrench ? 'Fichier' : 'File')),
          ),
        );
      },
    );
  }
}

class _PrivateAttachmentViewer extends StatefulWidget {
  final String url;
  final String name;
  final String mimeType;
  final bool isFrench;

  const _PrivateAttachmentViewer({
    required this.url,
    required this.name,
    required this.mimeType,
    required this.isFrench,
  });

  @override
  State<_PrivateAttachmentViewer> createState() => _PrivateAttachmentViewerState();
}

class _PrivateAttachmentViewerState extends State<_PrivateAttachmentViewer> {
  PdfControllerPinch? _pdfController;
  VideoPlayerController? _videoController;
  bool _loading = true;
  String? _error;

  bool get _isPdf => widget.mimeType.toLowerCase().contains('pdf');
  bool get _isVideo => widget.mimeType.toLowerCase().startsWith('video/');

  @override
  void initState() {
    super.initState();
    if (_isPdf) {
      _loadPdf();
    } else if (_isVideo) {
      _loadVideo();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadPdf() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final controller = PdfControllerPinch(
        document: PdfDocument.openData(Future.value(response.bodyBytes)),
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _pdfController = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.isFrench
              ? 'Impossible d’ouvrir ce document.'
              : 'Unable to open this document.';
        });
      }
    }
  }

  Future<void> _loadVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.isFrench
              ? 'Impossible de lire cette vidéo.'
              : 'Unable to play this video.';
        });
      }
    }
  }

  Future<void> _toggleVideo() async {
    final controller = _videoController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _isPdf
                  ? (_pdfController == null
                      ? Center(child: Text(widget.isFrench ? 'Document indisponible.' : 'Document unavailable.'))
                      : PdfViewPinch(controller: _pdfController!))
                  : _isVideo
                      ? (_videoController == null
                          ? Center(child: Text(widget.isFrench ? 'Vidéo indisponible.' : 'Video unavailable.'))
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AspectRatio(
                                    aspectRatio: _videoController!.value.aspectRatio > 0
                                        ? _videoController!.value.aspectRatio
                                        : 16 / 9,
                                    child: VideoPlayer(_videoController!),
                                  ),
                                  IconButton(
                                    onPressed: _toggleVideo,
                                    icon: Icon(_videoController!.value.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded),
                                    iconSize: 48,
                                  ),
                                ],
                              ),
                            ))
                      : widget.mimeType.toLowerCase().startsWith('audio/')
                      ? Center(child: _RemoteAudioMessage(url: widget.url, isFrench: widget.isFrench))
                      : widget.mimeType.toLowerCase().startsWith('image/')
                          ? Center(
                              child: InteractiveViewer(
                                child: Image.network(widget.url, fit: BoxFit.contain),
                              ),
                            )
                          : Center(
                              child: Text(widget.isFrench
                                  ? 'Type de fichier non pris en charge.'
                                  : 'Unsupported file type.'),
                            ),
    );
  }
}


class _RemoteAudioMessage extends StatefulWidget {
  final String url;
  final bool isFrench;

  const _RemoteAudioMessage({required this.url, required this.isFrench});

  @override
  State<_RemoteAudioMessage> createState() => _RemoteAudioMessageState();
}

class _RemoteAudioMessageState extends State<_RemoteAudioMessage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completed;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _completed = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = _duration;
        });
      }
    });
    _durationSubscription = _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    unawaited(_prepareDuration());
  }

  /// Load the audio source without starting playback so its total duration is
  /// visible as soon as the voice message appears in the conversation.
  Future<void> _prepareDuration() async {
    try {
      await _player.setSourceUrl(widget.url);
      final duration = await _player.getDuration();
      if (mounted && duration != null && duration > Duration.zero) {
        setState(() => _duration = duration);
      }
    } catch (_) {
      // The message remains playable; the duration will be filled when playback starts.
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (_position >= _duration && _duration > Duration.zero) {
      await _player.seek(Duration.zero);
      if (mounted) setState(() => _position = Duration.zero);
    }
    if (mounted) setState(() => _playing = true);
    try {
      await _player.play(UrlSource(widget.url));
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isFrench ? 'Lecture audio impossible.' : 'Unable to play audio.')),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_completed?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final current = _position.inMilliseconds.clamp(0, total > 0 ? total : 1);
    return SizedBox(
      width: 230,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.isFrench ? 'Message vocal' : 'Voice message',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total > 0 ? current / total : 0,
                  minHeight: 3,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatDuration(_position)} / ${_duration == Duration.zero ? '--:--' : _formatDuration(_duration)}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}