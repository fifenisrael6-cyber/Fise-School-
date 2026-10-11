import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../models/user_profile.dart';

/// Shown when Android opens Fise School from the system Share sheet.
class SharedMediaDestinationPage extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;
  final List<SharedMediaFile> files;
  final ValueChanged<String> onChoose;
  final VoidCallback onCancel;

  const SharedMediaDestinationPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.files,
    required this.onChoose,
    required this.onCancel,
  });

  bool get _fr => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    final isTeacher = profile.role.toLowerCase() == 'teacher' ||
        profile.role.toLowerCase() == 'admin';
    final options = <_Destination>[
      if (isTeacher) _Destination('courses', Icons.menu_book_rounded,
          _fr ? 'Cours et ressources' : 'Courses and resources',
          _fr ? 'Ajouter aux médias d’une classe' : 'Add to a classroom resource'),
      if (isTeacher) _Destination('annals', Icons.history_edu_rounded,
          _fr ? 'Annales d’examens' : 'Past exam papers',
          _fr ? 'Sujet ou corrigé d’examen' : 'Exam paper or answer key'),
      if (isTeacher) _Destination('qcm', Icons.quiz_rounded, 'QCM',
          _fr ? 'Espace de création des quiz' : 'Quiz creation workspace'),
      _Destination('private', Icons.person_rounded,
          _fr ? 'Messagerie privée' : 'Private messages',
          _fr ? 'Envoyer à une personne' : 'Send to one person'),
      _Destination('groups', Icons.groups_rounded,
          _fr ? 'Messagerie de groupe' : 'Group messages',
          _fr ? 'Envoyer dans un groupe autorisé' : 'Send to an authorized group'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Partager dans Fise School' : 'Share to Fise School'),
        leading: IconButton(
          tooltip: _fr ? 'Fermer' : 'Close',
          icon: const Icon(Icons.close),
          onPressed: onCancel,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.file_download_done_rounded, size: 44),
            const SizedBox(height: 8),
            Text(
              _fr ? '${files.length} fichier(s) reçu(s)' : '${files.length} file(s) received',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...files.map((file) {
              final name = file.path.split('/').last;
              final mime = (file.mimeType ?? '').toLowerCase();
              final icon = mime.startsWith('image/')
                  ? Icons.image_outlined
                  : mime.startsWith('video/')
                      ? Icons.video_file_outlined
                      : Icons.picture_as_pdf_outlined;
              return Card(
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(name.isEmpty ? (_fr ? 'Fichier partagé' : 'Shared file') : name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(file.mimeType ?? (_fr ? 'Type inconnu' : 'Unknown type')),
                ),
              );
            }),
            const SizedBox(height: 18),
            Text(
              _fr ? 'Que voulez-vous faire avec ce fichier ?' : 'What would you like to do with this file?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...options.map((option) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(option.icon)),
                title: Text(option.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(option.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onChoose(option.key),
              ),
            )),
            const SizedBox(height: 12),
            Text(
              _fr
                  ? 'Le fichier est reçu par Fise School. Choisissez une destination pour continuer.'
                  : 'Fise School has received the file. Choose a destination to continue.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;

  const _Destination(this.key, this.icon, this.title, this.subtitle);
}
