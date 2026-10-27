import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../models/user_profile.dart';
import '../../student/pages/pages/premium_page.dart';
import '../../teacher/pages/teacher_class_selection_page.dart';

class ProfilePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final ValueChanged<UserProfile>? onSaved;

  const ProfilePage({
    super.key,
    required this.locale,
    required this.profile,
    this.onSaved,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late UserProfile _profile = widget.profile;
  late final _firstName = TextEditingController(text: widget.profile.firstName);
  late final _lastName = TextEditingController(text: widget.profile.lastName);
  late final _email = TextEditingController(text: widget.profile.email ?? '');

  final _profiles = ProfileService();
  final _photos = PhotoService();

  late String _language = widget.profile.preferredLanguage;
  bool _loading = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.profile)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _avatar(context, texts),
            const SizedBox(height: 24),
            TextFormField(
              controller: _firstName,
              decoration: InputDecoration(labelText: texts.firstName),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              decoration: InputDecoration(labelText: texts.lastName),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              readOnly: true,
              decoration: InputDecoration(labelText: texts.email),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(labelText: texts.language),
              items: [
                DropdownMenuItem(value: 'fr', child: Text(texts.french)),
                DropdownMenuItem(value: 'en', child: Text(texts.english)),
              ],
              onChanged: (value) => setState(() => _language = value ?? 'fr'),
            ),
            const SizedBox(height: 24),
            _schoolInfo(texts),
            if (widget.profile.role == 'teacher') ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.meeting_room_rounded),
                  title: Text(widget.locale.languageCode == 'fr'
                      ? 'Mes cours et mes salles'
                      : 'My courses and classrooms'),
                  subtitle: Text(widget.locale.languageCode == 'fr'
                      ? 'Ajouter ou retirer les salles affichées dans votre espace de travail pour les cours, QCM et activités.'
                      : 'Add or remove classrooms shown in your workspace for courses, quizzes and activities.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TeacherClassSelectionPage(
                      locale: widget.locale,
                      profile: _profile,
                    ),
                  )),
                ),
              ),
            ],
            if (widget.profile.role == 'student') ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFB45309)),
                  title: Text(texts.isEnglish ? 'Premium subscription' : 'Abonnement Premium'),
                  subtitle: Text(texts.isEnglish
                      ? '2,000 XAF for 30 days • quotas and status'
                      : '2 000 FCFA pour 30 jours • quotas et état'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PremiumPage(locale: widget.locale, profile: widget.profile),
                  )),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, AppTexts texts) {
    return Center(
      child: PopupMenuButton<String>(
        onSelected: (value) =>
            value == 'delete' ? _deletePhoto(texts) : _pickPhoto(value, texts),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'camera', child: Text(texts.takePhoto)),
          PopupMenuItem(value: 'gallery', child: Text(texts.choosePhoto)),
          if (_profile.avatarPath != null)
            PopupMenuItem(value: 'delete', child: Text(texts.deletePhoto)),
        ],
        child: FutureBuilder<String?>(
          future: _photos.cachedAvatarFile(_profile.avatarPath),
          builder: (context, snapshot) {
            final localPath = snapshot.data;
            final hasLocal = localPath != null && File(localPath).existsSync();
            return CircleAvatar(
              radius: 48,
              backgroundImage: hasLocal ? FileImage(File(localPath)) : null,
              child: hasLocal ? null : const Icon(Icons.person_rounded, size: 48),
            );
          },
        ),
      ),
    );
  }

  Widget _schoolInfo(AppTexts texts) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texts.schooling,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${texts.subsystem}: ${widget.profile.subsystem ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}',
          ),
          Text(
            '${texts.sector}: ${widget.profile.sector ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}',
          ),
          Text(
            '${texts.examLevel}: ${widget.profile.examLevel ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}',
          ),
          Text('${texts.exam}: ${widget.profile.exam ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}'),
          Text(
            '${texts.schoolClass}: ${widget.profile.className ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}',
          ),
        ],
      ),
    ),
  );

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? AppTexts(widget.locale).requiredField
      : null;

  Future<void> _save(AppTexts texts) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _loading = true);

    try {
      final updated = await _profiles.updateEditableProfile(
        firstName: _firstName.text,
        lastName: _lastName.text,
        preferredLanguage: _language,
      );

      widget.onSaved?.call(updated);

      if (mounted) {
        Navigator.pop(context, updated);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(texts.profileSaveError)));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Met à jour l'écran et prévient le reste de l'application.
  void _applyAvatar(String? path) {
    final updated = UserProfile.fromMap({
      ..._profile.toMap(),
      'avatar_path': path,
    });
    setState(() => _profile = updated);
    widget.onSaved?.call(updated);
  }

  Future<void> _pickPhoto(String source, AppTexts texts) async {
    final XFile? file = source == 'camera'
        ? await _photos.takePhoto(maxWidth: 800)
        : await _photos.pickFromGallery(maxWidth: 800);

    if (file == null) {
      return;
    }

    final previous = _profile.avatarPath;
    try {
      final path = await _photos.uploadProfilePhoto(_profile.id, file);
      if (!mounted) return;
      _applyAvatar(path);
      // Supprime l'ancienne photo pour ne pas encombrer le stockage.
      if (previous != null && previous.isNotEmpty) {
        try {
          await Supabase.instance.client.storage
              .from('profile-photos')
              .remove([previous]);
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(texts.photoError)));
      }
    }
  }

  Future<void> _deletePhoto(AppTexts texts) async {
    try {
      await _photos.deleteProfilePhoto(_profile.id, _profile.avatarPath);
      if (!mounted) return;
      _applyAvatar(null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(texts.photoError)));
      }
    }
  }
}
