import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'subject_channel_page.dart';

/// Espace Cours de l'élève : les matières de sa salle, selon le programme du
/// Cameroun. Chaque matière ouvre son fil de cours, documents et QCM.
class CoursesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const CoursesPage({super.key, required this.locale, required this.profile});

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  final CourseService _service = CourseService();
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
    if (code.contains('math')) {
      return Icons.calculate_rounded;
    }
    if (code.contains('franc') || code.contains('french')) {
      return Icons.translate_rounded;
    }
    if (code.contains('angl') || code.contains('english')) {
      return Icons.language_rounded;
    }
    if (code.contains('hist')) {
      return Icons.history_edu_rounded;
    }
    if (code.contains('geo')) {
      return Icons.public_rounded;
    }
    if (code.contains('civ') || code.contains('citizen')) {
      return Icons.balance_rounded;
    }
    if (code.contains('science') || code.contains('phys') || code.contains('chim')) {
      return Icons.science_rounded;
    }
    if (code.contains('dessin') || code.contains('workshop') || code.contains('techno')) {
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

          if (snapshot.hasError) {
            return _Message(texts.pedagogyLoadError);
          }

          final entries = snapshot.data ?? const <ClassSubjectEntry>[];

          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _Message(
              _fr
                  ? 'Aucune matière n\u2019est encore associée à ta salle. Vérifie que tu as bien rejoint ta classe, puis tire l\u2019écran vers le bas pour actualiser.'
                  : 'No subject is linked to your class yet. Make sure you joined your class, then pull down to refresh.',
                    ),
                  ),
                ],
              ),
            );
          }

          final compulsory = entries.where((e) => e.isCompulsory).toList();
          final optional = entries.where((e) => !e.isCompulsory).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.school_rounded, color: Color(0xFF166534)),
                    title: Text(
                      widget.profile.className ?? (_fr ? 'Ma classe' : 'My class'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _fr
                          ? '${entries.length} matières de ton programme. Touche une matière pour voir les cours, documents et QCM.'
                          : '${entries.length} subjects in your programme. Tap a subject to see courses, documents and quizzes.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (compulsory.isNotEmpty)
                  _section(
                    context,
                    _fr ? 'Matières de base' : 'Core subjects',
                    compulsory,
                    0,
                  ),
                if (optional.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _section(
                    context,
                    _fr ? 'Matières optionnelles' : 'Optional subjects',
                    optional,
                    compulsory.length,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<ClassSubjectEntry> items,
    int colorOffset,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final entry = items[index];
            final color = _palette[(index + colorOffset) % _palette.length];
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectChannelPage(
                    locale: widget.locale,
                    profile: widget.profile,
                    subject: entry.subject,
                  ),
                ),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                padding: const EdgeInsets.all(14),
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
                  ],
                ),
              ),
            );
          },
        ),
      ],
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
