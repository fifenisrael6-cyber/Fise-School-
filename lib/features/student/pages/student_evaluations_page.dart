import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/user_profile.dart';

/// Calendar of official exams. Supabase RLS limits this list to the student's
/// real classroom (and compatible general classes); the PDF is time-gated too.
class StudentEvaluationsPage extends StatefulWidget {
  const StudentEvaluationsPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  final Locale locale;
  final UserProfile profile;

  @override
  State<StudentEvaluationsPage> createState() => _StudentEvaluationsPageState();
}

class _StudentEvaluationsPageState extends State<StudentEvaluationsPage> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, Map<String, dynamic>> _exams = {};
  Map<String, Map<String, dynamic>> _subjects = {};
  Map<String, Map<String, dynamic>> _classes = {};
  String? _openingId;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait<dynamic>([
        _db.from('assignments')
            .select('id,title_fr,title_en,instructions_fr,instructions_en,class_id,subject_id,exam_id,starts_at,due_at,results_publish_at,evaluation_file_path,evaluation_file_name,status')
            .not('exam_id', 'is', null)
            .inFilter('status', ['published', 'closed'])
            .order('starts_at'),
        _db.from('exams').select('id,name_fr,name_en'),
        _db.from('subjects').select('id,name_fr,name_en'),
        _db.from('school_classes').select('id,display_name,name'),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = (results[0] as List).map((r) => Map<String, dynamic>.from(r)).toList();
        _exams = {for (final r in results[1] as List) r['id'].toString(): Map<String, dynamic>.from(r)};
        _subjects = {for (final r in results[2] as List) r['id'].toString(): Map<String, dynamic>.from(r)};
        _classes = {for (final r in results[3] as List) r['id'].toString(): Map<String, dynamic>.from(r)};
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _label(Map<String, dynamic>? row, String frKey, String enKey) {
    if (row == null) return '';
    final first = row[_fr ? frKey : enKey]?.toString().trim() ?? '';
    final other = row[_fr ? enKey : frKey]?.toString().trim() ?? '';
    return first.isNotEmpty ? first : other;
  }

  DateTime? _parse(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

  String _date(dynamic value) {
    final parsed = _parse(value);
    if (parsed == null) return _fr ? 'Date non définie' : 'Date not set';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _title(Map<String, dynamic> row) {
    final value = _label(row, 'title_fr', 'title_en');
    if (value.isNotEmpty) return value;
    final exam = _label(_exams[row['exam_id']?.toString()], 'name_fr', 'name_en');
    final subject = _label(_subjects[row['subject_id']?.toString()], 'name_fr', 'name_en');
    return [exam, subject].where((v) => v.isNotEmpty).join(' — ');
  }

  bool _isOpen(Map<String, dynamic> row) {
    final start = _parse(row['starts_at']);
    final end = _parse(row['due_at']);
    final now = DateTime.now();
    return start != null && end != null && !now.isBefore(start) && now.isBefore(end);
  }

  String _state(Map<String, dynamic> row) {
    final start = _parse(row['starts_at']);
    final end = _parse(row['due_at']);
    final now = DateTime.now();
    if (start != null && now.isBefore(start)) return _fr ? 'À venir' : 'Upcoming';
    if (end != null && !now.isBefore(end)) return _fr ? 'Épreuve terminée' : 'Exam ended';
    return _fr ? 'En cours' : 'In progress';
  }

  Future<void> _openPdf(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final path = row['evaluation_file_path']?.toString() ?? '';
    if (path.trim().isEmpty) {
      _show(_fr ? 'Le PDF n’a pas encore été ajouté par l’enseignant.' : 'The teacher has not attached the PDF yet.');
      return;
    }
    if (!_isOpen(row)) {
      _show(_fr ? 'Le sujet protégé est accessible uniquement pendant la période de l’épreuve.' : 'The protected paper is available only during the scheduled exam window.');
      return;
    }
    setState(() => _openingId = id);
    try {
      final signed = await _db.storage.from('assignment-files').createSignedUrl(path, 180);
      final opened = await launchUrl(Uri.parse(signed), mode: LaunchMode.externalApplication);
      if (!opened) throw StateError(_fr ? 'Impossible d’ouvrir le PDF.' : 'Unable to open the PDF.');
    } catch (e) {
      _show((_fr ? 'Sujet inaccessible : ' : 'Paper unavailable: ') + e.toString());
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Calendrier des évaluations' : 'Exam schedule'),
        actions: [IconButton(onPressed: _load, tooltip: _fr ? 'Actualiser' : 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _rows.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                      _fr ? 'Aucune évaluation officielle programmée pour vos salles.' : 'No official exams are scheduled for your classrooms.',
                      textAlign: TextAlign.center,
                    )))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final row = _rows[index];
                          final subject = _label(_subjects[row['subject_id']?.toString()], 'name_fr', 'name_en');
                          final schoolClass = _classes[row['class_id']?.toString()];
                          final className = schoolClass?['display_name']?.toString() ?? schoolClass?['name']?.toString() ?? '';
                          final hasPdf = (row['evaluation_file_path']?.toString() ?? '').trim().isNotEmpty;
                          final isOpen = _isOpen(row);
                          final busy = _openingId == row['id'].toString();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    CircleAvatar(
                                      backgroundColor: const Color(0xFFE4F2E9),
                                      child: Icon(Icons.event_note, color: const Color(0xFF166534)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_title(row), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                                  ]),
                                  const SizedBox(height: 10),
                                  if (className.isNotEmpty) Text('${_fr ? 'Classe' : 'Class'} : $className'),
                                  if (subject.isNotEmpty) Text('${_fr ? 'Matière' : 'Subject'} : $subject'),
                                  const SizedBox(height: 6),
                                  Text('${_fr ? 'Début' : 'Starts'} : ${_date(row['starts_at'])}'),
                                  Text('${_fr ? 'Fin' : 'Ends'} : ${_date(row['due_at'])}'),
                                  Text('${_fr ? 'Résultats' : 'Results'} : ${_date(row['results_publish_at'])}'),
                                  const SizedBox(height: 10),
                                  Chip(
                                    avatar: Icon(isOpen ? Icons.play_circle_outline : Icons.schedule, size: 18),
                                    label: Text(_state(row)),
                                  ),
                                  if (hasPdf)
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: busy ? null : () => _openPdf(row),
                                        icon: busy
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.picture_as_pdf_outlined),
                                        label: Text(busy ? (_fr ? 'Ouverture…' : 'Opening…') : (_fr ? 'Ouvrir le sujet PDF' : 'Open exam PDF')),
                                      ),
                                    )
                                  else
                                    Text(
                                      _fr ? 'Sujet PDF en attente de publication par l’enseignant.' : 'The teacher has not published the exam PDF yet.',
                                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                                    ),
                                  if (hasPdf && !isOpen)
                                    Text(
                                      _fr ? 'Le PDF sera accessible uniquement pendant la période programmée.' : 'The PDF is available only during the scheduled window.',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
