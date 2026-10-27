import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/json_cache.dart';
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
  final CourseOfflineService _offline = CourseOfflineService();
  bool get _fr => widget.locale.languageCode == 'fr';
  String get _cacheKey => 'directed_studies_${widget.profile.id}_${widget.course.id}';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  List<Map<String, dynamic>> _decodeRows(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _load({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await JsonCache.instance.read(_cacheKey);
      if (cached is List) {
        // Affiche le dernier état enregistré tout de suite. Le rafraîchissement
        // réseau se fait ensuite sans bloquer l'ouverture du dossier TD.
        unawaited(_refreshFromServer());
        return _decodeRows(cached);
      }
    }
    return _fetchAndCache();
  }

  Future<void> _refreshFromServer() async {
    try {
      final rows = await _fetchAndCache();
      if (mounted) setState(() => _future = Future.value(rows));
    } catch (_) {
      // Keep the last local copy visible when offline.
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAndCache() async {
    final db = Supabase.instance.client;
    final memberships = await db.from('class_students')
        .select('class_id')
        .eq('student_id', widget.profile.id)
        .eq('is_active', true)
        .timeout(const Duration(seconds: 8));
    final classIds = memberships.map((row) => row['class_id'].toString()).toSet();
    if (classIds.isEmpty) {
      await JsonCache.instance.write(_cacheKey, const []);
      return const [];
    }
    final rows = await db.from('directed_studies')
        .select('id,course_id,source_class_id,subject_id,title,description,storage_path,file_name,target_class_ids,created_at')
        .eq('subject_id', widget.course.subjectId)
        .eq('status', 'published')
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 8));
    final result = rows.map((row) => Map<String, dynamic>.from(row)).where((row) {
      final targets = (row['target_class_ids'] as List? ?? const [])
          .map((id) => id.toString()).toSet();
      return targets.intersection(classIds).isNotEmpty;
    }).toList(growable: false);
    await JsonCache.instance.write(_cacheKey, result);
    return result;
  }

  Future<void> _openFile(Map<String, dynamic> td) async {
    final id = td['id']?.toString() ?? '';
    final storagePath = td['storage_path']?.toString() ?? '';
    final fileName = td['file_name']?.toString().trim().isNotEmpty == true
        ? td['file_name'].toString()
        : 'travaux_diriges.pdf';
    if (id.isEmpty || storagePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_fr ? 'Le chemin du fichier est invalide.' : 'The file path is invalid.'),
        ));
      }
      return;
    }
    try {
      final localPath = await _offline.openExternalFile(
        userId: widget.profile.id,
        resourceId: 'directed-study-$id',
        courseId: widget.course.id,
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () => Supabase.instance.client.storage
            .from('directed-study-files')
            .createSignedUrl(storagePath, 3600),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _DirectedStudyPdfPage(path: localPath, title: fileName),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_fr ? 'Ouverture impossible' : 'Could not open'}: $error'),
        ));
      }
    }
  }

  Future<void> _refresh() async {
    final next = _load(forceRefresh: true);
    setState(() => _future = next);
    await next;
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
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.65,
                    child: Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.assignment_outlined, size: 58, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_fr ? 'Aucun travail dirigé publié pour ce cours.' : 'No directed studies published for this course.', textAlign: TextAlign.center),
                      ]),
                    )),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
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

class _DirectedStudyPdfPage extends StatefulWidget {
  const _DirectedStudyPdfPage({required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<_DirectedStudyPdfPage> createState() => _DirectedStudyPdfPageState();
}

class _DirectedStudyPdfPageState extends State<_DirectedStudyPdfPage> {
  PdfControllerPinch? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _controller = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
    } catch (_) {
      _failed = true;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: _failed
        ? const Center(child: Icon(Icons.error_outline_rounded, size: 56))
        : _controller == null
            ? const Center(child: CircularProgressIndicator())
            : PdfViewPinch(controller: _controller!),
  );
}
