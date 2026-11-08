import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/json_cache.dart';
import '../../../models/chapter_learning_content.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

/// Supabase-backed list of published chapter TD PDFs. RLS remains authoritative
/// for classroom visibility; the local cache only stores rows returned by RLS.
class ChapterTdPdfsPage extends StatefulWidget {
  const ChapterTdPdfsPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.subject,
    required this.chapters,
  });

  final Locale locale;
  final UserProfile profile;
  final Subject subject;
  final List<CourseChapter> chapters;

  @override
  State<ChapterTdPdfsPage> createState() => _ChapterTdPdfsPageState();
}

class _ChapterTdPdfsPageState extends State<ChapterTdPdfsPage> {
  final _offline = CourseOfflineService();
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _rows;
  String? _chapterId;

  bool get _en => widget.locale.languageCode == 'en';
  String get _cacheKey => 'chapter_td_pdf_${widget.profile.id}_${widget.subject.id}';

  @override
  void initState() {
    super.initState();
    _rows = _load();
    _search.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load({bool refresh = false}) async {
    if (!refresh) {
      final cached = await JsonCache.instance.read(_cacheKey);
      if (cached is List) {
        unawaited(_refreshInBackground());
        return cached.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      }
    }
    return _fetch();
  }

  Future<void> _refreshInBackground() async {
    try {
      final fresh = await _fetch();
      if (mounted) setState(() => _rows = Future.value(fresh));
    } catch (_) {
      // Preserve the last RLS-filtered local snapshot while offline.
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final result = await Supabase.instance.client
        .from('directed_studies')
        .select('id,course_id,chapter_id,source_class_id,subject_id,title,description,storage_path,file_name,status,created_at,published_at,target_class_ids,courses(title_fr,title_en,chapter_id),school_classes(display_name,name),subjects(name_fr,name_en)')
        .eq('subject_id', widget.subject.id)
        .eq('status', 'published')
        .order('published_at', ascending: false)
        .timeout(const Duration(seconds: 8));
    final rows = result.map((row) => Map<String, dynamic>.from(row)).toList();
    await JsonCache.instance.write(_cacheKey, rows);
    return rows;
  }

  String _rowChapterId(Map<String, dynamic> row) {
    final direct = row['chapter_id']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final course = row['courses'];
    return course is Map ? (course['chapter_id']?.toString() ?? '') : '';
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    final query = _search.text.trim().toLowerCase();
    return rows.where((row) {
      final chapter = _rowChapterId(row);
      if (_chapterId != null && chapter != _chapterId) return false;
      if (query.isEmpty) return true;
      final course = row['courses'];
      final subject = row['subjects'];
      final haystack = [
        row['title'], row['description'], row['file_name'],
        if (course is Map) course['title_fr'],
        if (subject is Map) subject['name_fr'], subject['name_en'],
        widget.chapters.where((item) => item.id == chapter).firstOrNull?.labelFor(widget.locale.languageCode),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    final courseId = row['course_id']?.toString() ?? '';
    final storagePath = row['storage_path']?.toString() ?? '';
    final fileName = row['file_name']?.toString() ?? 'TD.pdf';
    if (id.isEmpty || courseId.isEmpty || storagePath.isEmpty) return;
    try {
      final path = await _offline.openExternalFile(
        userId: widget.profile.id,
        resourceId: 'directed-study-$id',
        courseId: courseId,
        fileName: fileName,
        mimeType: 'application/pdf',
        signedUrlProvider: () => Supabase.instance.client.storage
            .from('directed-study-files').createSignedUrl(storagePath, 3600),
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _TdPdfViewer(path: path, title: row['title']?.toString() ?? fileName),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_en ? 'PDF unavailable. Download it while online. ($error)' : 'PDF indisponible. Téléchargez-le avec Internet. ($error)'),
      ));
    }
  }

  Future<void> _refresh() async {
    final next = _load(refresh: true);
    setState(() => _rows = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8F6),
    appBar: AppBar(
      backgroundColor: const Color(0xFF166534), foregroundColor: Colors.white,
      title: Text(_en ? 'Chapter TD PDFs' : 'TD PDF par chapitre'),
      actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(child: Text(_en ? 'Unable to load TDs. Check connection and retry.' : 'Chargement impossible. Vérifiez la connexion et réessayez.'));
        }
        final all = snapshot.data ?? const <Map<String, dynamic>>[];
        final items = _filtered(all);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: _en ? 'Search TDs' : 'Rechercher un TD', border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: _chapterId,
                decoration: InputDecoration(labelText: _en ? 'Chapter' : 'Chapitre'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(_en ? 'All chapters' : 'Tous les chapitres')),
                  ...widget.chapters.map((chapter) => DropdownMenuItem<String?>(value: chapter.id, child: Text(chapter.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => setState(() => _chapterId = value),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 56),
                  child: Column(children: [
                    const Icon(Icons.assignment_outlined, size: 52, color: Color(0xFF166534)),
                    const SizedBox(height: 12),
                    Text(_en ? 'No published TD PDF for this subject or chapter.' : 'Aucun TD PDF publié pour cette matière ou ce chapitre.', textAlign: TextAlign.center),
                    Text(_en ? 'Downloaded TDs remain available offline.' : 'Les TD téléchargés restent disponibles hors ligne.', style: const TextStyle(color: Colors.black54)),
                  ]),
                )
              else
                ...items.map((row) {
                  final chapterId = _rowChapterId(row);
                  final chapterName = widget.chapters.where((item) => item.id == chapterId).firstOrNull?.labelFor(widget.locale.languageCode) ?? (_en ? 'Chapter not specified' : 'Chapitre non précisé');
                  final published = DateTime.tryParse((row['published_at'] ?? row['created_at'] ?? '').toString());
                  final instructions = row['description']?.toString().trim() ?? '';
                  return Card(child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFFE4F2E9), child: Icon(Icons.picture_as_pdf, color: Color(0xFF166534))),
                    title: Text(row['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      widget.subject.labelFor(widget.locale.languageCode), chapterName,
                      if (published != null) '${published.day}/${published.month}/${published.year}',
                      if (instructions.isNotEmpty) instructions,
                    ].join(' • '), maxLines: 4, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.download_for_offline_outlined),
                    onTap: () => _open(row),
                  ));
                }),
            ],
          ),
        );
      },
    ),
  );
}

class _TdPdfViewer extends StatefulWidget {
  const _TdPdfViewer({required this.path, required this.title});
  final String path;
  final String title;
  @override
  State<_TdPdfViewer> createState() => _TdPdfViewerState();
}

class _TdPdfViewerState extends State<_TdPdfViewer> {
  late final PdfControllerPinch _controller = PdfControllerPinch(document: PdfDocument.openFile(widget.path));
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: PdfViewPinch(controller: _controller),
  );
}
