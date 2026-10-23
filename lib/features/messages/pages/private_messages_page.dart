import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/private_message_service.dart';
import '../../../core/offline/app_database.dart';
import '../../../models/private_message.dart';
import '../../../core/services/message_quota_events.dart';
import '../widgets/message_media.dart';
import '../widgets/message_reply.dart';
import '../widgets/user_avatar.dart';
import '../widgets/voice_recorder.dart';
import '../../../core/services/quota_service.dart';
import '../../premium/premium_gate.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/photo_service.dart';

class PrivateMessagesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final PickedAttachment? initialAttachment;
  final String? initialContactId;

  const PrivateMessagesPage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialAttachment,
    this.initialContactId,
  });

  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  final _service = PrivateMessageService();
  final AppDatabase _localDb = AppDatabase();
  Map<String, Map<String, dynamic>> _conversationPreferences = {};
  bool _showArchived = false;
  final _composer = TextEditingController();
  final _searchController = TextEditingController();
  bool _searching = false;
  late Future<List<MessageContact>> _contactsFuture;
  MessageContact? _selected;
  List<PrivateMessage> _messages = const [];
  bool _loadingMessages = false;
  bool _sending = false;
  PickedAttachment? _attachment;
  PrivateMessage? _replyTo;
  final PhotoService _photoService = PhotoService();
  RealtimeChannel? _channel;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    MessageQuotaEvents.denied.addListener(_onMessageDenied);
    _attachment = widget.initialAttachment;
    _contactsFuture = _service.listContacts();
    _loadConversationPreferences();
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
      ..onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'private_messages', callback: (payload) {
        final row = payload.newRecord;
        if (row['sender_id'] == widget.profile.id || row['recipient_id'] == widget.profile.id) {
          final selected = _selected;
          if (selected != null && (row['sender_id'] == selected.id || row['recipient_id'] == selected.id)) {
            _select(selected);
          }
        }
      })
      .subscribe();
  }


  Future<void> _loadConversationPreferences() async {
    try {
      final preferences = await _localDb.getMessageConversationPreferences(widget.profile.id);
      if (mounted) setState(() => _conversationPreferences = preferences);
    } catch (_) {}
  }

  Map<String, dynamic> _contactPreference(String id) =>
      _conversationPreferences['private:$id'] ?? const <String, dynamic>{};

  Future<void> _saveContactPreference(
    MessageContact contact, {
    bool? pinned,
    bool? archived,
    String? mutedUntil,
    bool clearMute = false,
  }) async {
    final current = _contactPreference(contact.id);
    final nextPinned = pinned ?? current['pinned'] == true;
    if (nextPinned && current['pinned'] != true) {
      final count = _conversationPreferences.values
          .where((value) => value['pinned'] == true && value['archived'] != true)
          .length;
      if (count >= 3) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isFrench ? 'Maximum 3 discussions épinglées.' : 'You can pin at most 3 chats.'),
        ));
        return;
      }
    }
    await _localDb.saveMessageConversationPreference(
      userId: widget.profile.id,
      conversationType: 'private',
      conversationId: contact.id,
      pinned: nextPinned,
      archived: archived ?? current['archived'] == true,
      mutedUntil: clearMute ? null : (mutedUntil ?? current['muted_until'] as String?),
    );
    await _loadConversationPreferences();
  }

  Future<void> _showContactActions(MessageContact contact) async {
    final pref = _contactPreference(contact.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Wrap(children: [
        ListTile(
          leading: Icon(pref['pinned'] == true ? Icons.push_pin_outlined : Icons.push_pin_rounded),
          title: Text(pref['pinned'] == true ? (_isFrench ? 'Désépingler' : 'Unpin chat') : (_isFrench ? 'Épingler' : 'Pin chat')),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _saveContactPreference(contact, pinned: pref['pinned'] != true);
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(_isFrench ? 'Mettre en sourdine 8 heures' : 'Mute for 8 hours'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _saveContactPreference(contact, mutedUntil: DateTime.now().add(const Duration(hours: 8)).toUtc().toIso8601String());
          },
        ),
        if (pref['muted_until'] != null)
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(_isFrench ? 'Réactiver les notifications' : 'Unmute notifications'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _saveContactPreference(contact, clearMute: true);
            },
          ),
        ListTile(
          leading: Icon(pref['archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined),
          title: Text(pref['archived'] == true ? (_isFrench ? 'Désarchiver' : 'Unarchive chat') : (_isFrench ? 'Archiver' : 'Archive chat')),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _saveContactPreference(contact, archived: pref['archived'] != true);
          },
        ),
      ])),
    );
  }

  bool _gateOpen = false;
  bool _initialContactHandled = false;

  /// Le serveur a refusé un envoi (quota gratuit épuisé ou pièce jointe réservée) :
  /// on ouvre la fenêtre Premium ; si le paiement est confirmé, l'élève peut renvoyer son message.
  Future<void> _onMessageDenied() async {
    if (!mounted || _gateOpen) return;
    _gateOpen = true;
    final premiumOnly = MessageQuotaEvents.lastKind == 'premium';
    final ok = await PremiumGate.openForServerDenial(
      context,
      profile: widget.profile,
      feature: QuotaFeature.msgSent,
      premiumOnly: premiumOnly,
    );
    _gateOpen = false;
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.profile.preferredLanguage == 'en'
            ? 'Premium is active. Please send your message again.'
            : 'Premium activé. Renvoie ton message.'),
      ));
    }
  }

  @override
  void dispose() {
    MessageQuotaEvents.denied.removeListener(_onMessageDenied);
    _composer.dispose();
    _searchController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _select(MessageContact contact) async {
    setState(() {
      if (_selected?.id != contact.id) _replyTo = null;
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

  PrivateMessage? _findMessage(String? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _authorOf(PrivateMessage m, MessageContact contact) =>
      m.senderId == widget.profile.id ? (_isFrench ? 'Vous' : 'You') : contact.fullName;

  String _snippetOf(PrivateMessage m) => replySnippet(
        body: m.body,
        hasAttachment: m.attachmentPath != null || m.localAttachmentPath != null,
        attachmentName: m.attachmentName,
        attachmentType: m.attachmentType,
        french: _isFrench,
      );

  Future<void> _showMessageActions(PrivateMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(_isFrench ? 'Répondre' : 'Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyTo = message);
              },
            ),
            if (message.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(_isFrench ? 'Copier' : 'Copy'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(_isFrench ? 'Message copié.' : 'Message copied.'),
                    ));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  List<PrivateMessage> _visiblePrivateMessages() {
    final query = _searchController.text.trim().toLowerCase();
    if (!_searching || query.isEmpty) return _messages;
    return _messages.where((message) =>
      message.body.toLowerCase().contains(query) ||
      (message.attachmentName ?? '').toLowerCase().contains(query)
    ).toList(growable: false);
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

    // Limite gratuite atteinte / pièce jointe réservée : fenêtre Premium tout de suite,
    // sans que le message apparaisse dans la conversation.
    final canSend = await PremiumGate.canSend(
      context,
      profile: widget.profile,
      feature: QuotaFeature.msgSent,
      hasAttachment: _attachment != null,
    );
    if (!canSend || !mounted) return;

    setState(() => _sending = true);
    try {
      await _service.send(
        recipientId: contact.id,
        body: body,
        attachmentBytes: _attachment?.bytes,
        attachmentName: _attachment?.name,
        attachmentType: _attachment?.mimeType,
        replyToId: _replyTo?.id,
      );
      _composer.clear();
      if (mounted) {
        setState(() {
          _attachment = null;
          _replyTo = null;
        });
      }
      await _select(contact);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            error.toString().replaceFirst('Bad state: ', ''),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: _isFrench ? 'Réessayer' : 'Retry',
            onPressed: () => _send(),
          ),
        ));
      }
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
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _isFrench ? 'Rechercher' : 'Search',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(title),
        actions: [
          IconButton(
            tooltip: _searching ? (_isFrench ? 'Fermer' : 'Close') : (_isFrench ? 'Rechercher' : 'Search'),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              if (_searching) _searchController.clear();
              _searching = !_searching;
            }),
          ),
        ],
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
          final query = _searchController.text.trim().toLowerCase();
          final visibleContacts = contacts.where((contact) {
            final pref = _contactPreference(contact.id);
            if (_showArchived != (pref['archived'] == true)) return false;
            if (_selected == null && query.isNotEmpty && !contact.fullName.toLowerCase().contains(query)) return false;
            return true;
          }).toList(growable: false)
            ..sort((a, b) {
              final ap = _contactPreference(a.id)['pinned'] == true ? 1 : 0;
              final bp = _contactPreference(b.id)['pinned'] == true ? 1 : 0;
              return bp.compareTo(ap);
            });
          final initialId = widget.initialContactId;
          if (!_initialContactHandled && initialId != null) {
            _initialContactHandled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              for (final contact in contacts) {
                if (contact.id == initialId) {
                  _select(contact);
                  break;
                }
              }
            });
          }
          if (contacts.isEmpty) {
            return Center(
              child: Text(
                _isFrench
                    ? 'Aucun contact disponible dans votre classe.'
                    : 'No contact is available in your class.',
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final list = Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
              ChoiceChip(label: Text(_isFrench ? 'Discussions' : 'Chats'), selected: !_showArchived, onSelected: (_) => setState(() => _showArchived = false)),
              const SizedBox(width: 8),
              ChoiceChip(label: Text(_isFrench ? 'Archivées' : 'Archived'), selected: _showArchived, onSelected: (_) => setState(() => _showArchived = true)),
            ])),
            Expanded(child: _contacts(visibleContacts)),
          ]);
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
            leading: UserAvatar(path: contact.avatarPath, name: contact.fullName, radius: 22),
            title: Text(contact.fullName),
            subtitle: Text(
              contact.role == 'teacher'
                  ? (_isFrench ? 'Enseignant' : 'Teacher')
                  : (_isFrench ? 'Élève' : 'Student'),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_contactPreference(contact.id)['pinned'] == true) const Icon(Icons.push_pin_rounded, size: 15),
              if (_contactPreference(contact.id)['muted_until'] != null) const Icon(Icons.notifications_off_outlined, size: 15),
            ]),
            onLongPress: () => _showContactActions(contact),
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
            leading: UserAvatar(path: contact.avatarPath, name: contact.fullName, radius: 22),
            title: Text(contact.fullName),
            subtitle: Text(contact.className ?? ''),
          ),
          Expanded(
            child: _loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _visiblePrivateMessages().length,
                    itemBuilder: (context, index) {
                      final message = _visiblePrivateMessages()[index];
                      final mine = message.senderId == widget.profile.id;
                      final quoted = _findMessage(message.replyToId);
                      return GestureDetector(
                        onLongPress: () => _showMessageActions(message),
                        child: SwipeToReply(
                        enabled: !message.isPending,
                        onReply: () => setState(() => _replyTo = message),
                        child: Row(
                        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!mine)
                            Padding(
                              padding: const EdgeInsets.only(right: 8, bottom: 8),
                              child: UserAvatar(path: contact.avatarPath, name: contact.fullName),
                            ),
                          Flexible(
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
                              if (message.replyToId != null)
                                QuotedMessage(
                                  author: quoted == null ? '' : _authorOf(quoted, contact),
                                  snippet: quoted == null
                                      ? (_isFrench ? 'Message indisponible' : 'Message unavailable')
                                      : _snippetOf(quoted),
                                ),
                              if (message.body == '__PREMIUM_LOCKED__')
                                InkWell(
                                  onTap: () => PremiumGate.openForServerDenial(
                                    context,
                                    profile: widget.profile,
                                    feature: QuotaFeature.msgRecv,
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.lock_outline_rounded, size: 18),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(widget.profile.preferredLanguage == 'en'
                                          ? 'Message locked — free limit reached. Go Premium to read it.'
                                          : 'Message verrouillé — limite gratuite atteinte. Passe à Premium pour le lire.'),
                                    ),
                                  ]),
                                )
                              else if (message.body.isNotEmpty)
                                Text(message.body),
                              if (message.attachmentPath != null || message.localAttachmentPath != null)
                                MessageAttachmentView(
                                  name: message.attachmentName,
                                  type: message.attachmentType,
                                  localPath: message.localAttachmentPath,
                                  remotePath: message.attachmentPath,
                                  resolveUrl: _service.signedAttachmentUrl,
                                  french: _isFrench,
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
                                    Icon(
                                      message.isPending
                                          ? Icons.schedule_rounded
                                          : (message.readAt != null || message.deliveredAt != null
                                              ? Icons.done_all_rounded
                                              : Icons.done_rounded),
                                      size: 16,
                                      color: message.isPending
                                          ? Colors.black45
                                          : (message.readAt != null
                                              ? const Color(0xFF2EAD65)
                                              : (message.deliveredAt != null
                                                  ? Colors.black54
                                                  : Colors.black87)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                          ),
                          if (mine)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 8),
                              child: OwnAvatar(profile: widget.profile),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyTo != null)
                  ReplyComposerBar(
                    author: _authorOf(_replyTo!, contact),
                    snippet: _snippetOf(_replyTo!),
                    french: _isFrench,
                    onCancel: () => setState(() => _replyTo = null),
                  ),
                Row(
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
                VoiceRecorderButton(
                  french: _isFrench,
                  enabled: !_sending,
                  onRecorded: (voice) {
                    setState(() => _attachment = voice);
                    _send();
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _attachment != null
                          ? (_isFrench
                              ? 'Pièce jointe : ${_attachment!.name}'
                              : 'Attachment: ${_attachment!.name}')
                          : (_isFrench
                              ? 'Écrire un message...'
                              : 'Write a message...'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF166534), width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
