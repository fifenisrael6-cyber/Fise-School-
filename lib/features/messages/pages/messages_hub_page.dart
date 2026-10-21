import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/group_message_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/message_group.dart';
import '../../../models/school_class.dart';
import '../../../core/services/quota_service.dart';
import '../../../models/user_profile.dart';
import '../../premium/premium_gate.dart';
import 'group_chat_page.dart';
import 'private_messages_page.dart';

/// Espace Messages façon WhatsApp : liste des groupes et accès aux messages
/// privés. Le code FISE personnel de l'enseignant permet de rejoindre les
/// groupes autorisés pour la classe de l'élève.
class MessagesHubPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final PickedAttachment? initialSharedAttachment;
  final String? initialTargetType;
  final String? initialTargetId;

  const MessagesHubPage({super.key, required this.locale, required this.profile, this.initialSharedAttachment, this.initialTargetType, this.initialTargetId});

  @override
  State<MessagesHubPage> createState() => _MessagesHubPageState();
}

class _MessagesHubPageState extends State<MessagesHubPage> {
  final GroupMessageService _service = GroupMessageService();
  late Future<List<MessageGroup>> _groupsFuture;
  RealtimeChannel? _groupsChannel;
  PickedAttachment? _pendingSharedAttachment;

  bool _isCombinedLanguageRoom(String label) {
    const languages = <String>[
      'anglais', 'english', 'allemand', 'german',
      'espagnol', 'espaniol', 'espanol', 'spanish',
      'italien', 'italian', 'arabe', 'arabic',
      'chinois', 'chinese', 'portugais', 'portuguese',
      'russe', 'russian', 'latin',
    ];
    return languages.where(label.toLowerCase().contains).length >= 2;
  }

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _isTeacher => widget.profile.role == 'teacher' || widget.profile.role == 'admin';

  @override
  void initState() {
    super.initState();
    _pendingSharedAttachment = widget.initialSharedAttachment;
    _groupsFuture = _service.listGroups();
    // Open the exact conversation identified by a message notification.
    final targetType = widget.initialTargetType;
    final targetId = widget.initialTargetId;
    if (targetType == 'private_message' && targetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPrivateMessages(initialContactId: targetId);
      });
    } else if (targetType == 'group' && targetId != null) {
      _groupsFuture.then((groups) {
        if (!mounted) return;
        for (final group in groups) {
          if (group.id == targetId) {
            _openGroup(group);
            break;
          }
        }
      }).catchError((_) {});
    }
    // Keep the Messages navigation widget while restoring live updates in its
    // conversation list, so new group messages refresh the preview and time.
    _groupsChannel = Supabase.instance.client
        .channel('messages-hub-${widget.profile.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_messages',
        callback: (_) => _refreshGroups(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_groups',
        callback: (_) => _refreshGroups(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'message_groups',
        callback: (_) => _refreshGroups(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'message_groups',
        callback: (_) => _refreshGroups(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_members',
        callback: (_) => _refreshGroups(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'message_group_members',
        callback: (_) => _refreshGroups(),
      )
      ..subscribe();
  }

  @override
  void dispose() {
    _groupsChannel?.unsubscribe();
    super.dispose();
  }

  void _refreshGroups() {
    if (mounted) {
      setState(() => _groupsFuture = _service.listGroups());
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _groupsFuture = _service.listGroups());
    await _groupsFuture;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }

  Future<void> _openGroup(MessageGroup group) async {
    final attachment = _pendingSharedAttachment;
    if (attachment != null) setState(() => _pendingSharedAttachment = null);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          locale: widget.locale,
          profile: widget.profile,
          group: group,
          initialAttachment: attachment,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openPrivateMessages({String? initialContactId}) async {
    final attachment = _pendingSharedAttachment;
    if (attachment != null) setState(() => _pendingSharedAttachment = null);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateMessagesPage(
          locale: widget.locale,
          profile: widget.profile,
          initialAttachment: attachment,
          initialContactId: initialContactId,
        ),
      ),
    );
  }

  /// Raccourci caméra façon WhatsApp : photo, puis choix du groupe destinataire.
  Future<void> _quickCamera() async {
    final groups = await _groupsFuture.catchError((_) => const <MessageGroup>[]);
    if (!mounted) {
      return;
    }
    if (groups.isEmpty) {
      _snack(_fr
          ? 'Rejoignez d’abord un groupe pour envoyer une photo.'
          : 'Join a group first to send a photo.');
      return;
    }

    final photo = await PhotoService().takePhoto();
    if (photo == null || !mounted) {
      return;
    }

    final target = await showModalBottomSheet<MessageGroup>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _fr ? 'Envoyer la photo à…' : 'Send the photo to…',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            ...groups.map(
              (group) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF166534),
                  child: Icon(Icons.group_rounded, color: Colors.white),
                ),
                title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(sheetContext, group),
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) {
      return;
    }
    final canSend = await PremiumGate.canSend(
      context,
      profile: widget.profile,
      feature: QuotaFeature.msgSent,
      hasAttachment: true,
    );
    if (!canSend || !mounted) return;

    try {
      final bytes = await photo.readAsBytes();
      await _service.send(
        groupId: target.id,
        body: '',
        attachmentBytes: bytes,
        attachmentName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        attachmentType: 'image/jpeg',
      );
      await _reload();
      _snack(_fr ? 'Photo envoyée.' : 'Photo sent.');
    } catch (_) {
      _snack(_fr ? 'Envoi impossible.' : 'Unable to send.');
    }
  }

  Future<void> _createGroup() async {
    List<SchoolClass> classes = const [];
    Set<String> savedRoomIds = <String>{};
    try {
      final courseService = CourseService();
      classes = (await courseService.listTeacherCompatibleClasses())
          .where((schoolClass) => !_isCombinedLanguageRoom(schoolClass.displayName))
          .where((schoolClass) =>
              (widget.profile.subsystem != null && schoolClass.subsystem.name == widget.profile.subsystem!.toLowerCase().trim()) &&
              (widget.profile.sector != null && schoolClass.sector.name == widget.profile.sector!.toLowerCase().trim()) &&
              true)
          .toList(growable: false);
      savedRoomIds = await courseService.listTeacherFollowedClassIds();
      savedRoomIds.retainAll(classes.map((room) => room.id));
    } catch (_) {
      classes = const [];
    }
    if (!mounted) return;

    final nameController = TextEditingController();
    final classSearchController = TextEditingController();
    final selectedClassIds = <String>{...savedRoomIds};

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = classSearchController.text.trim().toLowerCase();
          final visibleClasses = classes
              .where((room) => room.displayName.toLowerCase().contains(query))
              .toList(growable: false);
          return AlertDialog(
            title: Text(_fr ? 'Créer un groupe' : 'Create a group'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    onChanged: (_) => setDialogState(() {}),
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _fr ? 'Nom du groupe' : 'Group name',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _fr ? 'Choisissez une ou plusieurs salles' : 'Choose one or more classrooms',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: classSearchController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _fr ? 'Rechercher une salle…' : 'Search classrooms…',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (classes.isEmpty)
                    Text(_fr ? 'Aucune salle compatible disponible.' : 'No compatible classrooms available.')
                  else
                    SizedBox(
                      height: 260,
                      child: ListView(
                        shrinkWrap: true,
                        children: visibleClasses.map((room) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedClassIds.contains(room.id),
                          title: Text(room.displayName),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selectedClassIds.add(room.id);
                            } else {
                              selectedClassIds.remove(room.id);
                            }
                          }),
                        )).toList(growable: false),
                      ),
                    ),
                  if (selectedClassIds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _fr ? 'Sélectionnez au moins une salle.' : 'Select at least one classroom.',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_fr ? 'Annuler' : 'Cancel'),
              ),
              FilledButton(
                onPressed: selectedClassIds.isEmpty || nameController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(_fr ? 'Créer' : 'Create'),
              ),
            ],
          );
        },
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();
    classSearchController.dispose();

    if (created != true || name.isEmpty || selectedClassIds.isEmpty) return;

    try {
      await _service.createGroup(name: name, classIds: selectedClassIds.toList(growable: false));
      await _reload();
      _snack(_fr
          ? 'Groupe créé pour ${selectedClassIds.length} salle(s). Ouvrez-le pour voir le code d’invitation.'
          : 'Group created for ${selectedClassIds.length} classroom(s). Open it to see the invitation code.');
    } catch (error) {
      _snack('${_fr ? 'Création impossible' : 'Could not create group'}: $error');
    }
  }

  Future<void> _joinGroup() async {
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Rejoindre un groupe' : 'Join a group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: _fr ? 'Code donné par votre professeur' : 'Code from your teacher',
            hintText: 'FISE-XXXXXX',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Rejoindre' : 'Join'),
          ),
        ],
      ),
    );

    final code = controller.text.trim();
    controller.dispose();

    if (confirmed != true || code.isEmpty) {
      return;
    }

    try {
      final joinedGroupId = await _service.joinWithCode(code);
      await _reload();
      _snack(joinedGroupId.isEmpty
          ? (_fr
              ? 'Code FISE validé. Les évaluations de cet enseignant sont maintenant accessibles ; aucun groupe n’est encore créé pour votre salle.'
              : 'FISE code validated. This teacher’s evaluations are now accessible; no group has been created for your classroom yet.')
          : (_fr ? 'Groupes autorisés ajoutés.' : 'Eligible groups added.'));
    } catch (error) {
      _snack(_fr ? 'Code invalide ou accès refusé.' : 'Invalid code or access denied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Messagerie' : 'Messages'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Prendre une photo' : 'Take a photo',
            icon: const Icon(Icons.camera_alt_rounded),
            onPressed: _quickCamera,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTeacher ? _createGroup : _joinGroup,
        icon: Icon(_isTeacher ? Icons.group_add_rounded : Icons.vpn_key_rounded),
        label: Text(
          _isTeacher
              ? (_fr ? 'Nouveau groupe' : 'New group')
              : (_fr ? 'Rejoindre avec un code' : 'Join with a code'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<MessageGroup>>(
          future: _groupsFuture,
          builder: (context, snapshot) {
            final groups = snapshot.data ?? const <MessageGroup>[];

            return ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.person_rounded, color: Color(0xFF166534)),
                  ),
                  title: Text(
                    _fr ? 'Messages privés' : 'Private messages',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(_fr ? 'Discussions individuelles' : 'One-to-one chats'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openPrivateMessages,
                ),
                const Divider(height: 1),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snapshot.error}', textAlign: TextAlign.center),
                  )
                else if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _isTeacher
                          ? (_fr
                              ? 'Aucun groupe. Créez vos groupes puis partagez votre code FISE unique.'
                              : 'No group yet. Create groups and share your single FISE code.')
                          : (_fr
                              ? 'Vous n’êtes dans aucun groupe. Demandez le code FISE unique à votre professeur.'
                              : 'You are not in any group. Ask your teacher for their unique FISE code.'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...groups.map(
                    (group) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF166534),
                        child: Text(
                          group.name.isEmpty ? '?' : group.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        group.lastBody ??
                            (group.className ??
                                '${group.memberCount} ${_fr ? 'membre(s)' : 'member(s)'}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _formatTime(group.lastAt),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      onTap: () => _openGroup(group),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
