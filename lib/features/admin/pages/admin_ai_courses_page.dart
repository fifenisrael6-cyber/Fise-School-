import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAiCoursesPage extends StatefulWidget {
  final Locale locale;
  const AdminAiCoursesPage({super.key, required this.locale});

  @override
  State<AdminAiCoursesPage> createState() => _AdminAiCoursesPageState();
}

class _AdminAiCoursesPageState extends State<AdminAiCoursesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _classes = const [];
  Set<String> _selectedClasses = <String>{};
  List<Map<String, dynamic>> _drafts = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _quizBackfillProgress;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final classes = await _client.from('school_classes')
          .select('id,display_name,name,subsystem,sector')
          .eq('is_active', true).order('display_name');

      final drafts = await _client.from('courses')
          .select('id,title_fr,title_en,status,ai_generated,ai_generated_at,class_id,subject_id,school_classes(display_name,name),subjects(name_fr,name_en)')
          .eq('ai_generated', true).eq('status', 'draft').order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _classes = List<Map<String, dynamic>>.from(classes);
        _drafts = List<Map<String, dynamic>>.from(drafts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _generate() async {
    if (_selectedClasses.isEmpty) {
      _snack(_fr ? 'Sélectionne au moins une salle.' : 'Select at least one classroom.');
      return;
    }
    setState(() => _working = true);
    try {
      var more = true;
      var rounds = 0;
      while (more && rounds < 50) {
        rounds++;
        final response = await _client.functions.invoke('admin-ai-courses', body: {
          'action': 'generate',
          'class_ids': _selectedClasses.toList(),
        });
        if (response.data is! Map) throw Exception(_fr ? 'Réponse IA invalide.' : 'Invalid AI response.');
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['error'] is String) throw Exception(data['error']);
        final generated = (data['generated'] as num?)?.toInt() ?? 0;
        final remaining = (data['remaining'] as num?)?.toInt() ?? 0;
        if (generated == 0 || remaining == 0) more = false;
      }
      await _load();
      if (mounted) _snack(_fr ? 'Génération terminée. Les cours sont en brouillon et attendent ton autorisation.' : 'Generation finished. Courses are drafts and await your approval.');
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _approve(List<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Autoriser la publication ?' : 'Approve publication?'),
        content: Text(_fr ? 'Les cours sélectionnés deviendront visibles dans les salles choisies.' : 'Selected courses will become visible in the chosen classrooms.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Autoriser' : 'Approve')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _working = true);
    try {
      final response = await _client.functions.invoke('admin-ai-courses', body: {'action': 'approve', 'course_ids': ids});
      if (response.data is! Map) throw Exception(_fr ? 'Réponse invalide.' : 'Invalid response.');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] is String) throw Exception(data['error']);
      final chapterIds = data['chapter_ids'] is List
          ? (data['chapter_ids'] as List).map((v) => v.toString()).toSet().toList()
          : <String>[];
      final quizResult = await _generateAiQuizzes(chapterIds);
      final quizCount = quizResult['generated'] as int;
      final failures = quizResult['failed'] as List<String>;
      await _load();
      if (failures.isEmpty) {
        _snack(_fr
            ? 'Publication autorisée : ${data['approved'] ?? ids.length} cours publiés et $quizCount QCM IA générés.'
            : 'Publication approved: ${data['approved'] ?? ids.length} courses published and $quizCount AI quizzes generated.');
      } else {
        _snack(_fr
            ? 'Cours publiés. $quizCount QCM IA générés; ${failures.length} échec(s). Relancez la génération des QCM manquants.'
            : 'Courses published. $quizCount AI quizzes generated; ${failures.length} failed. Run the missing-quiz backfill again.');
      }
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<Map<String, dynamic>> _generateAiQuizzes(List<String> chapterIds) async {
    final ids = chapterIds.toSet().toList(growable: false);
    var generated = 0;
    final failed = <String>[];
    for (var i = 0; i < ids.length; i++) {
      if (!mounted) break;
      final chapterId = ids[i];
      setState(() {
        _quizBackfillProgress = _fr
            ? 'Génération des QCM IA : ${i + 1}/${ids.length}'
            : 'Generating AI quizzes: ${i + 1}/${ids.length}';
      });
      try {
        final response = await _client.functions.invoke(
          'chapter-quiz',
          body: {'chapter_id': chapterId},
        );
        if (response.data is! Map) {
          throw Exception(_fr ? 'Réponse QCM IA invalide.' : 'Invalid AI quiz response.');
        }
        final payload = Map<String, dynamic>.from(response.data as Map);
        if (payload['error'] is String) throw Exception(payload['error']);
        generated++;
      } catch (e) {
        failed.add('$chapterId: $e');
      }
    }
    if (mounted) setState(() => _quizBackfillProgress = null);
    return {'generated': generated, 'failed': failed};
  }

  Future<void> _backfillMissingQuizzes() async {
    setState(() { _working = true; _error = null; });
    try {
      final response = await _client.functions.invoke(
        'admin-ai-courses',
        body: {'action': 'missing_quizzes'},
      );
      if (response.data is! Map) {
        throw Exception(_fr ? 'Réponse serveur invalide.' : 'Invalid server response.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] is String) throw Exception(data['error']);
      final chapterIds = data['chapter_ids'] is List
          ? (data['chapter_ids'] as List).map((v) => v.toString()).toSet().toList()
          : <String>[];
      if (chapterIds.isEmpty) {
        _snack(_fr
            ? 'Tous les chapitres ayant un cours publié possèdent déjà un QCM IA, ou aucun cours publiable n’est associé à un chapitre.'
            : 'Published chapter courses already have AI quizzes, or no published course is linked to a chapter.');
        return;
      }
      final result = await _generateAiQuizzes(chapterIds);
      final generated = result['generated'] as int;
      final failures = result['failed'] as List<String>;
      await _load();
      _snack(_fr
          ? '$generated QCM IA générés sur ${chapterIds.length} chapitres. ${failures.length} échec(s).'
          : '$generated AI quizzes generated for ${chapterIds.length} chapters. ${failures.length} failed.');
    } catch (e) {
      if (mounted) _snack((_fr ? 'Génération IA impossible : ' : 'AI generation failed: ') + e.toString());
    } finally {
      if (mounted) setState(() { _working = false; _quizBackfillProgress = null; });
    }
  }

  String _className(Map<String, dynamic> row) {
    final raw = row['school_classes'];
    if (raw is! Map) return '';
    return raw['display_name']?.toString() ?? raw['name']?.toString() ?? '';
  }

  String _subjectName(Map<String, dynamic> row) {
    final raw = row['subjects'];
    if (raw is! Map) return '';
    final fr = raw['name_fr']?.toString() ?? '';
    final en = raw['name_en']?.toString() ?? '';
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _classes.isNotEmpty && _selectedClasses.length == _classes.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'IA pédagogique' : 'Teaching AI'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_fr ? 'Créer les cours selon les programmes' : 'Create courses from the programmes', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                              ]),
                              const SizedBox(height: 10),
                              Text(_fr ? 'Sélectionne une ou plusieurs salles. L’IA lit les matières, programmes et chapitres associés, puis prépare les cours. Rien n’est publié automatiquement.' : 'Select one or more classrooms. AI reads their subjects, programmes and chapters, then prepares the courses. Nothing is published automatically.'),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _working ? null : _backfillMissingQuizzes,
                                  icon: const Icon(Icons.quiz_outlined),
                                  label: Text(_fr
                                      ? 'Générer les QCM IA manquants des cours publiés'
                                      : 'Generate missing AI quizzes for published courses'),
                                ),
                              ),
                              if (_quizBackfillProgress != null) ...[
                                const SizedBox(height: 8),
                                Text(_quizBackfillProgress!, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: allSelected,
                                onChanged: _working ? null : (value) => setState(() {
                                  _selectedClasses = value == true ? _classes.map((c) => c['id'].toString()).toSet() : <String>{};
                                }),
                                title: Text(_fr ? 'Toutes les salles' : 'All classrooms'),
                              ),
                              const Divider(),
                              ..._classes.map((c) {
                                final id = c['id'].toString();
                                final name = c['display_name']?.toString() ?? c['name']?.toString() ?? '';
                                final details = (c['subsystem']?.toString() ?? '') + ' • ' + (c['sector']?.toString() ?? '');
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _selectedClasses.contains(id),
                                  onChanged: _working ? null : (value) => setState(() {
                                    final next = {..._selectedClasses};
                                    if (value == true) next.add(id); else next.remove(id);
                                    _selectedClasses = next;
                                  }),
                                  title: Text(name),
                                  subtitle: Text(details),
                                );
                              }),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _working ? null : _generate,
                                  icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                                  label: Text(_working ? (_fr ? 'L’IA travaille…' : 'AI is working…') : (_fr ? 'Générer les cours IA' : 'Generate AI courses')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(_fr ? 'Cours IA en attente de ton autorisation' : 'AI courses awaiting your approval', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      const SizedBox(height: 8),
                      if (_drafts.isEmpty)
                        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_fr ? 'Aucun brouillon IA en attente.' : 'No AI draft is waiting.')))
                      else ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.fact_check_rounded),
                            title: Text(_fr ? 'Tout autoriser' : 'Approve all'),
                            subtitle: Text(_drafts.length.toString() + ' cours'),
                            trailing: FilledButton(onPressed: _working ? null : () => _approve(_drafts.map((d) => d['id'].toString()).toList()), child: Text(_fr ? 'Autoriser' : 'Approve')),
                          ),
                        ),
                        ..._drafts.map((d) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.menu_book_rounded),
                            title: Text(_fr ? (d['title_fr']?.toString() ?? '') : (d['title_en']?.toString() ?? d['title_fr']?.toString() ?? '')),
                            subtitle: Text(_className(d) + ' • ' + _subjectName(d)),
                            trailing: IconButton(
                              tooltip: _fr ? 'Autoriser' : 'Approve',
                              onPressed: _working ? null : () => _approve([d['id'].toString()]),
                              icon: const Icon(Icons.check_circle_outline_rounded),
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
    );
  }
}
