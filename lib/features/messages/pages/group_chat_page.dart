import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/group_message_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/message_group.dart';
import '../../../core/services/message_quota_events.dart';
import '../widgets/message_media.dart';
import '../widgets/message_reply.dart';
import '../widgets/user_avatar.dart';
import '../widgets/voice_recorder.dart';
import '../../../core/services/quota_service.dart';
import '../../premium/premium_gate.dart';
import '../../../models/user_profile.dart';

/// Conversation d'un groupe, façon WhatsApp.
class GroupChatPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final MessageGroup group;
  final PickedAttachment? initialAttachment;

  const GroupChatPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.group,
    this.initialAttachment,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final GroupMessageService _service = GroupMessageService();
  final PhotoService _photoService = PhotoService();
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  List<GroupMessage> _messages = const [];

  List<MessageMediaGalleryItem> get _mediaGalleryItems => _messages.where((message) {
        if (message.deletedAt != null ||
            (message.attachmentPath == null && message.localAttachmentPath == null)) return false;
        final type = (message.attachmentType ?? '').toLowerCase();
        final name = (message.attachmentName ?? '').toLowerCase();
        return type.startsWith('image/') || type.startsWith('video/') ||
            name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') ||
            name.endsWith('.webp') || name.endsWith('.gif') || name.endsWith('.mp4');
      }).map((message) => MessageMediaGalleryItem(
        name: message.attachmentName ?? 'Média',
        type: message.attachmentType,
        localPath: message.localAttachmentPath,
        remotePath: message.attachmentPath,
        cacheScope: widget.profile.id,
      )).toList(growable: false);
  bool _loading = true;
  String? _loadError;
  int _loadGeneration = 0;
  bool _sending = false;
  PickedAttachment? _attachment;
  GroupMessage? _replyTo;
  RealtimeChannel? _channel;
  String? _inviteCode;
  bool _announcementsOnly = false;
  bool _groupActionInProgress = false;
  int? _memberCount;
  final Set<String> _selectedMessageIds = <String>{};
  String? _groupAvatarPath;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _isOwner => widget.group.ownerId == widget.profile.id;

  @override
  void initState() {
    super.initState();
    MessageQuotaEvents.denied.addListener(_onMessageDenied);
    _inviteCode = widget.group.inviteCode;
    _groupAvatarPath = widget.group.avatarPath;
    _attachment = widget.initialAttachment;
    _load();
    _loadGroupSettings();
    _channel = Supabase.instance.client
        .channel('group-chat-${widget.group.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) { _load(showLoader: false); _loadGroupSettings(); },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'message_group_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) => _load(showLoader: false),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) {
          _loadGroupSettings();
          if (mounted) {
            _snack(_fr
                ? 'Un membre a rejoint le groupe.'
                : 'A member joined the group.');
          }
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'message_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) {
          _loadGroupSettings();
          if (mounted) {
            _snack(_fr
                ? 'Un membre a quitté le groupe.'
                : 'A member left the group.');
          }
        },
      )
      ..subscribe();
  }

  bool _gateOpen = false;

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

  Future<void> _load({bool showLoader = true}) async {
    final generation = ++_loadGeneration;
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    List<GroupMessage> cached = const [];
    try {
      cached = await _service.getCachedMessages(widget.group.id);
    } catch (_) {
      // Continue with Supabase if local cache cannot be read.
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _messages = cached;
      if (cached.isNotEmpty || !showLoader) _loading = false;
      if (cached.isNotEmpty) _loadError = null;
    });
    unawaited(_prefetchGroupAvatars(cached));
    unawaited(_refreshMessages(generation, hadCache: cached.isNotEmpty));
  }

  Future<void> _prefetchGroupAvatars(List<GroupMessage> messages) async {
    final paths = <String>{
      if ((_groupAvatarPath ?? '').isNotEmpty) _groupAvatarPath!,
      ...messages.map((message) => message.senderAvatarPath ?? '')
          .where((path) => path.isNotEmpty),
    };
    await Future.wait(paths.map((path) async {
      try {
        await _photoService.cachedAvatarFile(path);
      } catch (_) {
        // Avatar caching is opportunistic and never blocks the message list.
      }
    }));
  }

  Future<void> _refreshMessages(int generation, {required bool hadCache}) async {
    try {
      final messages = await _service
          .listMessages(widget.group.id)
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _loadGeneration) return;
      unawaited(_prefetchGroupAvatars(messages));
      setState(() {
        _messages = messages;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = hadCache ? null : error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changeGroupAvatar() async {
    if (!_isOwner || _groupActionInProgress) return;
    final image = await _photoService.pickFile(allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
    if (image == null || !mounted) return;
    final extension = image.name.contains('.') ? image.name.split('.').last.toLowerCase() : 'jpg';
    final safeExtension = ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
    final path = widget.profile.id + '/groups/' + widget.group.id + '/avatar-' + DateTime.now().millisecondsSinceEpoch.toString() + '.' + safeExtension;
    try {
      setState(() => _groupActionInProgress = true);
      await Supabase.instance.client.storage.from('profile-photos').uploadBinary(
        path, image.bytes,
        fileOptions: FileOptions(upsert: false, contentType: image.mimeType),
      );
      final oldPath = await Supabase.instance.client.rpc('set_message_group_avatar', params: {
        'p_group_id': widget.group.id, 'p_avatar_path': path,
      });
      if (oldPath is String && oldPath.isNotEmpty && oldPath != path) {
        try { await Supabase.instance.client.storage.from('profile-photos').remove([oldPath]); } catch (_) {}
      }
      if (mounted) {
        setState(() => _groupAvatarPath = path);
        _snack(_fr ? 'Photo du groupe mise à jour.' : 'Group photo updated.');
      }
    } catch (error) {
      try { await Supabase.instance.client.storage.from('profile-photos').remove([path]); } catch (_) {}
      if (mounted) _snack((_fr ? 'Impossible de modifier la photo : ' : 'Could not update group photo: ') + error.toString());
    } finally {
      if (mounted) setState(() => _groupActionInProgress = false);
    }
  }

  Future<void> _loadGroupSettings() async {
    try {
      final value = await _service.getAnnouncementsOnly(widget.group.id);
      final members = await _service.listMembers(widget.group.id);
      if (mounted) setState(() { _announcementsOnly = value; _memberCount = members.length; });
    } catch (_) {}
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Supprimer le groupe ?' : 'Delete this group?'),
        content: Text(_fr
            ? 'Le groupe et son historique seront supprimés pour tous les membres. Cette action est définitive.'
            : 'The group and its history will be deleted for all members. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      setState(() => _groupActionInProgress = true);
      await _service.deleteGroup(widget.group.id);
      if (mounted) { Navigator.of(context).pop(); Navigator.of(context).pop(); }
    } catch (error) {
      _snack((_fr ? 'Suppression impossible : ' : 'Delete failed: ') + error.toString());
    } finally {
      if (mounted) setState(() => _groupActionInProgress = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Quitter le groupe ?' : 'Leave this group?'),
        content: Text(_fr
            ? 'Vous ne recevrez plus les nouveaux messages de ce groupe. Vous pourrez le rejoindre de nouveau avec le code de l’enseignant.'
            : 'You will no longer receive new messages from this group. You can join again using the teacher’s code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_fr ? 'Quitter' : 'Leave')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      setState(() => _groupActionInProgress = true);
      await _service.leaveGroup(widget.group.id);
      if (mounted) { Navigator.of(context).pop(); Navigator.of(context).pop(); }
    } catch (error) {
      _snack((_fr ? 'Impossible de quitter le groupe : ' : 'Unable to leave group: ') + error.toString());
    } finally {
      if (mounted) setState(() => _groupActionInProgress = false);
    }
  }

  Future<void> _clearGroupForMe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Effacer la conversation ?' : 'Clear this conversation?'),
        content: Text(_fr
            ? 'Les anciens messages seront masqués uniquement pour vous. Vous restez membre et verrez les nouveaux messages.'
            : 'Old messages will be hidden only for you. You remain a member and will see new messages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_fr ? 'Effacer' : 'Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.clearGroupForMe(widget.group.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load(showLoader: false);
      if (mounted) _snack(_fr ? 'Conversation effacée pour vous.' : 'Conversation cleared for you.');
    } catch (error) {
      _snack((_fr ? 'Impossible d’effacer la conversation : ' : 'Unable to clear conversation: ') + error.toString());
    }
  }


  GroupMessage? _findMessage(String? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _authorOf(GroupMessage m) =>
      m.senderId == widget.profile.id ? (_fr ? 'Vous' : 'You') : m.senderName;

  String _snippetOf(GroupMessage m) => replySnippet(
        body: m.body,
        hasAttachment: m.attachmentPath != null || m.localAttachmentPath != null,
        attachmentName: m.attachmentName,
        attachmentType: m.attachmentType,
        french: _fr,
      );

  void _startReply(GroupMessage message) {
    setState(() => _replyTo = message);
  }

  Future<void> _showMessageActions(GroupMessage message) async {
    final mine = message.senderId == widget.profile.id;
    final canDeleteForEveryone = mine || _isOwner;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (message.deletedAt == null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(_fr ? 'Répondre' : 'Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startReply(message);
                },
              ),
            if (message.deletedAt == null && message.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(_fr ? 'Copier' : 'Copy'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) _snack(_fr ? 'Message copié.' : 'Message copied.');
                },
              ),
            if (!message.isPending)
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text(_fr ? 'Sélectionner plusieurs messages' : 'Select multiple messages'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _selectedMessageIds.add(message.id));
                },
              ),
            if (!message.isPending)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(_fr ? 'Supprimer pour moi' : 'Delete for me'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(message, forEveryone: false);
                },
              ),
            if (canDeleteForEveryone && !message.isPending && message.deletedAt == null)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: Text(_fr ? 'Supprimer pour tout le monde' : 'Delete for everyone'),
                subtitle: _isOwner && !mine
                    ? Text(_fr ? 'Modération enseignant' : 'Teacher moderation')
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessage(message, forEveryone: true);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _toggleMessageSelection(String id) {
    setState(() {
      if (!_selectedMessageIds.add(id)) _selectedMessageIds.remove(id);
    });
  }

  Future<void> _showBulkDeleteOptions() async {
    final selected = _messages.where((m) => _selectedMessageIds.contains(m.id) && !m.isPending).toList();
    if (selected.isEmpty) return;
    final canDeleteEveryone = selected.every((m) => m.senderId == widget.profile.id || _isOwner);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: Text(_fr ? 'Supprimer pour moi' : 'Delete for me'),
          onTap: () { Navigator.pop(sheetContext); _deleteSelectedMessages(forEveryone: false); },
        ),
        if (canDeleteEveryone)
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
            title: Text(_fr ? 'Supprimer pour tout le monde' : 'Delete for everyone'),
            onTap: () { Navigator.pop(sheetContext); _deleteSelectedMessages(forEveryone: true); },
          ),
      ])),
    );
  }

  Future<void> _deleteSelectedMessages({required bool forEveryone}) async {
    final selected = _messages.where((m) => _selectedMessageIds.contains(m.id) && !m.isPending && (!forEveryone || m.deletedAt == null)).toList();
    if (selected.isEmpty) return;
    if (forEveryone && selected.any((m) => m.senderId != widget.profile.id && !_isOwner)) {
      _snack(_fr ? 'Vous ne pouvez supprimer pour tous que vos messages.' : 'You can only delete your own messages for everyone.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(' ' + selected.length.toString() + (_fr ? ' message(s) à supprimer ?' : ' message(s) to delete?')),
        content: Text(forEveryone
          ? (_fr ? 'Ces messages seront supprimés pour tous les membres du groupe.' : 'These messages will be deleted for all group members.')
          : (_fr ? 'Ces messages seront masqués uniquement pour vous.' : 'These messages will be hidden only for you.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_fr ? 'Supprimer' : 'Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      for (final message in selected) {
        await _service.deleteMessage(message.id, forEveryone: forEveryone);
      }
      if (mounted) setState(() => _selectedMessageIds.clear());
      await _load(showLoader: false);
      if (mounted) _snack(_fr ? 'Messages supprimés.' : 'Messages deleted.');
    } catch (error) {
      if (mounted) _snack((_fr ? 'Suppression impossible : ' : 'Delete failed: ') + error.toString());
    }
  }

  Future<void> _deleteMessage(GroupMessage message, {required bool forEveryone}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(forEveryone
            ? (_fr ? 'Supprimer pour tout le monde ?' : 'Delete for everyone?')
            : (_fr ? 'Supprimer pour vous ?' : 'Delete for you?')),
        content: Text(forEveryone
            ? (_fr
                ? 'Le message sera supprimé pour tous les membres du groupe.'
                : 'The message will be deleted for every group member.')
            : (_fr
                ? 'Le message sera masqué uniquement pour vous.'
                : 'The message will be hidden only for you.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            style: forEveryone ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMessage(message.id, forEveryone: forEveryone);
      await _load(showLoader: false);
      if (mounted) {
        _snack(forEveryone
            ? (_fr ? 'Message supprimé pour tout le monde.' : 'Message deleted for everyone.')
            : (_fr ? 'Message supprimé pour vous.' : 'Message deleted for you.'));
      }
    } catch (error) {
      if (mounted) {
        _snack((_fr ? 'Suppression impossible : ' : 'Delete failed: ') + error.toString());
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (_sending || (body.isEmpty && _attachment == null)) {
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
        groupId: widget.group.id,
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
      await _load(showLoader: false);
    } catch (error) {
      _snack('$error');
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

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showInfo() async {
    final messageCount = _messages.length;
    final voiceCount = _messages.where((message) {
      final type = (message.attachmentType ?? '').toLowerCase();
      return type.startsWith('audio/') || type.contains('voice');
    }).length;
    List<GroupMember> members = const [];
    try {
      members = await _service.listMembers(widget.group.id);
    } catch (error) {
      _snack('$error');
      return;
    }
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Center(child: UserAvatar(path: _groupAvatarPath, name: widget.group.name, radius: 38)),
                const SizedBox(height: 8),
                Center(child: Text(widget.group.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (_isOwner)
                  OutlinedButton.icon(
                    onPressed: _groupActionInProgress ? null : _changeGroupAvatar,
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: Text(_fr ? 'Changer la photo du groupe' : 'Change group photo'),
                  ),
                if (widget.group.className != null) Text(widget.group.className!),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_fr
                            ? '$messageCount messages · $voiceCount messages vocaux'
                            : '$messageCount messages · $voiceCount voice messages'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_fr ? 'Seul l’enseignant peut envoyer des messages' : 'Only the teacher can send messages'),
                  subtitle: Text(_fr
                      ? 'Bloque ou autorise les messages des élèves. Les élèves restent membres du groupe.'
                      : 'Block or allow student messages. Students remain group members.'),
                  value: _announcementsOnly,
                  onChanged: !_isOwner || _groupActionInProgress ? null : (value) async {
                    final previous = _announcementsOnly;
                    setSheetState(() => _announcementsOnly = value);
                    setState(() => _announcementsOnly = value);
                    try {
                      await _service.setAnnouncementsOnly(widget.group.id, value);
                    } catch (error) {
                      setSheetState(() => _announcementsOnly = previous);
                      if (mounted) setState(() => _announcementsOnly = previous);
                      if (mounted) _snack((_fr ? 'Modification impossible : ' : 'Could not update setting: ') + error.toString());
                    }
                  },
                ),
                if (!_isOwner && _announcementsOnly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _fr ? 'Les messages des élèves sont désactivés par l’enseignant.' : 'Student messages are disabled by the teacher.',
                      style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_isOwner && _inviteCode != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fr ? 'Code FISE unique de l’enseignant' : 'Teacher shared FISE code',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _inviteCode!,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _inviteCode!));
                                if (mounted) {
                                  _snack(_fr ? 'Code copié.' : 'Code copied.');
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: Text(_fr ? 'Copier' : 'Copy'),
                            ),

                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  '${_fr ? 'Membres' : 'Members'} (${members.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                ...members.map(
                  (member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        member.fullName.isEmpty ? '?' : member.fullName.substring(0, 1),
                      ),
                    ),
                    title: Text(member.fullName),
                    subtitle: Text(
                      member.role == 'teacher'
                          ? (_fr ? 'Enseignant' : 'Teacher')
                          : (_fr ? 'Élève' : 'Student'),
                    ),
                    trailing: _isOwner && member.userId != widget.profile.id
                        ? IconButton(
                            tooltip: _fr ? 'Retirer du groupe' : 'Remove from group',
                            icon: const Icon(Icons.person_remove_alt_1_rounded),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: Text(_fr ? 'Retirer cet élève ?' : 'Remove this student?'),
                                  content: Text(_fr
                                      ? 'Cet élève sera retiré du groupe et les autres membres en seront informés.'
                                      : 'This student will be removed from the group and other members will be notified.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext, false),
                                      child: Text(_fr ? 'Annuler' : 'Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(dialogContext, true),
                                      child: Text(_fr ? 'Retirer' : 'Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              try {
                                await _service.removeMember(widget.group.id, member.userId);
                                setSheetState(() => members = members
                                    .where((m) => m.userId != member.userId)
                                    .toList());
                              } catch (error) {
                                if (mounted) _snack('$error');
                              }
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                if (_isOwner)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _groupActionInProgress ? null : _deleteGroup,
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: Text(_fr ? 'Supprimer le groupe pour tous' : 'Delete group for everyone'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _groupActionInProgress ? null : _clearGroupForMe,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(_fr ? 'Effacer la conversation pour moi' : 'Clear conversation for me'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _groupActionInProgress ? null : _leaveGroup,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(_fr ? 'Quitter le groupe' : 'Leave group'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final matchingMessages = query.isEmpty
        ? _messages
        : _messages.where((message) => message.body.toLowerCase().contains(query) ||
            (message.attachmentName ?? '').toLowerCase().contains(query)).toList(growable: false);
    final reversed = matchingMessages.reversed.toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _fr ? 'Rechercher dans la discussion' : 'Search conversation',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : InkWell(
                onTap: _showInfo,
                child: Row(
                  children: [
                    UserAvatar(path: _groupAvatarPath, name: widget.group.name, radius: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.group.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(
                      _fr ? '${_memberCount ?? widget.group.memberCount} membres · Touchez pour les infos' : '${_memberCount ?? widget.group.memberCount} members · Tap for info',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                    ),
                      ],
                    )),
                  ],
                ),
              ),
        actions: [
          if (_selectedMessageIds.isNotEmpty) ...[
            IconButton(
              tooltip: _fr ? 'Supprimer les messages sélectionnés' : 'Delete selected messages',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _showBulkDeleteOptions,
            ),
            IconButton(
              tooltip: _fr ? 'Annuler la sélection' : 'Cancel selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selectedMessageIds.clear()),
            ),
          ],
          IconButton(
            tooltip: _searching ? (_fr ? 'Fermer la recherche' : 'Close search') : (_fr ? 'Rechercher' : 'Search'),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              if (_searching) _searchController.clear();
              _searching = !_searching;
            }),
          ),
          IconButton(
            tooltip: _fr ? 'Infos du groupe' : 'Group info',
            icon: Icon(_isOwner ? Icons.vpn_key_rounded : Icons.info_outline_rounded),
            onPressed: _showInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 42),
                              const SizedBox(height: 12),
                              Text(
                                _fr
                                    ? 'Impossible de charger les messages. Vérifiez la connexion et réessayez.'
                                    : 'Could not load messages. Check the connection and try again.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () => _load(),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(_fr ? 'Réessayer' : 'Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : reversed.isEmpty
                        ? Center(
                            child: Text(_fr ? 'Aucun message pour le moment.' : 'No messages yet.'),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: reversed.length,
                            itemBuilder: (context, index) => _bubble(reversed[index]),
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyTo != null)
                    ReplyComposerBar(
                      author: _authorOf(_replyTo!),
                      snippet: _snippetOf(_replyTo!),
                      french: _fr,
                      onCancel: () => setState(() => _replyTo = null),
                    ),
                  Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _fr ? 'Prendre une photo' : 'Take a photo',
                    onPressed: _sending || (!_isOwner && _announcementsOnly) ? null : _takePhoto,
                    icon: const Icon(Icons.camera_alt_rounded),
                  ),
                  IconButton(
                    tooltip: _fr ? 'Joindre un fichier' : 'Attach a file',
                    onPressed: _sending || (!_isOwner && _announcementsOnly) ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  VoiceRecorderButton(
                    french: _fr,
                    enabled: !_sending && (_isOwner || !_announcementsOnly),
                    onRecorded: (voice) {
                      setState(() => _attachment = voice);
                      _send();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      enabled: _isOwner || !_announcementsOnly,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _attachment != null
                            ? '${_fr ? 'Pièce jointe' : 'Attachment'} : ${_attachment!.name}'
                            : (_fr ? 'Écrire un message...' : 'Write a message...'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF166534), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: _fr ? 'Envoyer' : 'Send',
                    onPressed: _sending || (!_isOwner && _announcementsOnly) ? null : _send,
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
          ),
        ],
      ),
    );
  }

  Widget _bubble(GroupMessage message) {
    final mine = message.senderId == widget.profile.id;
    final isTeacher = message.senderRole == 'teacher';
    final quoted = _findMessage(message.replyToId);

    return GestureDetector(
      onLongPress: () {
        if (message.isPending) return;
        if (_selectedMessageIds.isNotEmpty) {
          _toggleMessageSelection(message.id);
        } else {
          _showMessageActions(message);
        }
      },
      onTap: _selectedMessageIds.isEmpty || message.isPending ? null : () => _toggleMessageSelection(message.id),
      child: SwipeToReply(
      enabled: !message.isPending,
      onReply: () => _startReply(message),
      child: Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_selectedMessageIds.contains(message.id))
          const Padding(
            padding: EdgeInsets.only(right: 6, bottom: 8),
            child: Icon(Icons.check_circle_rounded, color: Color(0xFF166534)),
          ),
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 8),
            child: UserAvatar(path: message.senderAvatarPath, name: message.senderName),
          ),
        Flexible(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Text(
                '${message.senderName}${isTeacher ? (_fr ? ' • Prof' : ' • Teacher') : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isTeacher ? const Color(0xFF166534) : Colors.blueGrey.shade700,
                ),
              ),
            if (message.deletedAt == null && message.replyToId != null)
              QuotedMessage(
                author: quoted == null ? '' : _authorOf(quoted),
                snippet: quoted == null
                    ? (_fr ? 'Message indisponible' : 'Message unavailable')
                    : _snippetOf(quoted),
              ),
            if (message.deletedAt != null)
              Text(
                _fr ? 'Ce message a été supprimé.' : 'This message was deleted.',
                style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
              )
            else if (message.body.isNotEmpty)
              Text(message.body),
            if (message.deletedAt == null && (message.attachmentPath != null || message.localAttachmentPath != null))
              MessageAttachmentView(
                name: message.attachmentName,
                type: message.attachmentType,
                localPath: message.localAttachmentPath,
                cacheScope: widget.profile.id,
                remotePath: message.attachmentPath,
                resolveUrl: _service.signedAttachmentUrl,
                galleryItems: _mediaGalleryItems,
                french: _fr,
              ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.isPending
                          ? Icons.schedule_rounded
                          : (message.readCount > 0
                              ? Icons.done_all_rounded
                              : (message.deliveredCount > 0
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded)),
                      size: 15,
                      color: message.isPending
                          ? Colors.black45
                          : (message.readCount > 0
                              ? const Color(0xFF2EAD65)
                              : (message.deliveredCount > 0
                                  ? Colors.black54
                                  : Colors.black87)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
        ),
        if (mine)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: OwnAvatar(profile: widget.profile),
          ),
      ],
    ),
      ),
    );
  }
}
