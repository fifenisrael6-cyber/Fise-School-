import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/user_profile.dart';

/// Allows the assigned teacher to attach the PDF to an administrator's schedule.
/// The database trigger and Storage RLS prevent changes to the official calendar.
class TeacherEvaluationPublicationPage extends StatefulWidget {
  const TeacherEvaluationPublicationPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  final Locale locale;
  final UserProfile profile;

  @override
  State<TeacherEvaluationPublicationPage> createState() =>
      _TeacherEvaluationPublicationPageState();
}

class _TeacherEvaluationPublicationPageState
    extends State<TeacherEvaluationPublicationPage> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  String? _uploadingId;
  List<Map<String, dynamic>> _exams = [];

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      if (_db.auth.currentUser?.id != widget.profile.id) {
        throw StateError(_fr
            ? 'La session ne correspond pas au profil enseignant. Reconnectez-vous.'
            : 'The active session does not match this teacher profile. Sign in again.');
      }
      final rows = await _db
          .from('assignments')
          .select('id,teacher_id,class_id,subject_id,exam_id,title_fr,title_en,starts_at,due_at,results_publish_at,evaluation_file_path,evaluation_file_name,status')
          .eq('teacher_id', widget.profile.id)
          .not('exam_id', 'is', null)
          .inFilter('status', ['published', 'closed'])
          .order('starts_at');
      if (!mounted) return;
      setState(() {
        _exams = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _title(Map<String, dynamic> row) {
    final fr = row['title_fr']?.toString().trim() ?? '';
    final en = row['title_en']?.toString().trim() ?? '';
    return _fr ? (fr.isNotEmpty ? fr : en) : (en.isNotEmpty ? en : fr);
  }

  String _date(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return _fr ? 'Date non définie' : 'Date not set';
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _uploadPdf(Map<String, dynamic> exam) async {
    final user = _db.auth.currentUser;
    if (user == null || user.id != widget.profile.id) {
      _show(_fr ? 'Session expirée. Reconnectez-vous.' : 'Session expired. Sign in again.');
      return;
    }
    if ((exam['evaluation_file_path']?.toString() ?? '').trim().isNotEmpty) {
      _show(_fr ? 'Un PDF est déjà associé à cette évaluation. Contactez l’administration pour le remplacer.' : 'A PDF is already attached. Contact the administrator to replace it.');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _show(_fr ? 'Le fichier PDF est vide ou illisible.' : 'The PDF is empty or unreadable.');
      return;
    }
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${exam['id']}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    setState(() => _uploadingId = exam['id'].toString());
    var uploaded = false;
    try {
      await _db.storage.from('assignment-files').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
      );
      uploaded = true;
      await _db.from('assignments')
          .update({
            'evaluation_file_path': path,
            'evaluation_file_name': file.name,
          })
          .eq('id', exam['id'])
          .eq('teacher_id', widget.profile.id)
          .select('id')
          .single();
      _show(_fr ? 'Sujet PDF envoyé et associé au calendrier.' : 'PDF uploaded and attached to the exam schedule.');
      await _load();
    } catch (e) {
      if (uploaded) {
        try { await _db.storage.from('assignment-files').remove([path]); } catch (_) {}
      }
      _show((_fr ? 'Échec de publication du PDF : ' : 'PDF upload failed: ') + e.toString());
    } finally {
      if (mounted) setState(() => _uploadingId = null);
    }
  }

  void _show(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Publication des sujets officiels' : 'Official exam PDF publishing'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _exams.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                      _fr ? 'Aucune évaluation officielle ne vous est affectée pour le moment.' : 'No official exam has been assigned to you yet.',
                      textAlign: TextAlign.center,
                    )))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _exams.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final exam = _exams[index];
                          final id = exam['id'].toString();
                          final hasPdf = (exam['evaluation_file_path']?.toString() ?? '').trim().isNotEmpty;
                          final busy = _uploadingId == id;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Icon(hasPdf ? Icons.task_alt : Icons.picture_as_pdf_outlined,
                                      color: hasPdf ? Colors.green : Colors.orange, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_title(exam), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                                  ]),
                                  const SizedBox(height: 10),
                                  Text('${_fr ? 'Début' : 'Start'} : ${_date(exam['starts_at'])}'),
                                  Text('${_fr ? 'Fin' : 'End'} : ${_date(exam['due_at'])}'),
                                  Text('${_fr ? 'Résultats' : 'Results'} : ${_date(exam['results_publish_at'])}'),
                                  const SizedBox(height: 12),
                                  if (hasPdf)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.verified, color: Colors.green),
                                      title: Text(_fr ? 'Sujet PDF publié' : 'PDF published'),
                                      subtitle: Text(exam['evaluation_file_name']?.toString() ?? ''),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: busy ? null : () => _uploadPdf(exam),
                                        icon: busy
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.upload_file),
                                        label: Text(busy
                                            ? (_fr ? 'Envoi en cours…' : 'Uploading…')
                                            : (_fr ? 'Joindre le sujet PDF' : 'Attach exam PDF')),
                                      ),
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
