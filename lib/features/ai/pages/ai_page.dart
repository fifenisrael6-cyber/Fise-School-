import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/gemini_service.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/offline/connectivity_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/quota_service.dart';
import '../../../core/widgets/rich_lesson_text.dart';
import '../../premium/premium_gate.dart';
import '../../../models/user_profile.dart';

class AiPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final String? initialPrompt;

  const AiPage({
    super.key,
    required this.locale,
    required this.profile,
    this.initialPrompt,
  });

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GeminiService _geminiService = GeminiService();
  final PhotoService _photoService = PhotoService();
  final AppDatabase _offlineDatabase = AppDatabase();
  static const String _localConversationId = 'current';

  final List<_AiMessage> _messages = [];
  PickedAttachment? _attachment;
  PickedAttachment? _conversationAttachment;
  bool _sending = false;
  bool _quotaReached = false;
  String? _quotaReachedDate;
  Timer? _quotaResetTimer;

  bool get _isFrench => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    _messageController.text = widget.initialPrompt ?? '';
    _showWelcomeMessage();
    unawaited(_restoreCachedConversation());
  }

  void _showWelcomeMessage() {
    if (_messages.isNotEmpty) return;
    _messages.add(_AiMessage(
      text: _isFrench
          ? 'Bonjour ${widget.profile.firstName} 👋\n\nJe suis l’assistant IA de Fise School. Pose-moi une question sur tes cours, envoie un document, une photo ou prends une photo directement avec ton téléphone.'
          : 'Hello ${widget.profile.firstName} 👋\n\nI am the Fise School AI assistant. Ask about your lessons, attach a document or photo, or take a photo directly with your phone.',
      fromUser: false,
    ));
  }

  Future<void> _restoreCachedConversation() async {
    try {
      final rows = await _offlineDatabase.getAiConversationMessages(
        widget.profile.id,
        _localConversationId,
      );
      if (!mounted || rows.isEmpty) return;
      final restored = rows.map((row) => _AiMessage(
        text: row.read<String>('content'),
        fromUser: row.read<String>('role') == 'user',
      )).toList(growable: false);
      setState(() {
        _messages
          ..clear()
          ..addAll(restored);
      });
      _scrollToBottom();
    } catch (error) {
      debugPrint('Could not restore local AI conversation: $error');
    }
  }

  Future<void> _saveCachedAiMessage(String role, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      final now = DateTime.now();
      await _offlineDatabase.saveAiConversationMessage(
        messageId: '${widget.profile.id}:${now.microsecondsSinceEpoch}:$role',
        userId: widget.profile.id,
        conversationId: _localConversationId,
        role: role,
        content: trimmed,
        createdAt: now,
      );
    } catch (error) {
      debugPrint('Could not save local AI conversation: $error');
    }
  }

  @override
  void dispose() {
    _quotaResetTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final today = _todayKey();
    if (_quotaReached && _quotaReachedDate != today) {
      setState(() {
        _quotaReached = false;
        _quotaReachedDate = null;
      });
      _quotaResetTimer?.cancel();
    }
    if (_quotaReached) return;

    final text = _messageController.text.trim();
    final selectedAttachment = _attachment;
    final contextAttachment = selectedAttachment ?? _conversationAttachment;
    if ((text.isEmpty && contextAttachment == null) || _sending) {
      return;
    }

    // Save the student's question immediately when there is no network instead
    // of leaving the composer spinning while the remote AI endpoint times out.
    final online = await ConnectivityService().isOnline();
    if (!online) {
      final savedUserText = text.isNotEmpty
          ? text
          : '[Pièce jointe : ${contextAttachment!.name}]';
      _messageController.clear();
      setState(() {
        _messages.add(_AiMessage(
          text: text,
          fromUser: true,
          attachmentName: selectedAttachment?.name,
          attachmentMimeType: selectedAttachment?.mimeType,
          attachmentBytes: selectedAttachment?.bytes,
        ));
        _attachment = null;
        _messages.add(_AiMessage(
          text: _isFrench
              ? 'Question enregistrée sur cet appareil. La réponse de l’IA nécessite une connexion Internet. Si tu as joint une photo ou un document, il faudra le joindre à nouveau après reconnexion.'
              : 'Question saved on this device. The AI needs an internet connection to answer. If you attached a photo or document, attach it again after reconnecting.',
          fromUser: false,
        ));
      });
      await _saveCachedAiMessage('user', savedUserText);
      _scrollToBottom();
      return;
    }

    if (contextAttachment != null) {
      final okToSend = await PremiumGate.canSend(
        context,
        profile: widget.profile,
        feature: QuotaFeature.aiText,
        hasAttachment: true,
      );
      if (!okToSend || !mounted) return;
    } else {
      final okToSend = await PremiumGate.canSend(
        context,
        profile: widget.profile,
        feature: QuotaFeature.aiText,
      );
      if (!okToSend || !mounted) return;
    }

    _messageController.clear();
    final history = _messages
        .where((message) => message.text.trim().isNotEmpty || message.attachmentName != null)
        .takeLast(6)
        .map((message) => AiHistoryMessage(
              role: message.fromUser ? 'user' : 'model',
              text: message.attachmentName == null
                  ? message.text
                  : '${message.text.isEmpty ? '' : '${message.text}\n'}[Fichier joint : ${message.attachmentName}]',
            ))
        .toList();

    setState(() {
      _messages.add(_AiMessage(
        text: text,
        fromUser: true,
        attachmentName: selectedAttachment?.name,
        attachmentMimeType: selectedAttachment?.mimeType,
        attachmentBytes: selectedAttachment?.bytes,
      ));
      _attachment = null;
      if (selectedAttachment != null) {
        _conversationAttachment = selectedAttachment;
      }
      _sending = true;
    });
    _scrollToBottom();

    try {
      final answer = await _geminiService.ask(
        message: text,
        profile: widget.profile,
        history: history,
        attachmentBytes: contextAttachment?.bytes,
        attachmentMimeType: contextAttachment?.mimeType,
        attachmentName: contextAttachment?.name,
      );
      final savedUserText = text.isNotEmpty
          ? text
          : (selectedAttachment == null ? '' : '[Fichier joint : ${selectedAttachment.name}]');
      await _saveCachedAiMessage('user', savedUserText);
      await _saveCachedAiMessage('model', answer);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_AiMessage(text: answer, fromUser: false));
        _sending = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is AiDailyLimitReachedException || error is AiPremiumRequiredException) {
        // Quota gratuit épuisé (ou entrée multimédia réservée) : on ouvre la fenêtre Premium
        // au lieu d'un simple message, puis on reprend la demande si le paiement est confirmé.
        setState(() {
          if (_messages.isNotEmpty && _messages.last.fromUser) _messages.removeLast();
          _sending = false;
        });
        final resumed = await PremiumGate.openForServerDenial(
          context,
          profile: widget.profile,
          feature: QuotaFeature.aiText,
          premiumOnly: error is AiPremiumRequiredException,
        );
        if (resumed && mounted) {
          _messageController.text = text;
          _attachment = selectedAttachment;
          await _sendMessage();
        }
        return;
      }
      final quotaException = error is AiDailyLimitReachedException ? error : null;
      final savedUserText = text.isNotEmpty
          ? text
          : (selectedAttachment == null ? '' : '[Fichier joint : ${selectedAttachment.name}]');
      await _saveCachedAiMessage('user', savedUserText);
      setState(() {
        _messages.add(_AiMessage(
          text: quotaException?.message ?? _friendlyError(error),
          fromUser: false,
        ));
        _sending = false;
        if (quotaException != null) {
          _quotaReached = true;
          _quotaReachedDate = _todayKey();
          _quotaResetTimer?.cancel();
          final now = DateTime.now();
          final nextDay = DateTime(now.year, now.month, now.day + 1);
          _quotaResetTimer = Timer(nextDay.difference(now), () {
            if (!mounted) return;
            setState(() {
              _quotaReached = false;
              _quotaReachedDate = null;
            });
          });
        }
      });
    }
    _scrollToBottom();
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.contains('too large') || raw.contains('Taille')) {
      return raw;
    }
    if (raw.length <= 220) {
      return raw;
    }
    return _isFrench
        ? 'Impossible de traiter cette demande. Vérifie ta connexion ou essaie un fichier plus petit.'
        : 'I could not process this request. Check your connection or try a smaller file.';
  }

  Future<void> _showAttachmentMenu() async {
    if (_sending) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.camera_alt_rounded)),
                title: Text(_isFrench ? 'Prendre une photo' : 'Take a photo'),
                subtitle: Text(_isFrench ? 'Utiliser la caméra maintenant' : 'Use the camera now'),
                onTap: () async { Navigator.pop(context); await _takePhoto(); },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.photo_library_rounded)),
                title: Text(_isFrench ? 'Photos et images' : 'Photos and images'),
                onTap: () async { Navigator.pop(context); await _pickImage(); },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.attach_file_rounded)),
                title: Text(_isFrench ? 'Document ou fichier' : 'Document or file'),
                subtitle: Text(_isFrench ? 'PDF et fichiers texte' : 'PDF and text files'),
                onTap: () async { Navigator.pop(context); await _pickDocument(); },
              ),
            ],
          ),
        ),
      ),
    );
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
    _setAttachment(PickedAttachment(
      bytes: bytes,
      name: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: file.mimeType ?? 'image/jpeg',
    ));
  }

  Future<void> _pickImage() async {
    final file = await _photoService.pickFromGallery();
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    _setAttachment(PickedAttachment(
      bytes: bytes,
      name: file.name,
      mimeType: file.mimeType ?? 'image/jpeg',
    ));
  }

  Future<void> _pickDocument() async {
    final file = await _photoService.pickFile(
      allowedExtensions: const [
        'pdf', 'txt', 'md', 'csv',
      ],
    );
    if (!mounted || file == null) {
      return;
    }
    _setAttachment(file);
  }

  void _setAttachment(PickedAttachment attachment) {
    const maxBytes = 8 * 1024 * 1024;
    if (attachment.bytes.length > maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench
            ? 'Le fichier est trop volumineux. Limite : 8 Mo.'
            : 'The file is too large. Limit: 8 MB.'),
      ));
      return;
    }
    setState(() => _attachment = attachment);
  }

  void _removeAttachment() => setState(() => _attachment = null);

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _clearConversation() {
    unawaited(_offlineDatabase.clearAiConversation(
      widget.profile.id,
      _localConversationId,
    ));
    setState(() {
      _messages
        ..clear()
        ..add(_AiMessage(
          text: _quotaReached
              ? AiDailyLimitReachedException.messageForLanguage(_isFrench ? 'fr' : 'en').message
              : (_isFrench ? 'Conversation effacée.' : 'Conversation cleared.'),
          fromUser: false,
        ));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFrench ? 'Assistant IA Fise School' : 'Fise School AI'),
        actions: [
          IconButton(
            tooltip: _isFrench ? 'Nouvelle conversation' : 'New conversation',
            onPressed: _sending ? null : _clearConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildContextBanner(),
            Expanded(child: _buildConversation()),
            if (_sending) const LinearProgressIndicator(minHeight: 2),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5EC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF166534)),
          const SizedBox(width: 10),
          Expanded(child: Text(
            _isFrench
                ? 'Tu peux écrire, joindre un document, choisir une photo ou utiliser la caméra.'
                : 'You can type, attach a document, choose a photo, or use the camera.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          )),
        ],
      ),
    );
  }

  Widget _buildConversation() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      itemCount: _messages.length,
      itemBuilder: (_, index) => _buildMessage(_messages[index]),
    );
  }

  Widget _buildMessage(_AiMessage message) {
    final user = message.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user ? const Color(0xFF166534) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachmentName != null) ...[
              _attachmentPreview(message, compact: true),
              if (message.text.isNotEmpty) const SizedBox(height: 8),
            ],
            if (message.text.isNotEmpty)
              if (user)
                SelectableText(
                  message.text,
                  style: const TextStyle(color: Colors.white, height: 1.45),
                )
              else
                RichLessonText(
                  text: message.text,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentPreview(_AiMessage message, {bool compact = false}) {
    final image = message.attachmentMimeType?.startsWith('image/') == true && message.attachmentBytes != null;
    if (image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          message.attachmentBytes!,
          width: compact ? 220 : double.infinity,
          height: compact ? 150 : 190,
          fit: BoxFit.cover,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_fileIcon(message.attachmentMimeType), color: message.fromUser ? Colors.white : const Color(0xFF166534)),
        const SizedBox(width: 8),
        Flexible(child: Text(
          message.attachmentName ?? 'File',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: message.fromUser ? Colors.white : Colors.black87, fontWeight: FontWeight.w700),
        )),
      ],
    );
  }

  IconData _fileIcon(String? mime) {
    if (mime == 'application/pdf') {
      return Icons.picture_as_pdf_rounded;
    }
    if (mime?.startsWith('audio/') == true) {
      return Icons.audio_file_rounded;
    }
    if (mime?.startsWith('video/') == true) {
      return Icons.video_file_rounded;
    }
    return Icons.description_rounded;
  }

  Widget _buildComposer() {
    return Material(
      elevation: 8,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachment != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(_fileIcon(_attachment!.mimeType), color: const Color(0xFF166534)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_attachment!.name, overflow: TextOverflow.ellipsis)),
                    IconButton(onPressed: _removeAttachment, icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: _isFrench ? 'Joindre' : 'Attach',
                  onPressed: (_sending || _quotaReached) ? null : _showAttachmentMenu,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 5,
                    readOnly: _quotaReached,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _quotaReached
                          ? (_isFrench ? 'Limite quotidienne atteinte' : 'Daily limit reached')
                          : 'Message...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) { if (!_quotaReached) _sendMessage(); },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: (_sending || _quotaReached) ? null : _sendMessage,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiMessage {
  final String text;
  final bool fromUser;
  final String? attachmentName;
  final String? attachmentMimeType;
  final Uint8List? attachmentBytes;

  const _AiMessage({
    required this.text,
    required this.fromUser,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentBytes,
  });
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    if (count <= 0) {
      return <T>[];
    }
    final list = toList(growable: false);
    return list.length <= count ? list : list.sublist(list.length - count);
  }
}
