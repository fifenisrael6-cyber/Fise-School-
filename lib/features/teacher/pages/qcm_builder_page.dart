import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/user_profile.dart';

/// Espace enseignant en lecture seule : les QCM de chapitre viennent de l'IA.
/// Il ne crée ni questions manuelles ni corrigés côté client.
class QcmBuilderPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const QcmBuilderPage({super.key, required this.locale, required this.profile});

  @override
  State<QcmBuilderPage> createState() => _QcmBuilderPageState();
}

class _QcmBuilderPageState extends State<QcmBuilderPage> {
  final SupabaseClient _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _future = _loadAiQuizzes();
  }

  Future<List<Map<String, dynamic>>> _loadAiQuizzes() async {
    final profileRow = await _db.from('profiles').select('teaching_stream').eq('id', widget.profile.id).maybeSingle();
    final rawStream = (profileRow?['teaching_stream'] ?? '').toString().toLowerCase().trim();
    final teacherStream = ['literary', 'litteraire', 'littéraire'].contains(rawStream)
        ? 'literary'
        : ['scientific', 'scientifique'].contains(rawStream) ? 'scientific' : null;
    if (teacherStream == null) return const <Map<String, dynamic>>[];

    final quizRows = await _db
        .from('chapter_quizzes')
        .select('id,title_fr,title_en,description_fr,description_en,chapter_id,position,is_published,created_by')
        .eq('is_published', true)
        .isFilter('created_by', null)
        .order('position');
    final quizzes = quizRows.map((r) => Map<String, dynamic>.from(r)).toList();
    if (quizzes.isEmpty) return const [];

    final chapterIds = quizzes.map((q) => q['chapter_id'].toString()).toSet().toList();
    final chapterRows = await _db
        .from('course_chapters')
        .select('id,title_fr,title_en,curriculum_id,position')
        .inFilter('id', chapterIds);
    final chapters = {for (final raw in chapterRows) raw['id'].toString(): Map<String, dynamic>.from(raw)};
    final curriculumIds = chapters.values
        .map((c) => c['curriculum_id'].toString())
        .toSet()
        .toList();
    final curriculumRows = curriculumIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _db.from('curricula').select('id,title_fr,title_en,subject_id').inFilter('id', curriculumIds))
            .map((r) => Map<String, dynamic>.from(r)).toList();
    final curricula = {for (final c in curriculumRows) c['id'].toString(): c};
    final subjectIds = curriculumRows
        .map((c) => c['subject_id'].toString())
        .where((id) => id.isNotEmpty && id != 'null')
        .toSet()
        .toList();
    final subjectRows = subjectIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _db.from('subjects').select('id,name_fr,name_en,teaching_stream').inFilter('id', subjectIds))
            .map((r) => Map<String, dynamic>.from(r)).toList();
    final subjects = {for (final s in subjectRows) s['id'].toString(): s};

    final output = <Map<String, dynamic>>[];
    for (final quiz in quizzes) {
      final chapter = chapters[quiz['chapter_id'].toString()];
      if (chapter == null) continue;
      final curriculum = curricula[chapter['curriculum_id'].toString()];
      final subject = curriculum == null ? null : subjects[curriculum['subject_id'].toString()];
      final subjectStream = (subject?['teaching_stream'] ?? 'both').toString().toLowerCase();
      if (teacherStream != null && !['both', teacherStream].contains(subjectStream)) continue;
      final questionRows = await _db
          .from('chapter_quiz_questions')
          .select('id')
          .eq('quiz_id', quiz['id']);
      output.add({
        'quiz': quiz,
        'chapter': chapter,
        'curriculum': curriculum,
        'subject': subject,
        'question_count': questionRows.length,
      });
    }
    return output;
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadAiQuizzes());
    try {
      await _future;
    } catch (_) {
      // FutureBuilder displays the load error.
    }
  }

  String _value(Map<String, dynamic>? row, String fr, String en) {
    if (row == null) return '';
    final preferred = row[widget.locale.languageCode == 'en' ? en : fr]?.toString().trim() ?? '';
    final alternate = row[widget.locale.languageCode == 'en' ? fr : en]?.toString().trim() ?? '';
    return preferred.isNotEmpty ? preferred : alternate;
  }

  Future<void> _preview(Map<String, dynamic> entry) async {
    final quiz = Map<String, dynamic>.from(entry['quiz'] as Map);
    try {
      final rows = await _db
          .from('chapter_quiz_questions')
          .select('id,position,prompt_fr,prompt_en,options_fr,options_en')
          .eq('quiz_id', quiz['id'])
          .order('position');
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _value(quiz, 'title_fr', 'title_en'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final q = Map<String, dynamic>.from(rows[index]);
                      final prompt = _value(q, 'prompt_fr', 'prompt_en');
                      final rawOptions = q[widget.locale.languageCode == 'en' ? 'options_en' : 'options_fr'];
                      final options = rawOptions is List ? rawOptions : const [];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${index + 1}. $prompt', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              for (var i = 0; i < options.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('${String.fromCharCode(65 + i)}. ${options[i]}'),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((_fr ? 'Aperçu indisponible : ' : 'Preview unavailable: ') + e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'QCM générés par l’IA' : 'AI-generated quizzes'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Actualiser' : 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    (_fr ? 'Impossible de charger les QCM IA. Vérifiez les droits Supabase puis actualisez.\n' : 'Unable to load AI quizzes. Check Supabase access, then refresh.\n') + '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            final entries = snapshot.data ?? const <Map<String, dynamic>>[];
            if (entries.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 60),
                  const Icon(Icons.auto_awesome_outlined, size: 56, color: Color(0xFF166534)),
                  const SizedBox(height: 16),
                  Text(
                    _fr ? 'Aucun QCM IA publié pour vos chapitres pour le moment.' : 'No AI-generated quiz is published for your chapters yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fr ? 'Les QCM sont créés automatiquement à la publication d’un cours écrit suffisamment complet. Revenez ici pour actualiser.' : 'Quizzes are generated automatically when a sufficiently complete written course is published. Refresh this page to check again.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final entry = entries[index];
                final quiz = Map<String, dynamic>.from(entry['quiz'] as Map);
                final chapter = Map<String, dynamic>.from(entry['chapter'] as Map);
                final curriculum = entry['curriculum'] is Map ? Map<String, dynamic>.from(entry['curriculum'] as Map) : null;
                final subject = entry['subject'] is Map ? Map<String, dynamic>.from(entry['subject'] as Map) : null;
                final subtitle = [
                  _value(subject, 'name_fr', 'name_en'),
                  _value(curriculum, 'title_fr', 'title_en'),
                  _value(chapter, 'title_fr', 'title_en'),
                  '${entry['question_count']} ${_fr ? 'questions' : 'questions'}',
                ].where((s) => s.trim().isNotEmpty).join(' · ');
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDCFCE7),
                      child: Icon(Icons.auto_awesome, color: Color(0xFF166534)),
                    ),
                    title: Text(_value(quiz, 'title_fr', 'title_en'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(subtitle),
                    ),
                    trailing: const Icon(Icons.visibility_outlined),
                    onTap: () => _preview(entry),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
