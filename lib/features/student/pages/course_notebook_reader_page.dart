import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/rich_lesson_text.dart';
import '../../../models/chapter_learning_content.dart';

/// Lecteur de cahier : une page indépendante à la fois, avec navigation horizontale.
class CourseNotebookReaderPage extends StatefulWidget {
  const CourseNotebookReaderPage({
    super.key,
    required this.item,
    required this.locale,
  });

  final ChapterLearningContentItem item;
  final Locale locale;

  @override
  State<CourseNotebookReaderPage> createState() => _CourseNotebookReaderPageState();
}

class _CourseNotebookReaderPageState extends State<CourseNotebookReaderPage> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _en => widget.locale.languageCode == 'en';

  List<Map<String, dynamic>> get _pages {
    if (widget.item.pages.isNotEmpty) return widget.item.pages;
    final body = widget.item.bodyFor(widget.locale.languageCode) ??
        widget.item.bodyFor('fr') ?? '';
    return [
      {
        'blocks': [
          {'type': 'text', 'text_fr': body, 'text_en': body},
        ],
      },
    ];
  }

  Future<String?> _imageUrl(String path) async {
    try {
      return await Supabase.instance.client.storage
          .from('chapter-content')
          .createSignedUrl(path, 900);
    } catch (_) {
      return null;
    }
  }

  Widget _buildPage(Map<String, dynamic> page, int number) {
    final rawBlocks = page['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth - 28;
      final heightLimitedWidth = (constraints.maxHeight - 28) * 210 / 297;
      final width = (availableWidth < heightLimitedWidth ? availableWidth : heightLimitedWidth).clamp(200.0, 794.0).toDouble();
      return Center(
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.fromLTRB(30, 34, 30, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.item.titleFor(widget.locale.languageCode),
                      style: const TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w900, color: Color(0xFF14532D))),
                    const Divider(height: 28, color: Color(0xFF16A34A)),
                    for (final block in blocks) ...[
                      if (block['type'] == 'text')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: RichLessonText(
                            text: (block[_en ? 'text_en' : 'text_fr'] ?? block['text'] ?? '').toString(),
                            style: const TextStyle(fontSize: 15.5, height: 1.75, color: Color(0xFF1E293B)),
                          ),
                        ),
                      if (block['type'] == 'image' && (block['storage_path'] ?? '').toString().isNotEmpty)
                        FutureBuilder<String?>(
                          future: _imageUrl(block['storage_path'].toString()),
                          builder: (context, snapshot) => snapshot.data == null
                              ? const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator()))
                              : Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: InteractiveViewer(
                                    child: Image.network(snapshot.data!, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Text(_en ? 'Image unavailable' : 'Image indisponible')),
                                  ),
                                ),
                        ),
                    ],
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text('${_en ? 'Page' : 'Page'} $number / ${_pages.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.black45)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: const Color(0xFFE9EEE9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(widget.item.titleFor(widget.locale.languageCode)),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => _buildPage(pages[index], index + 1),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _index == 0 ? null : () => _controller.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('${_en ? 'Page' : 'Page'} ${_index + 1} / ${pages.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF166534))),
                  IconButton(
                    onPressed: _index >= pages.length - 1 ? null : () => _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
