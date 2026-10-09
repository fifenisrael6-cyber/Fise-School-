import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/private_message_service.dart';
import '../../../models/private_message.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/voice_note_service.dart';
import '../widgets/message_attachment_viewer.dart';

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
  final PhotoService _photoService = PhotoService();
  final VoiceNoteService _voiceNoteService = VoiceNoteService();
  bool _recordingVoice = false;
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
    unawaited(_voiceNoteService.dispose());
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
    if (_recordingVoice) {
      _showMessage(_isFrench ? 'Arrêtez l’enregistrement avant l’envoi.' : 'Stop recording before sending.');
      return;
    }
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
      );
      _composer.clear();
      if (mounted) {
        setState(() => _attachment = null);
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

  Future<void> _deleteMessage(PrivateMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isFrench ? 'Supprimer le message ?' : 'Delete message?'),
        content: Text(_isFrench
            ? 'Ce message sera supprimé pour tous les participants.'
            : 'This message will be deleted for all participants.'),
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
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMessage(message);
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((item) => item.id != message.id).toList();
      });
      _showMessage(_isFrench ? 'Message supprimé.' : 'Message deleted.');
    } catch (error) {
      if (mounted) {
        _showMessage(_isFrench
            ? 'Impossible de supprimer ce message : $error'
            : 'Could not delete this message: $error');
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

  Future<void> _toggleVoiceRecording() async {
    if (_sending) return;
    if (!_recordingVoice && _attachment != null) {
      _showMessage(_isFrench
          ? 'Envoyez ou retirez d’abord la pièce jointe actuelle.'
          : 'Send or remove the current attachment first.');
      return;
    }
    if (_recordingVoice) {
      try {
        final attachment = await _voiceNoteService.stop();
        if (!mounted) return;
        setState(() {
          _recordingVoice = false;
          if (attachment != null) _attachment = attachment;
        });
        if (attachment == null) {
          _showMessage(_isFrench
              ? 'Aucun audio enregistré.'
              : 'No audio was recorded.');
        } else {
          _showMessage(_isFrench
              ? 'Message vocal prêt à être envoyé.'
              : 'Voice message is ready to send.');
        }
      } catch (error) {
        if (mounted) {
          setState(() => _recordingVoice = false);
          _showMessage('${_isFrench ? 'Échec de l’enregistrement' : 'Recording failed'}: $error');
        }
      }
      return;
    }
    try {
      await _voiceNoteService.start();
      if (mounted) setState(() => _recordingVoice = true);
    } catch (error) {
      if (mounted) {
        _showMessage(_isFrench
            ? 'Impossible d’utiliser le microphone. Vérifiez son autorisation.'
            : 'Could not use the microphone. Check its permission.');
      }
    }
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
                              if (message.body.isNotEmpty) Text(message.body),
                              if (message.attachmentPath != null)
                                MessageAttachmentViewer(
                                  key: ValueKey(message.id),
                                  messageId: message.id,
                                  attachmentPath: message.attachmentPath!,
                                  attachmentName: message.attachmentName,
                                  attachmentType: message.attachmentType,
                                  isFrench: _isFrench,
                                  loadUrl: () => _service.signedAttachmentUrl(message.attachmentPath),
                                ),
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
                                    Icon(message.readAt == null ? Icons.done_rounded : Icons.done_all_rounded, size: 14, color: message.readAt == null ? Colors.black45 : const Color(0xFF166534)),
                                    PopupMenuButton<String>(
                                      tooltip: _isFrench ? 'Options du message' : 'Message options',
                                      padding: EdgeInsets.zero,
                                      iconSize: 16,
                                      onSelected: (value) {
                                        if (value == 'delete') _deleteMessage(message);
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(_isFrench ? 'Supprimer' : 'Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                IconButton(
                  tooltip: _recordingVoice
                      ? (_isFrench ? 'Arrêter le vocal' : 'Stop voice message')
                      : (_isFrench ? 'Enregistrer un vocal' : 'Record voice message'),
                  onPressed: _sending ? null : _toggleVoiceRecording,
                  icon: Icon(_recordingVoice ? Icons.stop_circle_rounded : Icons.mic_none_rounded),
                  color: _recordingVoice ? Colors.red : null,
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    enabled: !_recordingVoice,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _recordingVoice
                          ? (_isFrench ? 'Enregistrement vocal…' : 'Recording voice message…')
                          : _attachment != null
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
