import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/message_outbox.dart';
import '../../../core/services/group_message_service.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/message_group.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import 'group_chat_page.dart';
import 'private_messages_page.dart';

/// Espace Messages façon WhatsApp : liste des groupes et accès aux messages
/// privés. Un élève n'entre dans un groupe qu'avec le code unique créé par
/// l'enseignant propriétaire du groupe.
class MessagesHubPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final List<PickedAttachment> initialSharedAttachments;

  const MessagesHubPage({super.key, required this.locale, required this.profile, this.initialSharedAttachments = const []});

  @override
  State<MessagesHubPage> createState() => _MessagesHubPageState();
}

class _MessagesHubPageState extends State<MessagesHubPage> {
  final GroupMessageService _service = GroupMessageService();
  late Future<List<MessageGroup>> _groupsFuture;
  RealtimeChannel? _realtime;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _isTeacher => widget.profile.role == 'teacher' || widget.profile.role == 'admin';

  @override
  void initState() {
    super.initState();
    _groupsFuture = _service.listGroups();
    _realtime = Supabase.instance.client
        .channel('messages-hub-${widget.profile.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_group_messages',
        callback: (_) {
          if (mounted) setState(() => _groupsFuture = _service.listGroups());
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_group_message_receipts',
        callback: (_) {
          if (mounted) setState(() => _groupsFuture = _service.listGroups());
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_group_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: widget.profile.id,
        ),
        callback: (_) {
          if (mounted) setState(() => _groupsFuture = _service.listGroups());
        },
      )
      .subscribe();
  }

  Future<void> _reload() async {
    setState(() => _groupsFuture = _service.listGroups());
    try {
      await _groupsFuture;
    } catch (_) {
      // Hors ligne sans copie locale : le FutureBuilder affiche déjà la liste vide.
    }
  }

  @override
  void dispose() {
    _realtime?.unsubscribe();
    super.dispose();
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          locale: widget.locale,
          profile: widget.profile,
          group: group,
          initialAttachment: widget.initialSharedAttachments.isEmpty ? null : widget.initialSharedAttachments.first,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
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
      final stillWaiting = await MessageOutbox.instance
          .pending(scope: 'group', targetId: target.id);
      _snack(stillWaiting.isEmpty
          ? (_fr ? 'Photo envoyée.' : 'Photo sent.')
          : (_fr
              ? 'Photo enregistrée : elle partira dès le retour du réseau.'
              : 'Photo saved: it will be sent when you are back online.'));
    } catch (_) {
      _snack(_fr ? 'Envoi impossible.' : 'Unable to send.');
    }
  }

  Future<void> _createGroup() async {
    List<SchoolClass> classes = const [];
    try {
      classes = await CourseService().listTeacherCompatibleClasses();
    } catch (_) {
      classes = const [];
    }
    if (!mounted) {
      return;
    }

    final nameController = TextEditingController();
    final Set<String> selectedClassIds = <String>{};

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_fr ? 'Créer un groupe' : 'Create a group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _fr ? 'Nom du groupe' : 'Group name',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fr ? 'Choisir les salles' : 'Choose classrooms',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: classes.isEmpty
                        ? null
                        : () => setDialogState(() {
                              if (selectedClassIds.length == classes.length) {
                                selectedClassIds.clear();
                              } else {
                                selectedClassIds
                                  ..clear()
                                  ..addAll(classes.map((schoolClass) => schoolClass.id));
                              }
                            }),
                    child: Text(
                      selectedClassIds.length == classes.length && classes.isNotEmpty
                          ? (_fr ? 'Tout désélectionner' : 'Clear all')
                          : (_fr ? 'Tout sélectionner' : 'Select all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (classes.isEmpty)
                Text(_fr
                    ? 'Aucune salle compatible avec votre sous-système et votre secteur.'
                    : 'No classrooms match your subsystem and sector.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      children: classes.asMap().entries.map((entry) {
                        final schoolClass = entry.value;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${entry.key + 1}. ${schoolClass.displayName}'),
                          value: selectedClassIds.contains(schoolClass.id),
                          onChanged: (selected) => setDialogState(() {
                            if (selected == true) {
                              selectedClassIds.add(schoolClass.id);
                            } else {
                              selectedClassIds.remove(schoolClass.id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_fr ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_fr ? 'Créer' : 'Create'),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();

    if (created != true || name.isEmpty) {
      return;
    }
    if (selectedClassIds.isEmpty) {
      _snack(_fr ? 'Choisissez au moins une salle.' : 'Select at least one classroom.');
      return;
    }

    try {
      final targetClasses = classes
          .where((schoolClass) => selectedClassIds.contains(schoolClass.id))
          .toList(growable: false);
      final targetClassIds = targetClasses
          .map((schoolClass) => schoolClass.id)
          .toList(growable: false);
      await CourseService().authorizeTeacherClasses(targetClassIds);

      await _service.createGroup(
        name: name,
        classIds: targetClassIds,
      );

      await _reload();
      _snack(_fr
          ? 'Groupe « $name » créé pour ${targetClasses.length} salle(s). Les élèves de ces salles y ont accès.'
          : 'Group “$name” created for ${targetClasses.length} classroom(s). Students in those classrooms can access it.');
    } catch (error) {
      _snack('$error');
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
            labelText: _fr ? 'Code unique de l’enseignant' : 'Teacher’s unique code',
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
            child: Text(_fr ? 'Continuer' : 'Continue'),
          ),
        ],
      ),
    );

    final code = controller.text.trim();
    controller.dispose();
    if (confirmed != true || code.isEmpty) return;

    try {
      final choices = await _service.listTeacherGroupsByCode(code);
      if (!mounted) return;

      // Un code maître FISE doit toujours passer par la sélection du groupe/salle.
      // Ne jamais le transmettre à l'ancien flux, qui pourrait inscrire l'élève
      // automatiquement dans tous les groupes compatibles.
      final isTeacherMasterCode =
          RegExp(r'^FISE[- ]?', caseSensitive: false).hasMatch(code.trim());
      if (choices.isEmpty && !isTeacherMasterCode) {
        // Compatibilité uniquement pour les anciens codes d'invitation de groupe (GPR).
        await _service.joinWithCode(code);
        await _reload();
        _snack(_fr ? 'Vous avez rejoint le groupe.' : 'You joined the group.');
        return;
      }
      if (choices.isEmpty && isTeacherMasterCode) {
        _snack(_fr
            ? 'Aucun groupe de cet enseignant n’est disponible pour votre salle. Vérifiez votre classe ou demandez à l’enseignant de créer un groupe pour celle-ci.'
            : 'This teacher has no group available for your classroom. Check your class or ask the teacher to create a group for it.');
        return;
      }

      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_fr ? 'Choisir le groupe et la salle' : 'Choose group and classroom'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: choices.map((choice) {
                  final groupName = (choice['group_name'] ?? '').toString();
                  final className = (choice['class_name'] ?? '').toString();
                  final classId = (choice['class_id'] ?? '').toString();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.groups_rounded),
                    ),
                    title: Text(
                      groupName.isEmpty
                          ? (_fr ? 'Groupe sans nom' : 'Unnamed group')
                          : groupName,
                    ),
                    subtitle: Text(
                      className.isEmpty
                          ? (_fr ? 'Salle non définie' : 'Classroom not assigned')
                          : className,
                    ),
                    enabled: classId.isNotEmpty,
                    onTap: classId.isEmpty
                        ? null
                        : () => Navigator.pop(dialogContext, choice),
                  );
                }).toList(growable: false),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_fr ? 'Annuler' : 'Cancel'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;

      await _service.joinTeacherGroupByCode(
        code: code,
        groupId: (selected['group_id'] ?? '').toString(),
        classId: (selected['class_id'] ?? '').toString(),
      );
      await _reload();
      _snack(_fr
          ? 'Accès au groupe accordé pour votre salle.'
          : 'Group access granted for your classroom.');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      _snack(message.contains('classroom') || message.contains('salle')
          ? (_fr
              ? 'Accès refusé : ce groupe ne correspond pas à votre salle.'
              : 'Access denied: this group does not match your classroom.')
          : (_fr
              ? 'Impossible de rejoindre le groupe : $error'
              : 'Could not join group: $error'));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Messages' : 'Messages'),
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivateMessagesPage(
                        locale: widget.locale,
                        profile: widget.profile,
                        initialAttachment: widget.initialSharedAttachments.isEmpty ? null : widget.initialSharedAttachments.first,
                      ),
                    ),
                  ),
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
                              ? 'Aucun groupe. Créez un groupe puis donnez son code d’invitation à vos élèves.'
                              : 'No group yet. Create one and give its invitation code to your students.')
                          : (_fr