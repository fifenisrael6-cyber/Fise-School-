import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/search_service.dart';
import '../../../models/search_result.dart';

class SearchPage extends StatefulWidget {
  final Locale locale;
  final SearchService? searchService;

  const SearchPage({super.key, required this.locale, this.searchService});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  late final SearchService _service = widget.searchService ?? SearchService();
  Future<List<SearchResult>>? _future;

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.search)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: texts.search,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 20),
            Expanded(child: _results(texts)),
          ],
        ),
      ),
    );
  }

  Widget _results(AppTexts texts) {
    final future = _future;

    if (future == null) {
      return Center(child: Text(texts.searchHint));
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

        final results = snapshot.data ?? const <SearchResult>[];

        if (results.isEmpty) {
          return Center(child: Text(texts.noSearchResults));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (_, index) => ListTile(
            leading: Icon(_iconFor(results[index].type)),
            title: Text(results[index].title),
            subtitle: Text(results[index].subtitle ?? ''),
          ),
        );
      },
    );
  }

  void _search() {
    setState(() => _future = _service.search(_controller.text));
  }

  IconData _iconFor(SearchResultType type) => switch (type) {
    SearchResultType.exam => Icons.verified,
    SearchResultType.classItem => Icons.school,
    SearchResultType.subject => Icons.category_outlined,
    SearchResultType.course => Icons.menu_book_outlined,
    SearchResultType.lesson => Icons.play_lesson_outlined,
  };
}
