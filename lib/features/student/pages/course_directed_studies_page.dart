import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

class CourseDirectedStudiesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;

  const CourseDirectedStudiesPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
  });

  @override
  State<CourseDirectedStudiesPage> createState() => _CourseDirectedStudiesPageState();
}

class _CourseDirectedStudiesPageState extends State<CourseDirectedStudiesPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final db = Supabase.instance.client;
    final memberships = await db.from('class_students')
        .select('class_id')
        .eq('student_id', widget.profile.id)
        .eq('is_active', true);
    final classIds = memberships.map((row) => row['class_id'].toString()).toSet();
    if (classIds.isEmpty) return const [];
    final rows = await db.from('directed_studies')
        .select('id,course_id,source_class_id,subject_id,title,description,storage_path,file_name,target_class_ids,created_at')
        .eq('subject_id', widget.course.subjectId)
        .eq('status', 'published')
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).where((row) {
      final targets = (row['target_class_ids'] as List? ?? const [])
          .map((id) => id.toString()).toSet();
      return targets.intersection(classIds).isNotEmpty;
    }).toList(growable: false);
  }

  Future<void> _openFile(Map<String, dynamic> td) async {
    try {
      final url = await Supabase.instance.client.storage
          .from('directed-study-files')
          .createSignedUrl(td['storage_path'].toString(), 3600);
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fr ? 'Impossible d’ouvrir le PDF.' : 'Unable to open the PDF.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_fr ? 'Ouverture impossible' : 'Could not open'}: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Travaux dirigés' : 'Directed studies')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${_fr ? 'Impossible de charger les TD.' : 'Unable to load directed studies.'}\n${snapshot.error}', textAlign: TextAlign.center),
            ));
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.assignment_outlined, size: 58, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_fr ? 'Aucun travail dirigé publié pour ce cours.' : 'No directed studies published for this course.', textAlign: TextAlign.center),
              ]),
            ));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE4F2E9),
                    child: Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF166534)),
                  ),
                  title: Text(item['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text([
                    if ((item['description'] ?? '').toString().trim().isNotEmpty) item['description'].toString(),
                    item['file_name']?.toString() ?? 'PDF',
                  ].join('\n')),
                  isThreeLine: (item['description'] ?? '').toString().trim().isNotEmpty,
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () => _openFile(item),
                ));
              },
            ),
          );
        },
      ),
    );
  }
}
