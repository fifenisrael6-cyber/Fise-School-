import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/chapter_learning_service.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'chapter_learning_subject_page.dart';
import 'subject_channel_page.dart';

/// Espace Cours de l'élève : matières affectées à sa classe active.
class CoursesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const CoursesPage({super.key, required this.locale, required this.profile});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final CourseService _service = CourseService();
  final ChapterLearningService _learning = ChapterLearningService();
  late Future<List<ClassSubjectEntry>> _subjectsFuture;

  static const _palette = <Color>[
    Color(0xFF166534),
    Color(0xFF1D4ED8),
    Color(0xFFB45309),
    Color(0xFF7C3AED),
    Color(0xFFBE123C),
    Color(0xFF0E7490),
  ];

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _subjectsFuture = _service.listClassSubjects(widget.profile);
  }

  Future<void> _refresh() async {
    setState(() => _subjectsFuture = _service.listClassSubjects(widget.profile));
    await _subjectsFuture;
  }

  IconData _iconFor(Subject subject) {
    final code = subject.code.toLowerCase();
    if (code.contains('math')) return Icons.calculate_rounded;
    if (code.contains('franc') || code.contains('french')) {
      return Icons.translate_rounded;
    }
    if (code.contains('angl') || code.contains('english')) {
      return Icons.language_rounded;
    }
    if (code.contains('hist')) return Icons.history_edu_rounded;
    if (code.contains('geo')) return Icons.public_rounded;
    if (code.contains('civ') || code.contains('citizen')) {
      return Icons.balance_rounded;
    }
    if (code.contains('science') ||
        code.contains('phys') ||
        code.contains('chim')) {
      return Icons.science_rounded;
    }
    if (code.contains('dessin') ||
        code.contains('workshop') ||
        code.contains('techno')) {
      return Icons.construction_rounded;
    }
    return Icons.menu_book_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.courses)),
      body: FutureBuilder<List<ClassSubjectEntry>>(
        future: _subjectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _Message(texts.pedagogyLoadError);

          final entries = snapshot.data ?? const <ClassSubjectEntry>[];
          if (entries.isEmpty) return _Message(texts.noCoursesYet);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.school_rounded,
                        color: Color(0xFF166534)),
                    title: Text(
                      widget.profile.className ??
                          (_fr ? 'Ma classe' : 'My class'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _fr
                          ? 'Choisis une matière pour consulter les chapitres du programme MINESEC et leurs contenus.'
                          : 'Choose a subject to browse MINESEC programme chapters and their resources.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final color = _palette[index % _palette.length];
                    return Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChapterLearningSubjectPage(
                                    locale: widget.locale,
                                    profile: widget.profile,
                                    subject: entry.subject,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: color,
                                      child: Icon(_iconFor(entry.subject), color: Colors.white),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      entry.subject.labelFor(widget.locale.languageCode),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 6),
                                    FutureBuilder<int>(
                                      future: _learning.countChaptersForSubject(entry.subject.id, profile: widget.profile),
                                      builder: (context, countSnapshot) {
                                        final count = countSnapshot.data;
                                        return Text(
                                          countSnapshot.connectionState == ConnectionState.waiting
                                              ? (_fr ? 'Chargement…' : 'Loading…')
                                              : '${count ?? 0} ${_fr ? 'chapitres' : 'chapters'}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SubjectChannelPage(
                                    locale: widget.locale,
                                    profile: widget.profile,
                                    subject: entry.subject,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline, size: 16),
                              label: Text(
                                _fr ? 'Cours et échanges' : 'Course feed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;

  const _Message(this.message);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
}
