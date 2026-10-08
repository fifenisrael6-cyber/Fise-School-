import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/widgets/rich_lesson_text.dart';
import '../../../models/user_profile.dart';

class AiPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  /// Renseigné quand l'élève ouvre l'IA depuis une leçon : classe, matière,
  /// chapitre, titre et extrait de la leçon.
  final AiLessonContext? lessonContext;

  /// Question envoyée automatiquement à l'ouverture (ex. « Explique cette partie »).
  final String? initialPrompt;

  const AiPage({
    super.key,
    required this.locale,
    required this.profile,
    this.lessonContext,
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
  final ConnectivityService _connectivity = ConnectivityService();
  final FocusNode _inputFocus = FocusNode();

  final List<_AiMessage> _messages = [];
  String? _lastText;
  PickedAttachment? _lastAttachment;
  PickedAttachment? _attachment;
  PickedAttachment? _conversationAttachment;
  bool _sending = false;

  bool get _isFrench => widget.locale.languageCode != 'en';

  bool get _hasLessonContext =>
      widget.lessonContext != null && !widget.lessonContext!.isEmpty;

  @override
  void initState() {
    super.initState();
    final lessonTitle = widget.lessonContext?.lessonTitle?.trim() ?? '';
    _messages.add(_AiMessage(
      isIntro: true,
      text: _hasLessonContext && lessonTitle.isNotEmpty
          ? (_isFrench
              ? 'Bonjour ${widget.profile.firstName} 👋\n\nJe t’aide sur la leçon **$lessonTitle**. Choisis une aide ci-dessous ou pose ta question.'
              : 'Hello ${widget.profile.firstName} 👋\n\nI will help you with the lesson **$lessonTitle**. Pick a quick help below or ask your question.')
          : (_isFrench
              ? 'Bonjour ${widget.profile.firstName} 👋\n\nJe suis l’assistant IA de Fise School. Pose-moi une question sur tes cours, envoie un document, une photo ou prends une photo directement avec ton téléphone.'
              : 'Hello ${widget.profile.firstName} 👋\n\nI am the Fise School AI assistant. Ask about your lessons, attach a document or photo, or take a photo directly with your phone.'),
      fromUser: false,
    ));

    final initial = widget.initialPrompt?.trim() ?? '';
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendText(initial);
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    _sendText(_messageController.text.trim());
  }

  Future<void> _sendText(String rawText) async {
    final text = rawText.trim();
    final selectedAttachment = _attachment;
    final contextAttachment = selectedAttachment ?? _conversationAttachment;
    if ((text.isEmpty && contextAttachment == null) || _sending) {
      return;
    }

    _messageController.clear();
    _lastText = text;
    _lastAttachment = selectedAttachment;

    // Les messages d'erreur et le message d'accueil ne sont pas envoyés à l'IA.
    final history = _messages
        .where((message) =>
            !message.isError &&
            !message.isIntro &&
            (message.text.trim().isNotEmpty || message.attachmentName != null))
        .takeLast(20)
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
      // Évite un appel IA inutile (et une longue attente) sans Internet.
      if (!await _connectivity.isOnline()) {
        throw AiServiceException(
          _isFrench
              ? 'Pas de connexion Internet. L’assistant IA a besoin d’Internet : reconnecte-toi puis réessaie.'
              : 'No Internet connection. The AI assistant needs Internet: reconnect and try again.',
        );
      }

      final answer = await _geminiService.ask(
        message: text,
        profile: widget.profile,
        history: history,
        attachmentBytes: contextAttachment?.bytes,
        attachmentMimeType: contextAttachment?.mimeType,
        attachmentName: contextAttachment?.name,
        context: widget.lessonContext,
      );
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
      final retryable = error is! AiServiceException || error.retryable;
      setState(() {
        _messages.add(_AiMessage(
          text: _friendlyError(error),
          fromUser: false,
          isError: true,
          canRetry: retryable,
        ));
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  /// Renvoie la dernière question après une erreur, sans la dupliquer.
  void _retry() {
    final text = _lastText;
    if (_sending || (text == null && _lastAttachment == null)) {
      return;
    }
    setState(() {
      if (_messages.isNotEmpty && _messages.last.isError) {
        _messages.removeLast();
      }
      if (_messages.isNotEmpty && _messages.last.fromUser) {
        _messages.removeLast();
      }
      _attachment = _lastAttachment;
    });
    _sendText(text ?? '');
  }

  /// Aide rapide : envoie tout de suite si une leçon donne le contexte,
  /// sinon prépare le début de la question pour que l'élève la complète.
  void _useQuickAction(_QuickAction action) {
    if (_sending) {
      return;
    }
    if (_hasLessonContext || !action.needsTopic) {
      _sendText(action.prompt);
      return;
    }
    _messageController.text = action.prompt;
    _messageController.selection =
        TextSelection.collapsed(offset: _messageController.text.length);
    _inputFocus.requestFocus();
  }

  List<_QuickAction> get _quickActions {
    if (_hasLessonContext) {
      return _isFrench
          ? const [
              _QuickAction('Explique cette partie', 'Explique-moi cette partie de la leçon, étape par étape.'),
              _QuickAction('Je n’ai pas compris', 'Je n’ai pas compris cette leçon. Explique-la plus simplement, avec un exemple.'),
              _QuickAction('Donne un exemple', 'Donne-moi un exemple résolu sur cette leçon.'),
              _QuickAction('Explique la formule', 'Explique les formules de cette leçon : chaque symbole et quand les utiliser.'),
              _QuickAction('Exercice similaire', 'Donne-moi un exercice similaire à cette leçon pour m’entraîner, sans la correction tout de suite.'),
              _QuickAction('QCM sur la leçon', 'Fais-moi un QCM de 5 questions sur cette leçon, avec la correction à la fin.'),
            ]
          : const [
              _QuickAction('Explain this part', 'Explain this part of the lesson to me, step by step.'),
              _QuickAction('I did not understand', 'I did not understand this lesson. Explain it more simply, with an example.'),
              _QuickAction('Give an example', 'Give me a worked example on this lesson.'),
              _QuickAction('Explain the formula', 'Explain the formulas of this lesson: each symbol and when to use them.'),
              _QuickAction('Similar exercise', 'Give me a similar exercise on this lesson to practise, without the answer yet.'),
              _QuickAction('Lesson quiz', 'Make me a 5-question multiple choice quiz on this lesson, with answers at the end.'),
            ];
    }
    return _isFrench
        ? const [
            _QuickAction('Explique-moi…', 'Explique-moi ', needsTopic: true),
            _QuickAction('Aide pour un exercice', 'Aide-moi à résoudre cet exercice étape par étape : ', needsTopic: true),
            _QuickAction('Fais-moi un QCM sur…', 'Fais-moi un QCM de 5 questions sur ', needsTopic: true),
            _QuickAction('Donne-moi un exemple de…', 'Donne-moi un exemple résolu de ', needsTopic: true),
          ]
        : const [
            _QuickAction('Explain…', 'Explain ', needsTopic: true),
            _QuickAction('Help with an exercise', 'Help me solve this exercise step by step: ', needsTopic: true),
            _QuickAction('Quiz me on…', 'Make me a 5-question multiple choice quiz on ', needsTopic: true),
            _QuickAction('Example of…', 'Give me a worked example of ', needsTopic: true),
          ];
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

  void _clearConversation() {
    setState(() {
      _messages
        ..clear()
        ..add(_AiMessage(
          text: _isFrench ? 'Conversation effacée. Comment puis-je t’aider ?' : 'Conversation cleared. How can I help?',
          fromUser: false,
          isIntro: true,
        ));
      _conversationAttachment = null;
      _lastText = null;
      _lastAttachment = null;
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
            _buildQuickActions(),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBanner() {
    final context = widget.lessonContext;
    final parts = <String>[
      if (_hasLessonContext)
        for (final value in [
          context?.className,
          context?.series,
          context?.subject,
          context?.lessonTitle,
        ])
          if (value != null && value.trim().isNotEmpty) value.trim(),
    ];

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
            parts.isNotEmpty
                ? parts.join(' • ')
                : (_isFrench
                    ? 'Tu peux écrire, joindre un document, choisir une photo ou utiliser la caméra.'
                    : 'You can type, attach a document, choose a photo, or use the camera.'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          )),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = _quickActions;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final action = actions[index];
          return ActionChip(
            label: Text(action.label),
            onPressed: _sending ? null : () => _useQuickAction(action),
          );
        },
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
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = (screenWidth * (user ? 0.84 : 0.95)).clamp(0.0, 720.0).toDouble();
    final Color background = user
        ? const Color(0xFF166534)
        : (message.isError ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9));

    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: message.isError
              ? Border.all(color: const Color(0xFFFECACA))
              : null,
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
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.45,
                    fontSize: 15.5,
                  ),
                )
              else if (message.isError)
                Text(
                  message.text,
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    height: 1.45,
                    fontSize: 15,
                  ),
                )
              else
                RichLessonText(
                  text: message.text,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    height: 1.5,
                    fontSize: 15.5,
                  ),
                ),
            if (message.isError && message.canRetry)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _sending ? null : _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_isFrench ? 'Réessayer' : 'Try again'),
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
                  onPressed: _sending ? null : _showAttachmentMenu,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: _isFrench
                          ? 'Écris ta question ici…'
                          : 'Type your question here…',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFF166534), width: 1.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: _isFrench ? 'Envoyer' : 'Send',
                  onPressed: _sending ? null : _sendMessage,
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
  final bool isError;
  final bool isIntro;
  final bool canRetry;

  const _AiMessage({
    required this.text,
    required this.fromUser,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentBytes,
    this.isError = false,
    this.isIntro = false,
    this.canRetry = false,
  });
}

class _QuickAction {
  final String label;
  final String prompt;
  final bool needsTopic;

  const _QuickAction(this.label, this.prompt, {this.needsTopic = false});
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
