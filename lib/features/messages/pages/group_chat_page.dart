import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/group_message_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../models/message_group.dart';
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
  final AudioRecorder _recorder = AudioRecorder();
  bool _recordingVoice = false;

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
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_message_receipts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) => _load(showLoader: false, markRead: false),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'message_group_message_receipts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'group_id',
          value: widget.group.id,
        ),
        callback: (_) => _load(showLoader: false, markRead: false),
      )
      ..subscribe();
  }

  @override
  void dispose() {
    _composer.dispose();
    _channel?.unsubscribe();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _load({bool showLoader = true, bool markRead = true}) async {
    if (showLoader && mounted) {
      setState(() => _loading = true);
    }
    try {
      if (markRead) {
        await _service.markMessagesDelivered(widget.group.id);
        await _service.markMessagesRead(widget.group.id);
      }
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

  Future<void> _toggleVoiceRecording() async {
    if (_recordingVoice) {
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
          _snack('${_fr ? 'Échec de l’enregistrement' : 'Recording failed'}: $error');
        }
      }
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _snack(_fr
            ? 'Autorise le microphone pour enregistrer un message vocal.'
            : 'Allow microphone access to record a voice message.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/fise_group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => _recordingVoice = true);
    } catch (error) {
      if (mounted) {
        _snack('${_fr ? 'Impossible de démarrer le microphone' : 'Could not start the microphone'}: $error');
      }
    }
  }

  Future<void> _confirmDeleteMessage(GroupMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Supprimer le message ?' : 'Delete message?'),
        content: Text(_fr
            ? 'Ce message sera supprimé pour tous les membres du groupe.'
            : 'This message will be deleted for every group member.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteMessage(groupId: widget.group.id, message: message);
      if (mounted) {
        setState(() => _messages = _messages.where((item) => item.id != message.id).toList());
        _snack(_fr ? 'Message supprimé.' : 'Message deleted.');
      }
    } catch (error) {
      if (mounted) _snack('${_fr ? 'Suppression impossible' : 'Could not delete message'}: $error');
    }
  }

  void _openAttachment(GroupMessage message, String url) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _GroupAttachmentViewer(
        url: url,
        name: message.attachmentName ?? (_fr ? 'Pièce jointe' : 'Attachment'),
        mimeType: message.attachmentType ?? '',
        isFrench: _fr,
      ),
    ));
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
                          _fr ? 'Code d’invitation' : 'Invitation code',
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
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  final code = await _service.regenerateCode(widget.group.id);
                                  setSheetState(() => _inviteCode = code);
                                  if (mounted) {
                                    setState(() {});
                                  }
                                } catch (error) {
                                  if (mounted) {
                                    _snack('$error');
                                  }
                                }
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(_fr ? 'Nouveau code' : 'New code'),
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
                    onPressed: _sending || _recordingVoice ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  IconButton(
                    tooltip: _recordingVoice
                        ? (_fr ? 'Arrêter et joindre le vocal' : 'Stop and attach voice')
                        : (_fr ? 'Enregistrer un vocal' : 'Record a voice message'),
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
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _attachment != null
                            ? '${_fr ? 'Pièce jointe' : 'Attachment'} : ${_attachment!.name}'
                            : (_fr ? 'Écrire un message...' : 'Write a message...'),
                        border: const OutlineInputBorder(),
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

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine ? () => _confirmDeleteMessage(message) : null,
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
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
            if (message.attachmentPath != null) _attachmentView(message),
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
                    Tooltip(
                      message: message.recipientCount > 0 && message.readCount >= message.recipientCount
                          ? (_fr ? 'Lu par tous' : 'Read by everyone')
                          : message.recipientCount > 0 && message.deliveredCount >= message.recipientCount
                              ? (_fr ? 'Reçu par tous' : 'Delivered to everyone')
                              : message.deliveredCount > 0
                                  ? (_fr ? 'En cours de réception' : 'Being delivered')
                                  : (_fr ? 'Envoyé' : 'Sent'),
                      child: Icon(
                        message.recipientCount > 0 && message.readCount >= message.recipientCount
                            ? Icons.done_all_rounded
                            : message.deliveredCount > 0
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                        size: 14,
                        color: message.recipientCount > 0 && message.readCount >= message.recipientCount
                            ? const Color(0xFF166534)
                            : message.deliveredCount > 0
                                ? Colors.black54
                                : Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _attachmentView(GroupMessage message) {
    return FutureBuilder<String?>(
      future: _service.signedAttachmentUrl(message.attachmentPath),
      builder: (context, snapshot) {
        final url = snapshot.data;
        final type = message.attachmentType ?? '';

        if (url != null && type.startsWith('audio/')) {
          return _GroupRemoteAudioMessage(url: url, isFrench: _fr);
        }

        if (url != null && type.startsWith('image/')) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () => _openAttachment(message, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  width: 220,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          );
        }

        return TextButton.icon(
          onPressed: url == null ? null : () => _openAttachment(message, url),
          icon: Icon(type == 'application/pdf'
              ? Icons.picture_as_pdf_rounded
              : type.startsWith('video/')
                  ? Icons.videocam_rounded
                  : Icons.attach_file_rounded),
          label: Text(message.attachmentName ?? (_fr ? 'Fichier' : 'File')),
        );
      },
    );
  }
}


class _GroupRemoteAudioMessage extends StatefulWidget {
  final String url;
  final bool isFrench;

  const _GroupRemoteAudioMessage({required this.url, required this.isFrench});

  @override
  State<_GroupRemoteAudioMessage> createState() => _GroupRemoteAudioMessageState();
}

class _GroupRemoteAudioMessageState extends State<_GroupRemoteAudioMessage> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completed;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _completed = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
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
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: _toggle,
        icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
      ),
      Text(widget.isFrench ? 'Message vocal' : 'Voice message'),
    ],
  );
}

class _GroupAttachmentViewer extends StatefulWidget {
  final String url;
  final String name;
  final String mimeType;
  final bool isFrench;

  const _GroupAttachmentViewer({
    required this.url,
    required this.name,
    required this.mimeType,
    required this.isFrench,
  });

  @override
  State<_GroupAttachmentViewer> createState() => _GroupAttachmentViewerState();
}

class _GroupAttachmentViewerState extends State<_GroupAttachmentViewer> {
  PdfControllerPinch? _pdfController;
  VideoPlayerController? _videoController;
  bool _loading = false;
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
    }
  }

  Future<void> _loadPdf() async {
    setState(() => _loading = true);
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
          _error = widget.isFrench ? 'Impossible d’ouvrir ce PDF.' : 'Unable to open this PDF.';
        });
      }
    }
  }

  Future<void> _loadVideo() async {
    setState(() => _loading = true);
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
      await controller.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.isFrench ? 'Impossible de lire cette vidéo.' : 'Unable to play this video.';
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isImage = widget.mimeType.toLowerCase().startsWith('image/');
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
                      ? Center(child: Text(widget.isFrench ? 'PDF indisponible.' : 'PDF unavailable.'))
                      : PdfViewPinch(controller: _pdfController!))
                  : _isVideo
                      ? (_videoController == null
                          ? Center(child: Text(widget.isFrench ? 'Vidéo indisponible.' : 'Video unavailable.'))
                          : Center(
                              child: AspectRatio(
                                aspectRatio: _videoController!.value.aspectRatio > 0
                                    ? _videoController!.value.aspectRatio
                                    : 16 / 9,
                                child: VideoPlayer(_videoController!),
                              ),
                            ))
                      : isImage
                          ? Center(child: InteractiveViewer(child: Image.network(widget.url, fit: BoxFit.contain)))
                          : Center(child: Text(widget.isFrench ? 'Type de fichier non pris en charge.' : 'Unsupported file type.')));
  }
}
