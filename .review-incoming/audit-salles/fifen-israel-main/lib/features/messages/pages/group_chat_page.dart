import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/group_message_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/message_group.dart';
import '../../../core/services/message_quota_events.dart';
import '../widgets/message_media.dart';
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

  const GroupChatPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.group,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final GroupMessageService _service = GroupMessageService();
  final PhotoService _photoService = PhotoService();
  final TextEditingController _composer = TextEditingController();

  List<GroupMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  PickedAttachment? _attachment;
  RealtimeChannel? _channel;
  String? _inviteCode;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _isOwner => widget.group.ownerId == widget.profile.id;

  @override
  void initState() {
    super.initState();
    MessageQuotaEvents.denied.addListener(_onMessageDenied);
    _inviteCode = widget.group.inviteCode;
    _load();
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
        callback: (_) => _load(showLoader: false),
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
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      final messages = await _service.listMessages(widget.group.id);
      if (mounted) {
        setState(() => _messages = messages);
      }
    } catch (error) {
      if (mounted) {
        _snack('$error');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
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
      );
      _composer.clear();
      if (mounted) {
        setState(() => _attachment = null);
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
                Text(
                  widget.group.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                if (widget.group.className != null) Text(widget.group.className!),
                const SizedBox(height: 14),
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
                              try {
                                await _service.removeMember(widget.group.id, member.userId);
                                setSheetState(() => members = members
                                    .where((m) => m.userId != member.userId)
                                    .toList());
                              } catch (error) {
                                if (mounted) {
                                  _snack('$error');
                                }
                              }
                            },
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reversed = _messages.reversed.toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: InkWell(
          onTap: _showInfo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              Text(
                _fr ? 'Touchez pour les infos du groupe' : 'Tap for group info',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
        actions: [
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _fr ? 'Prendre une photo' : 'Take a photo',
                    onPressed: _sending ? null : _takePhoto,
                    icon: const Icon(Icons.camera_alt_rounded),
                  ),
                  IconButton(
                    tooltip: _fr ? 'Joindre un fichier' : 'Attach a file',
                    onPressed: _sending ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  VoiceRecorderButton(
                    french: _fr,
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

  Widget _bubble(GroupMessage message) {
    final mine = message.senderId == widget.profile.id;
    final isTeacher = message.senderRole == 'teacher';

    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
            if (message.body.isNotEmpty) Text(message.body),
            if (message.attachmentPath != null || message.localAttachmentPath != null)
              MessageAttachmentView(
                name: message.attachmentName,
                type: message.attachmentType,
                localPath: message.localAttachmentPath,
                remotePath: message.attachmentPath,
                resolveUrl: _service.signedAttachmentUrl,
                french: _fr,
              ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_formatTime(message.createdAt)}${message.isPending ? '  ◷' : ''}',
                style: const TextStyle(fontSize: 10, color: Colors.black45),
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
    );
  }
}
