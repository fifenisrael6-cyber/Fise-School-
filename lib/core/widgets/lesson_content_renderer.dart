import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'rich_lesson_text.dart';
import 'course_image_embed.dart';
import 'course_table_embed.dart';

/// Displays Quill Delta courses while keeping compatibility with legacy text.
class LessonContentRenderer extends StatefulWidget {
  const LessonContentRenderer({
    super.key,
    required this.text,
    this.style = const TextStyle(
      fontSize: 16,
      height: 1.65,
      color: Color(0xFF334155),
    ),
    this.selectable = true,
  });

  final String text;
  final TextStyle style;
  final bool selectable;

  @override
  State<LessonContentRenderer> createState() => _LessonContentRendererState();
}

class _LessonContentRendererState extends State<LessonContentRenderer> {
  QuillController? _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant LessonContentRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller?.dispose();
      _controller = null;
      _createController();
    }
  }

  void _createController() {
    try {
      final decoded = jsonDecode(widget.text);
      if (decoded is! Map || decoded['ops'] is! List) return;
      final operations = (decoded['ops'] as List)
          .whereType<Map>()
          .map((operation) => Map<String, dynamic>.from(operation))
          .toList(growable: false);
      if (operations.isEmpty) return;
      _controller = QuillController(
        document: Document.fromJson(operations),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      // A non-Delta value is an older plain-text/Markdown course.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return RichLessonText(
        text: widget.text,
        style: widget.style,
        selectable: widget.selectable,
      );
    }
    final editor = QuillEditor.basic(
      controller: controller,
      config: QuillEditorConfig(
        padding: EdgeInsets.zero,
        expands: false,
        showCursor: false,
        embedBuilders: [CourseImageEmbedBuilder(), CourseTableEmbedBuilder()],
      ),
    );
    return DefaultTextStyle.merge(style: widget.style, child: editor);
  }
}
