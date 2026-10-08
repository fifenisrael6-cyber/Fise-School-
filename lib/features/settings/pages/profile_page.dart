import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/photo_service.dart';
import '../../../core/services/profile_service.dart';
import '../../../models/user_profile.dart';

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
          if (widget.profile.avatarPath != null)
            PopupMenuItem(value: 'delete', child: Text(texts.deletePhoto)),
        ],
        child: FutureBuilder<String?>(
          future: _photos.signedUrl(widget.profile.avatarPath),
          builder: (context, snapshot) => CircleAvatar(
            radius: 48,
            backgroundImage: snapshot.data == null
                ? null
                : NetworkImage(snapshot.data!),
            child: snapshot.data == null
                ? const Icon(Icons.person_rounded, size: 48)
                : null,
          ),
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

  Future<void> _pickPhoto(String source, AppTexts texts) async {
    final XFile? file = source == 'camera'
        ? await _photos.takePhoto()
        : await _photos.pickFromGallery();

    if (file == null) {
      return;
    }

    try {
      await _photos.uploadProfilePhoto(widget.profile.id, file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(texts.photoError)));
      }
    }
  }

  Future<void> _deletePhoto(AppTexts texts) async {
    try {
      await _photos.deleteProfilePhoto(
        widget.profile.id,
        widget.profile.avatarPath,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(texts.photoError)));
      }
    }
  }
}
