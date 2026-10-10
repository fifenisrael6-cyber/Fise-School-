import 'package:flutter/material.dart';

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

  const MessagesHubPage({super.key, required this.locale, required this.profile});

  @override
  State<MessagesHubPage> createState() => _MessagesHubPageState();
}

class _MessagesHubPageState extends State<MessagesHubPage> {
  final GroupMessageService _service = GroupMessageService();
  late Future<List<MessageGroup>> _groupsFuture;

  bool get _fr => widget.locale.languageCode == 'fr';
  bool get _isTeacher => widget.profile.role == 'teacher' || widget.profile.role == 'admin';

  @override
  void initState() {
    super.initState();
    _groupsFuture = _service.listGroups();
  }

  Future<void> _reload() async {
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          locale: widget.locale,
          profile: widget.profile,
          group: group,
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
      _snack(_fr ? 'Photo envoyée.' : 'Photo sent.');
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _fr ? 'Choisir une ou plusieurs salles' : 'Choose one or more classrooms',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
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
                      children: classes.map((schoolClass) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(schoolClass.displayName),
                        value: selectedClassIds.contains(schoolClass.id),
                        onChanged: (selected) => setDialogState(() {
                          if (selected == true) {
                            selectedClassIds.add(schoolClass.id);
                          } else {
                            selectedClassIds.remove(schoolClass.id);
                          }
                        }),
                      )).toList(),
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

      var createdCount = 0;
      final failures = <String>[];
      for (final schoolClass in targetClasses) {
        final groupName = targetClasses.length == 1
            ? name
            : '$name - ${schoolClass.displayName}';
        try {
          await _service.createGroup(
            name: groupName,
            classId: schoolClass.id,
          );
          createdCount++;
        } catch (error) {
          failures.add('${schoolClass.displayName}: $error');
        }
      }

      if (createdCount == 0) {
        throw StateError(
          failures.isEmpty
              ? (_fr ? 'Aucun groupe créé.' : 'No group was created.')
              : failures.first,
        );
      }

      await _reload();
      if (failures.isNotEmpty) {
        _snack(_fr
            ? '$createdCount groupe(s) créé(s), mais certains ont échoué : ${failures.first}'
            : '$createdCount group(s) created, but some failed: ${failures.first}');
      } else {
        _snack(_fr
            ? '$createdCount groupe(s) créé(s). Ouvrez chaque groupe pour voir son code d’invitation.'
            : '$createdCount group(s) created. Open each group to see its invitation code.');
      }
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
      await _service.joinWithCode(code);
      await _reload();
      _snack(_fr ? 'Vous avez rejoint le groupe.' : 'You joined the group.');
    } catch (error) {
      _snack(_fr ? 'Impossible de rejoindre le groupe : $error' : 'Could not join group: $error');
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
                              ? 'Vous n’êtes dans aucun groupe. Demandez le code d’invitation à votre professeur.'
                              : 'You are not in any group. Ask your teacher for the invitation code.'),
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
