import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import 'create_course_page.dart';

/// Teacher entry point for sharing chapter media.
/// Teachers cannot author written courses or chapter quizzes from this screen.
class TeacherCoursesPage extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherCoursesPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  bool get _fr => locale.languageCode == 'fr';

  Future<void> _shareMedia(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateCoursePage(locale: locale, profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Médias des chapitres' : 'Chapter media'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EC),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.perm_media_outlined,
                    size: 44,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _fr ? 'Partager des médias par chapitre' : 'Share media by chapter',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _fr
                      ? 'Choisissez vos salles, la matière et le chapitre du programme, puis ajoutez des photos, PDF, vidéos ou audios. La rédaction des cours et la création des QCM restent réservées à l’administration.'
                      : 'Choose your classrooms, subject and curriculum chapter, then add photos, PDFs, videos or audio. Written lessons and quizzes are reserved for administrators.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _shareMedia(context),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_fr ? 'Ajouter des médias' : 'Add media'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
