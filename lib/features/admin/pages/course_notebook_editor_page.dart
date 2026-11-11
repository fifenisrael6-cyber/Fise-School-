import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/rich_lesson_text.dart';
import '../../../core/offline/notebook_page_pagination.dart';

/// Éditeur de cahier : chaque page est indépendante et prévisualisable au format A4.
class CourseNotebookEditorPage extends StatefulWidget {
  const CourseNotebookEditorPage({
    super.key,
    required this.locale,
    required this.chapterId,
    this.existingItem,
    this.existingCourse,
    this.courseContext,
  });

  final Locale locale;
  final String chapterId;
  final Map<String, dynamic>? existingItem;
  final Map<String, dynamic>? existingCourse;
  final Map<String, dynamic>? courseContext;

  @override
  State<CourseNotebookEditorPage> createState() => _CourseNotebookEditorPageState();
}

class _NotebookPage {
  _NotebookPage({
    String text = '',
    String textEn = '',
    List<Map<String, dynamic>>? images,
  })  : text = TextEditingController(text: text),
        textEn = TextEditingController(text: textEn),
        images = images ?? <Map<String, dynamic>>[];

  final TextEditingController text;
  final TextEditingController textEn;
  final List<Map<String, dynamic>> images;

  void dispose() {
    text.dispose();
    textEn.dispose();
  }
}

class _CourseNotebookEditorPageState extends State<CourseNotebookEditorPage> {
  final SupabaseClient _db = Supabase.instance.client;
  final TextEditingController _titleFr = TextEditingController();
  final TextEditingController _titleEn = TextEditingController();
  final PageController _previewController = PageController();
  final List<_NotebookPage> _pages = [];
  bool _preview = false;
  bool _published = false;
  bool _saving = false;
  int _previewIndex = 0;
  String? _error;

  bool get _fr => widget.locale.languageCode == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem ?? widget.existingCourse;
    if (item != null) {
      _titleFr.text = item['title_fr']?.toString() ?? '';
      _titleEn.text = item['title_en']?.toString() ?? '';
      _published = item['is_published'] == true || item['status'] == 'published';
      final rawPages = item['pages_json'];
      if (rawPages is List) {
        final savedPages = rawPages
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList(growable: false);
        for (final page in NotebookPagePagination.expandLegacyPages(savedPages)) {
          final blocks = page['blocks'];
          String text = '';
          String textEn = '';
          final images = <Map<String, dynamic>>[];
          if (blocks is List) {
            for (final rawBlock in blocks.whereType<Map>()) {
              final block = Map<String, dynamic>.from(rawBlock);
              if (block['type'] == 'text') {
                text = (block['text_fr'] ?? block['text'] ?? '').toString();
                textEn = (block['text_en'] ?? text).toString();
              } else if (block['type'] == 'image') {
                images.add(block);
              }
            }
          }
          _pages.add(_NotebookPage(text: text, textEn: textEn, images: images));
        }
      }
      if (_pages.isEmpty) {
        _pages.add(_NotebookPage(
          text: (item['body_text_fr'] ?? item['content_fr'] ?? item['body_text_en'] ?? item['content_en'] ?? '').toString(),
          textEn: (item['body_text_en'] ?? item['content_en'] ?? item['body_text_fr'] ?? item['content_fr'] ?? '').toString(),
        ));
      }
    } else {
      _published = widget.courseContext?['publish'] == true;
      _pages.add(_NotebookPage());
    }
  }

  @override
  void dispose() {
    _titleFr.dispose();
    _titleEn.dispose();
    _previewController.dispose();
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  void _addPage() {
    setState(() {
      _pages.add(_NotebookPage());
      _previewIndex = _pages.length - 1;
    });
  }

  Future<void> _addImage(int pageIndex) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(_t('Image illisible sur cet appareil.', 'Image cannot be read on this device.'));
      }
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${widget.chapterId}/notebook/${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final extension = (file.extension ?? '').toLowerCase();
      final mime = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      await _db.storage.from('chapter-content').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: false),
      );
      if (!mounted) return;
      setState(() {
        _pages[pageIndex].images.add({
          'type': 'image',
          'storage_path': path,
          'caption_fr': file.name,
          'caption_en': file.name,
        });
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  List<Map<String, dynamic>> _serializePages() {
    return [
      for (var index = 0; index < _pages.length; index++)
        {
          'id': 'page-${index + 1}',
          'position': index + 1,
          'format': 'A4',
          'blocks': [
            if (_pages[index].text.text.trim().isNotEmpty ||
                _pages[index].textEn.text.trim().isNotEmpty)
              {
                'type': 'text',
                'text_fr': _pages[index].text.text.trim().isEmpty
                    ? _pages[index].textEn.text.trim()
                    : _pages[index].text.text.trim(),
                'text_en': _pages[index].textEn.text.trim().isEmpty
                    ? _pages[index].text.text.trim()
                    : _pages[index].textEn.text.trim(),
              },
            ..._pages[index].images,
          ],
        },
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleFr.text.trim().isEmpty) {
      setState(() => _error = _t('Le titre français est obligatoire.', 'The French title is required.'));
      return;
    }
    if (_pages.every((page) =>
        page.text.text.trim().isEmpty && page.textEn.text.trim().isEmpty && page.images.isEmpty)) {
      setState(() => _error = _t('Ajoutez du texte ou une image dans au moins une page.', 'Add text or an image to at least one page.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final pages = _serializePages();
      final plainText = _pages.map((page) => page.text.text.trim())
          .where((value) => value.isNotEmpty).join('\n\n');
      final plainTextEn = _pages.map((page) => page.textEn.text.trim().isEmpty
          ? page.text.text.trim()
          : page.textEn.text.trim()).where((value) => value.isNotEmpty).join('\n\n');
      if (widget.courseContext != null) {
        final contextData = widget.courseContext!;
        final classIds = (contextData['class_ids'] as List? ?? const [])
            .map((value) => value.toString()).where((value) => value.isNotEmpty).toList();
        if (classIds.isEmpty) throw StateError(_t('Aucune salle destinataire sélectionnée.', 'No target classroom selected.'));
        for (final classId in classIds) {
          final values = <String, dynamic>{
            'curriculum_id': contextData['curriculum_id'],
            'chapter_id': contextData['chapter_id'],
            'subject_id': contextData['subject_id'],
            'teacher_id': contextData['teacher_id'],
            'class_id': classId,
            'title_fr': _titleFr.text.trim(),
            'title_en': _titleEn.text.trim().isEmpty ? _titleFr.text.trim() : _titleEn.text.trim(),
            'content_fr': plainText,
            'content_en': plainTextEn,
            'pages_json': pages,
            'status': _published ? 'published' : 'draft',
            'published_at': _published ? DateTime.now().toIso8601String() : null,
          };
          final existingId = widget.existingCourse != null &&
                  widget.existingCourse!['class_id']?.toString() == classId
              ? widget.existingCourse!['id']?.toString()
              : null;
          if (existingId != null) {
            await _db.from('courses').update(values).eq('id', existingId);
          } else {
            final matches = await _db.from('courses').select('id')
                .eq('class_id', classId)
                .eq('subject_id', contextData['subject_id'])
                .eq('chapter_id', contextData['chapter_id'])
                .eq('title_fr', _titleFr.text.trim())
                .neq('status', 'archived')
                .limit(1);
            if (matches.isEmpty) {
              await _db.from('courses').insert(values);
            } else {
              await _db.from('courses').update(values).eq('id', matches.first['id']);
            }
          }
        }
      } else {
        final data = <String, dynamic>{
          'chapter_id': widget.chapterId,
          'content_type': 'course',
          'title_fr': _titleFr.text.trim(),
          'title_en': _titleEn.text.trim().isEmpty ? _titleFr.text.trim() : _titleEn.text.trim(),
          'body_text_fr': plainText,
          'body_text_en': plainTextEn,
          'pages_json': pages,
          'is_published': _published,
          'created_by': _db.auth.currentUser?.id,
        };
        final existingId = widget.existingItem?['id']?.toString();
        if (existingId == null) {
          final rows = await _db.from('chapter_content_items')
              .select('position').eq('chapter_id', widget.chapterId).order('position', ascending: false).limit(1);
          data['position'] = rows.isEmpty ? 1 : ((rows.first['position'] as num?)?.toInt() ?? 0) + 1;
          await _db.from('chapter_content_items').insert(data);
        } else {
          data.remove('created_by');
          data.remove('chapter_id');
          await _db.from('chapter_content_items').update(data).eq('id', existingId);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Cahier enregistré.', 'Notebook saved.'))),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _imageUrl(String path) async {
    try {
      return await _db.storage.from('chapter-content').createSignedUrl(path, 900);
    } catch (_) {
      return null;
    }
  }

  Widget _pagePreview(int index) {
    final page = _pages[index];
    final previewText = _fr || page.textEn.text.trim().isEmpty
        ? page.text.text
        : page.textEn.text;
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth - 32;
      final heightLimitedWidth = (constraints.maxHeight - 32) * 210 / 297;
      final width = (availableWidth < heightLimitedWidth ? availableWidth : heightLimitedWidth).clamp(200.0, 794.0).toDouble();
      return Center(
        child: SizedBox(
          width: width,
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_titleFr.text.trim(), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF14532D))),
                    const Divider(height: 26, color: Color(0xFF16A34A)),
                    if (previewText.trim().isNotEmpty)
                      RichLessonText(text: previewText, style: const TextStyle(fontSize: 14, height: 1.65, color: Color(0xFF1E293B))),
                    for (final image in page.images)
                      if ((image['storage_path'] ?? '').toString().isNotEmpty)
                        FutureBuilder<String?>(
                          future: _imageUrl(image['storage_path'].toString()),
                          builder: (context, snapshot) => snapshot.data == null
                              ? const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                              : Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Image.network(snapshot.data!, fit: BoxFit.contain),
                                ),
                        ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Text('${_t('Page', 'Page')} ${index + 1}', style: const TextStyle(color: Colors.black45, fontSize: 10)),
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

  Widget _buildPageEditor(int index) {
    final page = _pages[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('${_t('PAGE', 'PAGE')} ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF166534)))),
              IconButton(
                tooltip: _t('Monter la page', 'Move page up'),
                onPressed: index == 0 ? null : () => setState(() {
                  final previous = _pages[index - 1];
                  _pages[index - 1] = _pages[index];
                  _pages[index] = previous;
                }),
                icon: const Icon(Icons.arrow_upward_rounded, size: 19),
              ),
              IconButton(
                tooltip: _t('Descendre la page', 'Move page down'),
                onPressed: index == _pages.length - 1 ? null : () => setState(() {
                  final next = _pages[index + 1];
                  _pages[index + 1] = _pages[index];
                  _pages[index] = next;
                }),
                icon: const Icon(Icons.arrow_downward_rounded, size: 19),
              ),
              IconButton(
                tooltip: _t('Supprimer la page', 'Delete page'),
                onPressed: _pages.length == 1 ? null : () {
                  setState(() {
                    _pages.removeAt(index).dispose();
                    if (_previewIndex >= _pages.length) _previewIndex = _pages.length - 1;
                  });
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ]),
            TextField(
              controller: page.text,
              minLines: 7,
              maxLines: 18,
              decoration: InputDecoration(
                labelText: _t('Texte français de cette page', 'French text on this page'),
                hintText: _t('Rédige le contenu de la page…', 'Write this page…'),
                border: const OutlineInputBorder(),
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(_t('Traduction anglaise (facultative)', 'English translation (optional)')),
              children: [
                TextField(
                  controller: page.textEn,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'English text',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _addImage(index),
                icon: const Icon(Icons.image_outlined),
                label: Text(_t('Insérer une image', 'Insert image')),
              ),
              for (var imageIndex = 0; imageIndex < page.images.length; imageIndex++)
                Chip(
                  avatar: const Icon(Icons.image, size: 16),
                  label: Text(_t('Image', 'Image') + ' ${imageIndex + 1}'),
                  onDeleted: () => setState(() => page.images.removeAt(imageIndex)),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(_preview ? _t('Aperçu du cahier', 'Notebook preview') : _t('Éditeur de cahier', 'Notebook editor')),
        actions: [
          IconButton(
            tooltip: _t('Basculer aperçu', 'Toggle preview'),
            onPressed: () => setState(() => _preview = !_preview),
            icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
          ),
        ],
      ),
      body: _preview
          ? Column(children: [
              Expanded(
                child: PageView.builder(
                  controller: _previewController,
                  itemCount: _pages.length,
                  onPageChanged: (index) => setState(() => _previewIndex = index),
                  itemBuilder: (context, index) => _pagePreview(index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text('${_t('Page', 'Page')} ${_previewIndex + 1} / ${_pages.length}'),
              ),
            ])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(controller: _titleFr, decoration: InputDecoration(labelText: _t('Titre du cours', 'Course title'))),
                const SizedBox(height: 8),
                TextField(controller: _titleEn, decoration: InputDecoration(labelText: _t('Titre anglais (facultatif)', 'English title (optional)'))),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                  child: Text(_t(
                    'Chaque feuille est indépendante. Ajoute le texte et les images, puis ouvre l’aperçu pour vérifier le rendu avant publication.',
                    'Each sheet is independent. Add text and images, then preview the result before publishing.',
                  )),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < _pages.length; index++) _buildPageEditor(index),
                OutlinedButton.icon(onPressed: _addPage, icon: const Icon(Icons.add), label: Text(_t('Ajouter une page', 'Add page'))),
                SwitchListTile(
                  value: _published,
                  onChanged: (value) => setState(() => _published = value),
                  title: Text(_t('Publier pour les élèves', 'Publish for students')),
                ),
                if (_error != null) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                  label: Text(_t('Enregistrer le cahier', 'Save notebook')),
                ),
              ],
            ),
    );
  }
}
