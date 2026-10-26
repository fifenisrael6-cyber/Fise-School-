import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/app_database.dart';
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
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _filter = 'all';
  final AppDatabase _localDb = AppDatabase();
  Map<String, Map<String, dynamic>> _conversationPreferences = {};

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
    _groupsFuture = _loadGroupsInstant();
    _loadConversationPreferences();
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationPreferences() async {
    try {
      final preferences = await _localDb.getMessageConversationPreferences(widget.profile.id);
      if (mounted) setState(() => _conversationPreferences = preferences);
    } catch (_) {
      // Preferences are local conveniences; their failure must not hide chats.
    }
  }

  Map<String, dynamic> _preferenceFor(String groupId) =>
      _conversationPreferences['group:$groupId'] ?? const <String, dynamic>{};

  Future<void> _saveGroupPreference(
    MessageGroup group, {
    bool? pinned,
    bool? archived,
    String? mutedUntil,
    bool clearMute = false,
  }) async {
    final current = _preferenceFor(group.id);
    final nextPinned = pinned ?? current['pinned'] == true;
    if (nextPinned && current['pinned'] != true) {
      final pinnedCount = _conversationPreferences.values
          .where((value) => value['pinned'] == true && value['archived'] != true)
          .length;
      if (pinnedCount >= 3) {
        _snack(_fr ? 'Vous pouvez épingler au maximum 3 discussions.' : 'You can pin at most 3 chats.');
        return;
      }
    }
    final nextArchived = archived ?? current['archived'] == true;
    final nextMute = clearMute ? null : (mutedUntil ?? current['muted_until'] as String?);
    await _localDb.saveMessageConversationPreference(
      userId: widget.profile.id,
      conversationType: 'group',
      conversationId: group.id,
      pinned: nextPinned,
      archived: nextArchived,
      mutedUntil: nextMute,
    );
    await _loadConversationPreferences();
  }

  Future<void> _showGroupListActions(MessageGroup group) async {
    final preference = _preferenceFor(group.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: Icon(preference['pinned'] == true ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(preference['pinned'] == true ? (_fr ? 'Désépingler' : 'Unpin chat') : (_fr ? 'Épingler' : 'Pin chat')),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _saveGroupPreference(group, pinned: preference['pinned'] != true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(_fr ? 'Mettre en sourdine' : 'Mute notifications'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final duration = await showModalBottomSheet<Duration>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(title: Text(_fr ? '8 heures' : '8 hours'), onTap: () => Navigator.pop(context, const Duration(hours: 8))),
                  ListTile(title: Text(_fr ? '1 semaine' : '1 week'), onTap: () => Navigator.pop(context, const Duration(days: 7))),
                  ListTile(title: Text(_fr ? 'Toujours' : 'Always'), onTap: () => Navigator.pop(context, const Duration(days: 36500))),
                ])),
              );
              if (duration != null && mounted) {
                await _saveGroupPreference(group, mutedUntil: DateTime.now().add(duration).toUtc().toIso8601String());
              }
            },
          ),
          if (preference['muted_until'] != null)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(_fr ? 'Réactiver les notifications' : 'Unmute notifications'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _saveGroupPreference(group, clearMute: true);
              },
            ),
          ListTile(
            leading: Icon(preference['archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(preference['archived'] == true ? (_fr ? 'Désarchiver' : 'Unarchive chat') : (_fr ? 'Archiver' : 'Archive chat')),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _saveGroupPreference(group, archived: preference['archived'] != true);
            },
          ),
        ]),
      ),
    );
  }

  Future<List<MessageGroup>> _loadGroupsInstant() async {
    // A notification deep-link needs a fresh list to resolve its exact target.
    if (widget.initialTargetType == 'group' && widget.initialTargetId != null) {
      return _service.listGroups();
    }
    // Students must receive a server-authorized group list for the current
    // classroom. A local cache can contain groups from a room they just left,
    // so it must not be displayed before Supabase validates the current scope.
    if (!_isTeacher) return _service.listGroups();

    try {
      final cached = await _service.getCachedGroups();
      if (cached.isNotEmpty) {
        unawaited(_refreshGroupsInBackground());
        return cached;
      }
    } catch (_) {
      // Use the server list if the local snapshot is unavailable.
    }
    return _service.listGroups();
  }

  Future<void> _refreshGroupsInBackground() async {
    try {
      final groups = await _service.listGroups();
      if (mounted) setState(() => _groupsFuture = Future.value(groups));
    } catch (_) {
      // Keep local groups visible offline.
    }
  }

  void _refreshGroups() {
    unawaited(_refreshGroupsInBackground());
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
    try {
      classes = (await CourseService().listTeacherCompatibleClasses())
          .where((schoolClass) => !_isCombinedLanguageRoom(schoolClass.displayName))
          .where((schoolClass) =>
              (widget.profile.subsystem != null && schoolClass.subsystem.name == widget.profile.subsystem!.toLowerCase().trim()) &&
              (widget.profile.sector != null && schoolClass.sector.name == widget.profile.sector!.toLowerCase().trim()))
          .toList(growable: false);
    } catch (_) {
      classes = const [];
    }
    if (!mounted) {
      return;
    }

    final nameController = TextEditingController();
    final classSearchController = TextEditingController();
    String? classId;

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
              DropdownButtonFormField<String>(
                initialValue: classId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _fr ? 'Salle (facultatif)' : 'Classroom (optional)',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(_fr ? 'Toutes les salles compatibles' : 'All compatible classrooms'),
                  ),
                  ...classes.where((c) => c.displayName.toLowerCase().contains(classSearchController.text.trim().toLowerCase()))
                    .map((c) => DropdownMenuItem<String>(value: c.id, child: Text(c.displayName))),
                ],
                onChanged: (value) => setDialogState(() => classId = value),
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
    classSearchController.dispose();

    if (created != true || name.isEmpty) {
      return;
    }

    try {
      await _service.createGroup(name: name, classId: classId);
      await _reload();
      _snack(_fr
          ? 'Groupe créé. Ouvrez-le pour voir le code d’invitation.'
          : 'Group created. Open it to see the invitation code.');
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _joinGroup() async {
    // A group is a paid feature scoped to the student's current classroom.
    // The server repeats this check in join_message_group and its RLS helper.
    final canJoin = await PremiumGate.ensure(
      context,
      profile: widget.profile,
      feature: QuotaFeature.msgSent,
      premiumOnly: true,
    );
    if (!canJoin || !mounted) return;

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
      // Show the actionable reason returned by the existing secured RPC instead
      // of hiding every failure behind the same "invalid code" message.
      final detail = error.toString().toLowerCase();
      final message = detail.contains('premium payment is required') ||
              detail.contains('premium payment required')
          ? (_fr
              ? 'Payez d’abord Premium pour cette salle avant de rejoindre ses groupes.'
              : 'Pay for Premium in this classroom before joining its groups.')
          : detail.contains('invalid or inactive fise code') ||
              detail.contains('invalid invitation code') ||
              detail.contains('invitation code')
          ? (_fr
              ? 'Code FISE invalide ou désactivé. Demandez le code FISE actuel à votre professeur.'
              : 'Invalid or inactive FISE code. Ask your teacher for the current FISE code.')
          : detail.contains('no active classroom')
              ? (_fr
                  ? 'Aucune classe active n’est associée à votre compte. Faites vérifier votre classe.'
                  : 'No active classroom is assigned to your account. Please have your class checked.')
              : detail.contains('belongs to another teacher')
                  ? (_fr
                      ? 'Ce code appartient à un autre enseignant.'
                      : 'This code belongs to another teacher.')
                  : detail.contains('profile not found')
                      ? (_fr
                          ? 'Votre profil scolaire est introuvable. Reconnectez-vous ou faites vérifier votre compte.'
                          : 'Your school profile was not found. Sign in again or have your account checked.')
                      : (_fr
                          ? 'Impossible de rejoindre le groupe. Vérifiez le code FISE et votre classe, puis réessayez.'
                          : 'Could not join the group. Check the FISE code and your class, then try again.');
      _snack(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _fr ? 'Rechercher une discussion' : 'Search chats',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(_fr ? 'Messagerie' : 'Messages'),
        actions: [
          IconButton(
            tooltip: _searching
                ? (_fr ? 'Fermer la recherche' : 'Close search')
                : (_fr ? 'Rechercher' : 'Search'),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              if (_searching) _searchController.clear();
              _searching = !_searching;
            }),
          ),
          IconButton(
            tooltip: _fr ? 'Prendre une photo' : 'Take a photo',
            icon: const Icon(Icons.camera_alt_rounded),
            onPressed: _quickCamera,
          ),
          PopupMenuButton<String>(
            tooltip: _fr ? 'Plus d’options' : 'More options',
            onSelected: (value) {
              switch (value) {
                case 'private':
                  _openPrivateMessages();
                  break;
                case 'group':
                  if (_isTeacher) _createGroup(); else _joinGroup();
                  break;
                case 'refresh':
                  _reload();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'private', child: Text(_fr ? 'Messages privés' : 'Private messages')),
              PopupMenuItem(value: 'group', child: Text(_isTeacher ? (_fr ? 'Nouveau groupe' : 'New group') : (_fr ? 'Rejoindre avec un code' : 'Join with a code'))),
              PopupMenuItem(value: 'refresh', child: Text(_fr ? 'Actualiser' : 'Refresh')),
            ],
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
            final query = _searchController.text.trim().toLowerCase();
            final visibleGroups = groups.where((group) {
              final preference = _preferenceFor(group.id);
              if (_filter == 'archived' && preference['archived'] != true) return false;
              if (_filter != 'archived' && preference['archived'] == true) return false;
              if (_filter == 'groups' && group.id.isEmpty) return false;
              if (_filter == 'unread' && group.unreadCount <= 0) return false;
              if (query.isEmpty) return true;
              return group.name.toLowerCase().contains(query) ||
                  (group.lastBody ?? '').toLowerCase().contains(query) ||
                  (group.className ?? '').toLowerCase().contains(query);
            }).toList(growable: false)
              ..sort((a, b) {
                final aPref = _preferenceFor(a.id);
                final bPref = _preferenceFor(b.id);
                final aPinned = aPref['pinned'] == true ? 1 : 0;
                final bPinned = bPref['pinned'] == true ? 1 : 0;
                if (aPinned != bPinned) return bPinned.compareTo(aPinned);
                final aTime = a.lastAt?.millisecondsSinceEpoch ?? 0;
                final bTime = b.lastAt?.millisecondsSinceEpoch ?? 0;
                return bTime.compareTo(aTime);
              });

            return ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(_fr ? 'Toutes' : 'All'),
                        selected: _filter == 'all',
                        onSelected: (_) => setState(() => _filter = 'all'),
                      ),
                      ChoiceChip(
                        label: Text(_fr ? 'Non lues' : 'Unread'),
                        selected: _filter == 'unread',
                        onSelected: (_) => setState(() => _filter = 'unread'),
                      ),
                      ChoiceChip(
                        label: Text(_fr ? 'Groupes' : 'Groups'),
                        selected: _filter == 'groups',
                        onSelected: (_) => setState(() => _filter = 'groups'),
                      ),
                    ],
                  ),
                ),
                if (_filter != 'archived' && _conversationPreferences.values.any((value) => value['archived'] == true))
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(_fr ? 'Archivées' : 'Archived'),
                    trailing: Text('${_conversationPreferences.values.where((value) => value['archived'] == true).length}'),
                    onTap: () => setState(() => _filter = 'archived'),
                  ),
                if (_filter == 'all')
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
                if (_filter == 'all') const Divider(height: 1),
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
                else if (visibleGroups.isEmpty)
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
                  ...visibleGroups.map(
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
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatTime(group.lastAt), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          if (group.unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: const BoxDecoration(color: Color(0xFF166534), shape: BoxShape.circle),
                              child: Text('${group.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                          if (_preferenceFor(group.id)['pinned'] == true || _preferenceFor(group.id)['muted_until'] != null)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_preferenceFor(group.id)['pinned'] == true) const Icon(Icons.push_pin_rounded, size: 13),
                              if (_preferenceFor(group.id)['muted_until'] != null) const Icon(Icons.notifications_off_outlined, size: 13),
                            ]),
                        ],
                      ),
                      onLongPress: () => _showGroupListActions(group),
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
