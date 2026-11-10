import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

import 'rich_lesson_text.dart';

/// Renders a course body stored as Quill Delta JSON.
///
/// Supported inputs:
/// - Quill Delta array: [{"insert":"Text"}, ...]
/// - Legacy Quill object: {"ops":[{"insert":"Text"}, ...]}
/// - Plain text / legacy text: rendered with [RichLessonText].
///
/// The document/controller is created in initState (or when the input changes),
/// never from build(). Quill's own scrollable is disabled so the parent page
/// (usually a ListView) remains the only vertical scroll view.
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
    final raw = widget.text.trim();
    if (raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      final List<dynamic>? rawOperations;

      if (decoded is List) {
        // Format currently produced by the Fise School Quill editor.
        rawOperations = decoded;
      } else if (decoded is Map && decoded['ops'] is List) {
        // Backward compatibility with the classic Quill {"ops": [...]} form.
        rawOperations = decoded['ops'] as List<dynamic>;
      } else {
        // Valid JSON, but not a Quill Delta document: use the text fallback.
        return;
      }

      if (rawOperations.isEmpty) return;

      final operations = rawOperations.map((operation) {
        if (operation is! Map) {
          throw const FormatException('Invalid Quill Delta operation');
        }
        return Map<String, dynamic>.from(operation);
      }).toList(growable: false);

      final document = Document.fromJson(operations);
      _controller = QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      // Invalid JSON/Delta must never crash the student course page.
      // The original content is displayed by RichLessonText below.
      _controller?.dispose();
      _controller = null;
    }
  }

  /// Returns a MemoryImage for data:image/...;base64,... sources.
  /// Returning null lets flutter_quill_extensions handle normal URLs.
  static ImageProvider<Object>? _dataImageProvider(
    BuildContext context,
    String imageUrl,
  ) {
    if (!imageUrl.startsWith('data:image/')) return null;

    try {
      final commaIndex = imageUrl.indexOf(',');
      if (commaIndex < 0) return null;

      final metadata = imageUrl.substring(5, commaIndex).toLowerCase();
      final payload = imageUrl.substring(commaIndex + 1);
      final Uint8List bytes;

      if (metadata.split(';').contains('base64')) {
        bytes = base64Decode(base64.normalize(payload));
      } else {
        bytes = Uint8List.fromList(
          utf8.encode(Uri.decodeComponent(payload)),
        );
      }

      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      // A malformed image is ignored instead of crashing the whole course.
      return null;
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

    final embedBuilders = <EmbedBuilder>[
      ...FlutterQuillEmbeds.editorBuilders(
        imageEmbedConfig: QuillEditorImageEmbedConfig(
          imageProviderBuilder: _dataImageProvider,
        ),
      ),
    ];

    final editor = QuillEditor.basic(
      controller: controller,
      config: QuillEditorConfig(
        padding: EdgeInsets.zero,
        expands: false,
        scrollable: false,
        showCursor: false,
        enableInteractiveSelection: widget.selectable,
        embedBuilders: embedBuilders,
      ),
    );

    return DefaultTextStyle.merge(
      style: widget.style,
      child: editor,
    );
  }
}
