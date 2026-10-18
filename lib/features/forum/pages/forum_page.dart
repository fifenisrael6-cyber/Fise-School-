import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/forum_service.dart';
import '../../../models/forum.dart';
import '../../../models/user_profile.dart';

class ForumPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const ForumPage({super.key, required this.locale, required this.profile});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final ForumService _service = ForumService();

  bool _loading = true;
  String? _error;
  List<ForumClass> _classes = const [];

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final classes = await _service.listClasses(widget.profile);

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger vos classes.'
            : 'Unable to load your classes.';
      });
    }
  }

  bool get _isTeacher => widget.profile.role == 'teacher';

  /// L'enseignant choisit les salles qu'il suit (et dans lesquelles il peut créer des forums).
  Future<void> _chooseMyClasses() async {
    List<TeacherClassChoice> choices;
    try {
      choices = await _service.listTeacherClassChoices();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench ? 'Impossible de charger les salles.' : 'Unable to load classrooms.'),
      ));
      return;
    }
    if (!mounted) {
      return;
    }

    final selected = <String>{for (final c in choices) if (c.isSelected) c.id};

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isFrench ? 'Mes salles' : 'My classrooms',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_isFrench
                    ? 'Cochez les salles que vous suivez : vous pourrez y créer des forums.'
                    : 'Tick the classrooms you follow: you will be able to create forums there.'),
                const SizedBox(height: 8),
                if (choices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_isFrench ? 'Aucune salle disponible pour votre profil.' : 'No classroom available for your profile.'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: choices
                          .map((room) => CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                value: selected.contains(room.id),
                                title: Text(room.displayName),
                                onChanged: (value) => setSheetState(() {
                                  if (value == true) {
                                    selected.add(room.id);
                                  } else {
                                    selected.remove(room.id);
                                  }
                                }),
                              ))
                          .toList(growable: false),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(_isFrench ? 'Enregistrer' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) {
      return;
    }
    try {
      await _service.setTeacherClasses(selected.toList(growable: false));
      await _loadClasses();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isFrench ? 'Enregistrement impossible.' : 'Unable to save.'),
      ));
    }
  }

  Future<void> _createTeacherForum() async {
    ForumClass? selected = _classes.length == 1 ? _classes.first : null;
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_isFrench ? 'Créer un forum' : 'Create a forum'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<ForumClass>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: _isFrench ? 'Salle de classe' : 'Classroom',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.school_outlined),
                ),
                items: _classes.map((room) => DropdownMenuItem(value: room, child: Text(room.displayName))).toList(),
                onChanged: (value) => setDialogState(() => selected = value),
              ),
              const SizedBox(height: 12),
              TextField(controller: titleController, onChanged: (_) => setDialogState(() {}), decoration: InputDecoration(labelText: _isFrench ? 'Nom du forum' : 'Forum name', border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: descriptionController, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: _isFrench ? 'Description (facultative)' : 'Description (optional)', border: const OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_isFrench ? 'Annuler' : 'Cancel')),
            FilledButton(
              onPressed: selected == null || titleController.text.trim().isEmpty ? null : () async {
                try {
                  await _service.createTopic(classId: selected!.id, authorId: widget.profile.id, authorName: _authorName(widget.profile), title: titleController.text.trim(), description: descriptionController.text.trim());
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (_) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(_isFrench ? 'Impossible de créer le forum.' : 'Unable to create the forum.')));
                  }
                }
              },
              child: Text(_isFrench ? 'Créer' : 'Create'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    if (result == true) {
      await _loadClasses();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Forum' : 'Forum',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isTeacher)
            IconButton(
              tooltip: _isFrench ? 'Mes salles' : 'My classrooms',
              icon: const Icon(Icons.school_outlined),
              onPressed: _chooseMyClasses,
            ),
        ],
      ),
      floatingActionButton: _isTeacher && _classes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _createTeacherForum,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text(_isFrench ? 'Nouveau forum' : 'New forum'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadClasses,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(
                message: _error!,
                retryLabel: _isFrench ? 'Réessayer' : 'Try again',
                onRetry: _loadClasses,
              )
            : _classes.isEmpty
            ? (_isTeacher
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 48),
                      const Icon(Icons.school_outlined, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        _isFrench
                            ? 'Choisissez les salles que vous suivez pour pouvoir créer un forum.'
                            : 'Choose the classrooms you follow to be able to create a forum.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.icon(
                          onPressed: _chooseMyClasses,
                          icon: const Icon(Icons.checklist_rounded),
                          label: Text(_isFrench ? 'Choisir mes salles' : 'Choose my classrooms'),
                        ),
                      ),
                    ],
                  )
                : _EmptyView(
                    icon: Icons.forum_outlined,
                    message: _isFrench
                        ? 'Aucune classe disponible.'
                        : 'No class available.',
                  ))
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _classes.length,
                itemBuilder: (context, index) {
                  final schoolClass = _classes[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Icon(
                          Icons.forum_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        schoolClass.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(schoolClass.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ForumTopicsPage(
                              locale: widget.locale,
                              profile: widget.profile,
                              forumClass: schoolClass,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _authorName(UserProfile profile) {
  final name = '${profile.firstName} ${profile.lastName}'.trim();
  return name.isEmpty ? 'Utilisateur' : name;
}

class ForumTopicsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final ForumClass forumClass;

  const ForumTopicsPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.forumClass,
  });

  @override
  State<ForumTopicsPage> createState() => _ForumTopicsPageState();
}

class _ForumTopicsPageState extends State<ForumTopicsPage> {
  final ForumService _service = ForumService();

  bool _loading = true;
  String? _error;
  List<ForumTopic> _topics = const [];

  bool get _isFrench => widget.locale.languageCode == 'fr';

  bool get _isTeacher => widget.profile.role == 'teacher';

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final topics = await _service.listTopics(widget.forumClass.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger les discussions.'
            : 'Unable to load discussions.';
      });
    }
  }

  Future<void> _createTopic() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_isFrench ? 'Nouvelle discussion' : 'New discussion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'Titre' : 'Title',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'Description' : 'Description',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();

                if (title.isEmpty) {
                  return;
                }

                try {
                  await _service.createTopic(
                    classId: widget.forumClass.id,
                    authorId: widget.profile.id,
                    authorName: _authorName(widget.profile),
                    title: title,
                    description: descriptionController.text.trim(),
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.pop(dialogContext, true);
                } catch (_) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isFrench
                            ? 'Impossible de créer la discussion.'
                            : 'Unable to create the discussion.',
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

    titleController.dispose();
    descriptionController.dispose();

    if (result == true) {
      await _loadTopics();
    }
  }

  Future<void> _manageTopic(ForumTopic topic) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  topic.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  topic.isPinned
                      ? (_isFrench ? 'Retirer l’épingle' : 'Unpin discussion')
                      : (_isFrench ? 'Épingler' : 'Pin discussion'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext, 'pin');
                },
              ),
              ListTile(
                leading: Icon(
                  topic.isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                ),
                title: Text(
                  topic.isLocked
                      ? (_isFrench ? 'Déverrouiller' : 'Unlock discussion')
                      : (_isFrench ? 'Verrouiller' : 'Lock discussion'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext, 'lock');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(_isFrench ? 'Supprimer' : 'Delete'),
                onTap: () {
                  Navigator.pop(sheetContext, 'delete');
                },
              ),
            ],
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    try {
      switch (action) {
        case 'pin':
          await _service.updateTopicPin(topic.id, !topic.isPinned);
          break;

        case 'lock':
          await _service.updateTopicLock(topic.id, !topic.isLocked);
          break;

        case 'delete':
          await _service.deleteTopic(topic.id);
          break;
      }

      await _loadTopics();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFrench ? 'Action impossible.' : 'Action failed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.forumClass.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      floatingActionButton: _isTeacher
          ? FloatingActionButton(
              onPressed: _createTopic,
              child: const Icon(Icons.add_comment_rounded),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadTopics,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(
                message: _error!,
                retryLabel: _isFrench ? 'Réessayer' : 'Try again',
                onRetry: _loadTopics,
              )
            : _topics.isEmpty
            ? _EmptyView(
                icon: Icons.forum_outlined,
                message: _isFrench
                    ? 'Aucune discussion pour le moment.'
                    : 'No discussions yet.',
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _topics.length,
                itemBuilder: (context, index) {
                  final topic = _topics[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Icon(
                          topic.isLocked
                              ? Icons.lock_rounded
                              : Icons.forum_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Row(
                        children: [
                          if (topic.isPinned)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.push_pin, size: 18),
                            ),
                          Expanded(
                            child: Text(
                              topic.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle:
                          topic.description == null ||
                              topic.description!.trim().isEmpty
                          ? null
                          : Text(
                              topic.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: _isTeacher
                          ? IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _manageTopic(topic),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ForumTopicPage(
                              locale: widget.locale,
                              profile: widget.profile,
                              topic: topic,
                              forumClass: widget.forumClass,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class ForumTopicPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final ForumTopic topic;
  final ForumClass forumClass;

  const ForumTopicPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.topic,
    required this.forumClass,
  });

  @override
  State<ForumTopicPage> createState() => _ForumTopicPageState();
}

class _ForumTopicPageState extends State<ForumTopicPage> {
  final ForumService _service = ForumService();

  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  String? _error;

  List<ForumPost> _posts = const [];

  PlatformFile? _attachment;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final posts = await _service.listPosts(widget.topic.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _posts = posts;
        _loading = false;
      });

      _scrollToBottom();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger les messages.'
            : 'Unable to load messages.';
      });
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

    const maxSize = 50 * 1024 * 1024;

    if (file.size > maxSize) {
      if (!mounted) {
        return;
      }

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

  Future<void> _sendPost() async {
    if (_sending) {
      return;
    }

    final body = _controller.text.trim();

    if (body.isEmpty && _attachment == null) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _service.createPost(
        topicId: widget.topic.id,
        authorId: widget.profile.id,
        authorName: _authorName(widget.profile),
        body: body,
        attachment: _attachment,
        classId: widget.forumClass.id,
      );

      _controller.clear();

      if (!mounted) {
        return;
      }

      setState(() {
        _attachment = null;
      });

      await _loadPosts();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible de publier le message.'
                : 'Unable to publish the message.',
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

  Future<void> _deletePost(ForumPost post) async {
    try {
      await _service.deletePost(post);
      await _loadPosts();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible de supprimer le message.'
                : 'Unable to delete the message.',
          ),
        ),
      );
    }
  }

  Future<void> _openAttachment(ForumPost post) async {
    final path = post.attachmentPath;

    if (path == null || path.trim().isEmpty) {
      return;
    }

    try {
      final url = await _service.createAttachmentSignedUrl(path);

      if (!mounted) {
        return;
      }

      if (post.isImage) {
        await showDialog<void>(
          context: context,
          builder: (_) {
            return Dialog(
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            );
          },
        );
        return;
      }

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw Exception('Unable to open attachment');
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Impossible d’ouvrir le fichier.'
                : 'Unable to open the file.',
          ),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  IconData _attachmentIcon(ForumPost post) {
    if (post.isImage) {
      return Icons.image_rounded;
    }

    if (post.isPdf) {
      return Icons.picture_as_pdf_rounded;
    }

    if (post.isVideo) {
      return Icons.video_file_rounded;
    }

    if (post.isAudio) {
      return Icons.audio_file_rounded;
    }

    return Icons.attach_file_rounded;
  }

  Widget _buildAttachment(ForumPost post) {
    return InkWell(
      onTap: () => _openAttachment(post),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          children: [
            Icon(_attachmentIcon(post), color: const Color(0xFF166534)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                post.attachmentName ??
                    (_isFrench ? 'Pièce jointe' : 'Attachment'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPost(ForumPost post) {
    final isMine = post.authorId == widget.profile.id;

    final body = post.body?.trim();

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFDCFCE7),
                      child: Text(
                        isMine ? 'V' : '?',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isMine
                            ? (_isFrench ? 'Vous' : 'You')
                            : (_isFrench ? 'Membre' : 'Member'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (isMine)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deletePost(post);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(_isFrench ? 'Supprimer' : 'Delete'),
                          ),
                        ],
                      ),
                  ],
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(body),
                ],
                if (post.hasAttachment) _buildAttachment(post),
                const SizedBox(height: 8),
                Text(
                  _formatDate(post.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    String two(int value) => value.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isLockedForStudent =
        widget.topic.isLocked && widget.profile.role != 'teacher';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.topic.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPosts,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _ErrorView(
                      message: _error!,
                      retryLabel: _isFrench ? 'Réessayer' : 'Try again',
                      onRetry: _loadPosts,
                    )
                  : _posts.isEmpty
                  ? _EmptyView(
                      icon: Icons.chat_bubble_outline_rounded,
                      message: _isFrench
                          ? 'Aucune réponse pour le moment.'
                          : 'No replies yet.',
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _posts.length,
                      itemBuilder: (context, index) {
                        return _buildPost(_posts[index]);
                      },
                    ),
            ),
          ),
          if (_attachment != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color: const Color(0xFFF0FDF4),
              child: Row(
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    color: Color(0xFF166534),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachment!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _attachment = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          if (isLockedForStudent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFFFF7ED),
              child: Text(
                _isFrench
                    ? 'Cette discussion est verrouillée.'
                    : 'This discussion is locked.',
                textAlign: TextAlign.center,
              ),
            )
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _pickAttachment,
                      tooltip: _isFrench
                          ? 'Joindre un fichier'
                          : 'Attach a file',
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText: _isFrench
                              ? 'Écrire un message...'
                              : 'Write a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : _sendPost,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
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

class _ErrorView extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline_rounded, size: 56),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retryLabel),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyView({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 68, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
