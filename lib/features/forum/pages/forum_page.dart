import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/forum_access_service.dart';
import '../../../models/forum_with_code.dart';
import '../../../models/user_profile.dart';

class ForumPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const ForumPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final ForumAccessService _service = ForumAccessService();
  final TextEditingController _codeController = TextEditingController();

  bool _loading = false;
  String? _error;
  bool get _isTeacher => widget.profile.role == 'teacher';
  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createForum() async {
    final classIdController = TextEditingController();
    final classNameController = TextEditingController();
    final filiereController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_isFrench ? 'Créer un forum de classe' : 'Create class forum'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: classIdController,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'ID de la salle' : 'Class ID',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: classNameController,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'Nom de la salle' : 'Class name',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: filiereController,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'Filière' : 'Specialty',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final classId = classIdController.text.trim();
                final className = classNameController.text.trim();

                if (classId.isEmpty || className.isEmpty) {
                  return;
                }

                try {
                  final forum = await _service.createForum(
                    teacherId: widget.profile.id,
                    classId: classId,
                    className: className,
                    filiere: filiereController.text.trim(),
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.pop(dialogContext, true);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isFrench
                              ? 'Forum créé. Code: ${forum.accessCode}'
                              : 'Forum created. Code: ${forum.accessCode}',
                        ),
                      ),
                    );
                  }
                } catch (_) {
                  if (!dialogContext.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isFrench
                            ? 'Impossible de créer le forum.'
                            : 'Unable to create the forum.',
                      ),
                    ),
                  );
                }
              },
              child: Text(_isFrench ? 'Créer' : 'Create'),
            ),
          ],
        );
      },
    );

    if (created == true) {
      setState(() {});
    }
  }

  Future<void> _joinForumByCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final forum = await _service.joinForumByCode(
        studentId: widget.profile.id,
        code: code,
      );

      if (!mounted) {
        return;
      }

      if (forum == null) {
        setState(() {
          _loading = false;
          _error = _isFrench ? 'Code introuvable.' : 'Code not found.';
        });
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ForumChatPage(
            locale: widget.locale,
            profile: widget.profile,
            forum: forum,
          ),
        ),
      );

      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible de rejoindre le forum.'
                : 'Unable to join the forum.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isFrench ? 'Forum de classe' : 'Class forum'),
      ),
      floatingActionButton: _isTeacher
          ? FloatingActionButton.extended(
              onPressed: _createForum,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text(_isFrench ? 'Nouveau forum' : 'New forum'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isTeacher
              ? _TeacherForumView(
                  locale: widget.locale,
                  profile: widget.profile,
                  service: _service,
                )
              : _StudentForumView(
                  locale: widget.locale,
                  profile: widget.profile,
                  service: _service,
                  codeController: _codeController,
                  onJoinForum: _joinForumByCode,
                ),
    );
  }
}

class _TeacherForumView extends StatelessWidget {
  final ForumAccessService service;
  final UserProfile profile;
  final Locale locale;

  const _TeacherForumView({
    required this.service,
    required this.profile,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClassForum>>(
      future: service.listMyClassForumsForTeacher(profile.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }

        final forums = snapshot.data ?? const <ClassForum>[];
        if (forums.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    locale.languageCode == 'fr'
                        ? 'Aucun forum créé pour le moment.'
                        : 'No forum created yet.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: forums.length,
          itemBuilder: (context, index) {
            final forum = forums[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.forum_rounded),
                ),
                title: Text(forum.className),
                subtitle: Text(
                  '${forum.filiere ?? 'Filière'} • Code: ${forum.accessCode}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForumChatPage(
                        locale: locale,
                        profile: profile,
                        forum: forum,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _StudentForumView extends StatelessWidget {
  final ForumAccessService service;
  final UserProfile profile;
  final Locale locale;
  final TextEditingController codeController;
  final VoidCallback onJoinForum;

  const _StudentForumView({
    required this.service,
    required this.profile,
    required this.locale,
    required this.codeController,
    required this.onJoinForum,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: codeController,
            decoration: InputDecoration(
              labelText: locale.languageCode == 'fr' ? 'Code du forum' : 'Forum code',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onJoinForum,
            icon: const Icon(Icons.check_circle_rounded),
            label: Text(locale.languageCode == 'fr' ? 'Rejoindre' : 'Join'),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<ClassForum>>(
              future: service.listMyClassForumsForStudent(profile.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }

                final forums = snapshot.data ?? const <ClassForum>[];
                if (forums.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.forum_outlined, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          locale.languageCode == 'fr'
                              ? 'Aucun forum disponible. Entrez le code pour rejoindre.'
                              : 'No forum available. Enter the code to join.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: forums.length,
                  itemBuilder: (context, index) {
                    final forum = forums[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.forum_rounded),
                        ),
                        title: Text(forum.className),
                        subtitle: Text(
                          '${forum.filiere ?? 'Filière'} • Code: ${forum.accessCode}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ForumChatPage(
                                locale: locale,
                                profile: profile,
                                forum: forum,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ForumChatPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final ClassForum forum;

  const ForumChatPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.forum,
  });

  @override
  State<ForumChatPage> createState() => _ForumChatPageState();
}

class _ForumChatPageState extends State<ForumChatPage> {
  final ForumAccessService _service = ForumAccessService();
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ClassForumMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  PlatformFile? _attachment;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
    });

    try {
      final messages = await _service.listForumMessages(widget.forum.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench ? 'Impossible de charger les messages.' : 'Unable to load messages.',
          ),
        ),
      );
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'mp4',
        'mov',
        'webm',
        'mp3',
        'wav',
        'm4a',
      ],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    if (file.size > 50 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Le fichier ne doit pas dépasser 50 Mo.'
                : 'The file must not exceed 50 MB.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _attachment = file;
    });
  }

  Future<void> _sendMessage() async {
    final body = _composer.text.trim();
    if (body.isEmpty && _attachment == null) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _service.sendForumMessage(
        forumId: widget.forum.id,
        authorId: widget.profile.id,
        authorName: '${widget.profile.firstName} ${widget.profile.lastName}'.trim(),
        authorRole: widget.profile.role,
        body: body,
        attachment: _attachment,
      );

      _composer.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _attachment = null;
      });
      await _loadMessages();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible d’envoyer le message.'
                : 'Unable to send the message.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forum.className),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMine = message.authorId == widget.profile.id;

                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: isMine ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.authorName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              if (message.body.isNotEmpty) Text(message.body),
                              if (message.hasAttachment)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.attach_file_rounded),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message.attachmentName ?? 'Fichier',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 10),
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
              children: [
                IconButton(
                  onPressed: _pickAttachment,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _isFrench ? 'Écrire un message...' : 'Write a message...',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _sendMessage,
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
