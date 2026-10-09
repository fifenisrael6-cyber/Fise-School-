import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/private_message_service.dart';
import '../../../models/private_message.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/photo_service.dart';
import 'message_attachment_viewer_page.dart';

class PrivateMessagesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const PrivateMessagesPage({
    super.key,
    required this.locale,
    required this.profile,
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
  bool _recordingVoice = false;
  AudioRecorder? _voiceRecorder;
  final PhotoService _photoService = PhotoService();
  RealtimeChannel? _channel;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _contactsFuture = _service.listContacts();
    _channel = Supabase.instance.client.channel('private-messages-${widget.profile.id}')
      ..onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'private_messages', callback: (payload) {
        final row = payload.newRecord;
        if (row['sender_id'] == widget.profile.id || row['recipient_id'] == widget.profile.id) {
          final selected = _selected;
          if (selected != null && (row['sender_id'] == selected.id || row['recipient_id'] == selected.id)) {
            _select(selected);
          }
          if (mounted) {
            setState(() => _contactsFuture = _service.listContacts());
          }
        }
      })
      .subscribe();
  }

  @override
  void dispose() {
    _composer.dispose();
    _channel?.unsubscribe();
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    if (recorder != null) unawaited(recorder.dispose());
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

  Future<void> _select(MessageContact contact) async {
    setState(() {
      _selected = contact;
      _loadingMessages = true;
    });
    try {
      final messages = await _service.listConversation(contact.id);
      await _service.markConversationRead(contact.id);
      if (mounted) {
        setState(() => _messages = messages);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMessages = false);
      }
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
      await _select(contact);
    } catch (error) {
      if (mounted) _showMessage('${_isFrench ? 'Échec de l’envoi' : 'Message failed to send'}: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }


  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
      final recorder = _voiceRecorder;
      if (recorder == null) return;
      try {
        final path = await recorder.stop();
        _voiceRecorder = null;
        await recorder.dispose();
        if (path == null || path.isEmpty) {
          if (mounted) setState(() => _recordingVoice = false);
          return;
        }
        final file = File(path);
        if (!await file.exists()) {
          if (mounted) {
            setState(() => _recordingVoice = false);
            _showMessage(_isFrench ? 'Enregistrement vocal introuvable.' : 'Voice recording not found.');
          }
          return;
        }
        final bytes = await file.readAsBytes();
        try { await file.delete(); } catch (_) {}
        if (!mounted) return;
        setState(() {
          _recordingVoice = false;
          _attachment = PickedAttachment(
            bytes: bytes,
            name: 'message-vocal-${DateTime.now().millisecondsSinceEpoch}.m4a',
            mimeType: 'audio/mp4',
          );
          _viewOnce = false;
        });
      } catch (error) {
        if (mounted) {
          setState(() => _recordingVoice = false);
          _showMessage('${_isFrench ? 'Échec de l’enregistrement vocal' : 'Voice recording failed'}: $error');
        }
      }
      return;
    }

    try {
      final recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        if (mounted) {
          _showMessage(_isFrench
              ? 'Autorisez le microphone dans les paramètres du téléphone.'
              : 'Allow microphone access in phone settings.');
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/fise-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await recorder.cancel();
        await recorder.dispose();
        return;
      }
      setState(() {
        _voiceRecorder = recorder;
        _recordingVoice = true;
      });
    } catch (error) {
      if (mounted) {
        _showMessage('${_isFrench ? 'Impossible de démarrer le microphone' : 'Could not start the microphone'}: $error');
      }
    }
  }

  Future<void> _openAttachment(PrivateMessage message) async {
    try {
      final url = await _service.openAttachmentUrl(message);
      if (url == null || url.isEmpty) {
        if (mounted) {
          _showMessage(_isFrench
              ? 'Cette pièce jointe n’est plus disponible.'
              : 'This attachment is no longer available.');
        }
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageAttachmentViewerPage(
            url: url,
            title: message.attachmentName ?? (_isFrench ? 'Pièce jointe' : 'Attachment'),
            mimeType: message.attachmentType ?? 'application/octet-stream',
            viewOnce: message.viewOnce,
          ),
        ),
      );
      final contact = _selected;
      if (mounted && contact != null) await _select(contact);
    } catch (error) {
      if (mounted) {
        _showMessage('${_isFrench ? 'Impossible d’ouvrir la pièce jointe' : 'Could not open attachment'}: $error');
      }
    }
  }

  Future<void> _deleteMessage(
    PrivateMessage message, {
    required bool forEveryone,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Supprimer le message ?' : 'Delete message?'),
        content: Text(forEveryone
            ? (_isFrench
                ? 'Le message sera supprimé pour tous les participants.'
                : 'The message will be deleted for everyone.')
            : (_isFrench
                ? 'Le message sera masqué uniquement pour vous.'
                : 'The message will be hidden only for you.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_isFrench ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_isFrench ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteMessage(message.id, forEveryone: forEveryone);
      final contact = _selected;
      if (contact != null && mounted) await _select(contact);
    } catch (error) {
      if (mounted) {
        _showMessage('${_isFrench ? 'Suppression impossible' : 'Could not delete message'}: $error');
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

  Future<void> _pickAttachment() async {
    final attachment = await _photoService.pickFile(
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'mp4', 'mp3', 'm4a'],
    );
    if (attachment != null && mounted) {
      setState(() => _attachment = attachment);
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
            onTap: () => _select(contact),
          );
        },
      ),
    );
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
                                  _isFrench ? 'Ce message a été supprimé.' : 'This message was deleted.',
                                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
                                )
                              else if (message.body.isNotEmpty)
                                Text(message.body),
                              if (message.deletedAt == null && message.attachmentPath != null)
                                _MessageAttachment(
                                  message: message,
                                  isFrench: _isFrench,
                                  isMine: mine,
                                  onOpen: () => _openAttachment(message),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatTime(message.createdAt),
                                    style: TextStyle(fontSize: 10, color: mine ? Colors.black54 : Colors.black45),
                                  ),
                                  if (message.deletedAt == null)
                                    PopupMenuButton<String>(
                                      padding: EdgeInsets.zero,
                                      iconSize: 16,
                                      tooltip: _isFrench ? 'Options du message' : 'Message options',
                                      onSelected: (value) => _deleteMessage(
                                        message,
                                        forEveryone: value == 'everyone',
                                      ),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'me',
                                          child: Text(_isFrench ? 'Supprimer pour moi' : 'Delete for me'),
                                        ),
                                        if (mine)
                                          PopupMenuItem(
                                            value: 'everyone',
                                            child: Text(_isFrench ? 'Supprimer pour tout le monde' : 'Delete for everyone'),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_attachment != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Row(
                children: [
                  const Icon(Icons.attach_file_rounded, size: 18),
                  Expanded(
                    child: Text(
                      _attachment!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Checkbox(
                    value: _viewOnce,
                    onChanged: _sending ? null : (value) => setState(() => _viewOnce = value ?? false),
                  ),
                  Flexible(child: Text(_isFrench ? 'Voir une fois' : 'View once')),
                  IconButton(
                    tooltip: _isFrench ? 'Retirer le fichier' : 'Remove attachment',
                    onPressed: _sending ? null : () => setState(() {
                      _attachment = null;
                      _viewOnce = false;
                    }),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: _isFrench ? 'Prendre une photo' : 'Take a photo',
                  onPressed: _sending ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_rounded),
                ),
                IconButton(
                  tooltip: _isFrench ? 'Joindre un fichier' : 'Attach a file',
                  onPressed: _sending ? null : _pickAttachment,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _attachment != null
                          ? (_isFrench
                              ? 'Pièce jointe : ${_attachment!.name}'
                              : 'Attachment: ${_attachment!.name}')
                          : (_isFrench
                              ? 'Écrire un message...'
                              : 'Write a message...'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _recordingVoice
                      ? (_isFrench ? 'Arrêter l’enregistrement' : 'Stop recording')
                      : (_isFrench ? 'Message vocal' : 'Voice message'),
                  onPressed: _sending ? null : _toggleVoiceRecording,
                  icon: Icon(
                    _recordingVoice ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _recordingVoice ? Colors.red : null,
                  ),
                ),
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
        ],
      ),
    );
  }
}


class _MessageAttachment extends StatelessWidget {
  final PrivateMessage message;
  final bool isFrench;
  final bool isMine;
  final Future<void> Function() onOpen;

  const _MessageAttachment({
    required this.message,
    required this.isFrench,
    required this.isMine,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final type = (message.attachmentType ?? '').toLowerCase();
    final name = message.attachmentName ?? (isFrench ? 'Pièce jointe' : 'Attachment');

    if (message.viewOnce) {
      final alreadyOpened = message.viewedAt != null && !isMine;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton.icon(
          onPressed: isMine || alreadyOpened ? null : onOpen,
          icon: const Icon(Icons.visibility_rounded),
          label: Text(isMine
              ? (isFrench ? 'Envoyé • Voir une fois' : 'Sent • View once')
              : alreadyOpened
                  ? (isFrench ? 'Déjà ouvert' : 'Already opened')
                  : (isFrench ? 'Ouvrir une fois' : 'Open once')),
        ),
      );
    }

    if (type.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<String?>(
              future: PrivateMessageService().signedAttachmentUrl(message.attachmentPath),
              builder: (context, snapshot) {
                if (snapshot.data == null) {
                  return SizedBox(
                    width: 220,
                    height: 100,
                    child: Center(child: Text(isFrench ? 'Chargement de la photo…' : 'Loading photo…')),
                  );
                }
                return Image.network(
                  snapshot.data!,
                  width: 220,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: 220,
                    height: 80,
                    child: Center(child: Text(isFrench ? 'Photo indisponible' : 'Photo unavailable')),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    final audio = type.startsWith('audio/');
    final pdf = type.contains('pdf') || name.toLowerCase().endsWith('.pdf');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextButton.icon(
        onPressed: onOpen,
        icon: Icon(audio ? Icons.play_circle_fill_rounded
            : pdf ? Icons.picture_as_pdf_rounded
            : Icons.insert_drive_file_rounded),
        label: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
