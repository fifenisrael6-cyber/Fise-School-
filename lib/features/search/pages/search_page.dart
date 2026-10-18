import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/search_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/search_result.dart';
import '../../../models/user_profile.dart';
import '../../forum/pages/forum_page.dart';
import '../../student/pages/assignments_page.dart';
import '../../student/pages/course_detail_page.dart';
import '../../student/pages/lesson_page.dart';
import '../../student/pages/past_papers_page.dart';

enum _Filter { all, courses, files, papers, assignments, forum, catalogue }

class SearchPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final SearchService? searchService;

  const SearchPage({
    super.key,
    required this.locale,
    required this.profile,
    this.searchService,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  late final SearchService _service = widget.searchService ?? SearchService();
  Timer? _debounce;
  Future<List<SearchResult>>? _future;
  _Filter _filter = _Filter.all;

  bool get _en => widget.locale.languageCode == 'en';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.search)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: texts.search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _future = null);
                        },
                      ),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_filterLabel(f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _results(texts)),
          ],
        ),
      ),
    );
  }

  String _filterLabel(_Filter f) => switch (f) {
    _Filter.all => _en ? 'All' : 'Tout',
    _Filter.courses => _en ? 'Courses' : 'Cours',
    _Filter.files => _en ? 'Files' : 'Fichiers',
    _Filter.papers => _en ? 'Past papers' : 'Annales',
    _Filter.assignments => _en ? 'Assignments' : 'Devoirs',
    _Filter.forum => 'Forum',
    _Filter.catalogue => 'Catalogue',
  };

  bool _matches(SearchResultType type) => switch (_filter) {
    _Filter.all => true,
    _Filter.courses =>
      type == SearchResultType.course ||
          type == SearchResultType.lesson ||
          type == SearchResultType.chapter ||
          type == SearchResultType.chapterContent,
    _Filter.files =>
      type == SearchResultType.resource ||
          type == SearchResultType.fileContent ||
          type == SearchResultType.chapterContent,
    _Filter.papers => type == SearchResultType.pastPaper,
    _Filter.assignments => type == SearchResultType.assignment,
    _Filter.forum => type == SearchResultType.forum,
    _Filter.catalogue =>
      type == SearchResultType.exam ||
          type == SearchResultType.classItem ||
          type == SearchResultType.subject,
  };

  Widget _results(AppTexts texts) {
    final future = _future;

    if (future == null) {
      return Center(child: Text(texts.searchHint, textAlign: TextAlign.center));
    }

    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text(texts.searchError));
        }

        final results = (snapshot.data ?? const <SearchResult>[])
            .where((r) => _matches(r.type))
            .toList();

        if (results.isEmpty) {
          return Center(child: Text(texts.noSearchResults));
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: results.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) => _tile(results[index]),
        );
      },
    );
  }

  Widget _tile(SearchResult r) {
    final sub = [
      _typeLabel(r.type),
      if (r.subtitle != null) r.subtitle!,
    ].join(' · ');
    return ListTile(
      leading: Icon(_iconFor(r.type)),
      title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sub, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (r.snippet != null)
            Text(r.snippet!, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
      isThreeLine: r.snippet != null,
      trailing: _canOpen(r) ? const Icon(Icons.chevron_right) : null,
      onTap: _canOpen(r) ? () => _open(r) : null,
    );
  }

  bool _canOpen(SearchResult r) => switch (r.type) {
    SearchResultType.course ||
    SearchResultType.lesson ||
    SearchResultType.resource ||
    SearchResultType.fileContent => r.courseId != null,
    SearchResultType.pastPaper ||
    SearchResultType.assignment ||
    SearchResultType.forum => true,
    _ => false,
  };

  Future<void> _open(SearchResult r) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (r.type) {
        case SearchResultType.course:
        case SearchResultType.resource:
        case SearchResultType.fileContent:
          final course = await _loadCourse(r.courseId!);
          if (!mounted) return;
          navigator.push(
            MaterialPageRoute(
              builder: (_) => CourseDetailPage(
                locale: widget.locale,
                profile: widget.profile,
                course: course,
              ),
            ),
          );
        case SearchResultType.lesson:
          final course = await _loadCourse(r.courseId!);
          final row = await Supabase.instance.client
              .from('lessons')
              .select()
              .eq('id', r.lessonId ?? r.id)
              .single();
          if (!mounted) return;
          navigator.push(
            MaterialPageRoute(
              builder: (_) => LessonPage(
                locale: widget.locale,
                profile: widget.profile,
                course: course,
                lesson: Lesson.fromMap(Map<String, dynamic>.from(row)),
              ),
            ),
          );
        case SearchResultType.pastPaper:
          navigator.push(
            MaterialPageRoute(
              builder: (_) => PastPapersPage(
                locale: widget.locale,
                profile: widget.profile,
              ),
            ),
          );
        case SearchResultType.assignment:
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AssignmentsPage(
                locale: widget.locale,
                profile: widget.profile,
              ),
            ),
          );
        case SearchResultType.forum:
          navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  ForumPage(locale: widget.locale, profile: widget.profile),
            ),
          );
        default:
          break;
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _en
                ? 'This item could not be opened.'
                : 'Impossible d’ouvrir cet élément.',
          ),
        ),
      );
    }
  }

  Future<Course> _loadCourse(String id) async {
    final row = await Supabase.instance.client
        .from('courses')
        .select()
        .eq('id', id)
        .single();
    return Course.fromMap(Map<String, dynamic>.from(row));
  }

  String _typeLabel(SearchResultType t) => switch (t) {
    SearchResultType.exam => _en ? 'Exam' : 'Examen',
    SearchResultType.classItem => _en ? 'Class' : 'Classe',
    SearchResultType.subject => _en ? 'Subject' : 'Matière',
    SearchResultType.course => _en ? 'Course' : 'Cours',
    SearchResultType.lesson => _en ? 'Lesson' : 'Leçon',
    SearchResultType.chapter => _en ? 'Chapter' : 'Chapitre',
    SearchResultType.chapterContent =>
      _en ? 'Chapter content' : 'Contenu de chapitre',
    SearchResultType.resource => _en ? 'File' : 'Fichier',
    SearchResultType.fileContent =>
      _en ? 'Inside a file' : 'Dans un fichier',
    SearchResultType.pastPaper => _en ? 'Past paper' : 'Annale',
    SearchResultType.assignment => _en ? 'Assignment' : 'Devoir',
    SearchResultType.forum => 'Forum',
  };

  IconData _iconFor(SearchResultType type) => switch (type) {
    SearchResultType.exam => Icons.verified,
    SearchResultType.classItem => Icons.school,
    SearchResultType.subject => Icons.category_outlined,
    SearchResultType.course => Icons.menu_book_outlined,
    SearchResultType.lesson => Icons.play_lesson_outlined,
    SearchResultType.chapter => Icons.bookmark_outline,
    SearchResultType.chapterContent => Icons.article_outlined,
    SearchResultType.resource => Icons.attach_file,
    SearchResultType.fileContent => Icons.find_in_page_outlined,
    SearchResultType.pastPaper => Icons.description_outlined,
    SearchResultType.assignment => Icons.assignment_outlined,
    SearchResultType.forum => Icons.forum_outlined,
  };

  void _onChanged(String value) {
    setState(() {}); // met à jour le bouton d'effacement
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _future = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  void _search() {
    _debounce?.cancel();
    final text = _controller.text;
    if (text.trim().length < 2) return;
    setState(() => _future = _service.search(text));
  }
}
