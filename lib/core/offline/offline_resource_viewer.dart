import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../../models/pedagogy.dart';

String _decodeXmlText(String value) {
  var text = value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  text = text.replaceAllMapped(
    RegExp(r'&#(?:x([0-9a-fA-F]+)|([0-9]+));'),
    (m) {
      final code = int.tryParse(m[1] ?? m[2] ?? '', radix: m[1] == null ? 10 : 16);
      return code == null || code < 0 || code > 0x10ffff
          ? ''
          : String.fromCharCode(code);
    },
  );
  return text;
}

String _xmlRuns(String xml, String tag) {
  final expression = RegExp(
    '<(?:[A-Za-z0-9_]+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:[A-Za-z0-9_]+:)?$tag>',
  );
  return expression
      .allMatches(xml)
      .map((match) => _decodeXmlText(
          (match.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), '')))
      .join();
}

String _archiveXml(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null) return '';
  return utf8.decode(file.content, allowMalformed: true);
}

Future<String> _readOfficeDocument(String path, String fileName) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.isEmpty) throw const FormatException('Empty document.');
  final archive = ZipDecoder().decodeBytes(bytes);
  final lower = fileName.toLowerCase();

  if (lower.endsWith('.docx')) {
    final xml = _archiveXml(archive, 'word/document.xml');
    if (xml.isEmpty) throw const FormatException('Invalid DOCX document.');
    final paragraphs = RegExp(r'<w:p\b[^>]*>([\s\S]*?)</w:p>')
        .allMatches(xml)
        .map((m) => _xmlRuns(m.group(1) ?? '', 't').trim())
        .where((line) => line.isNotEmpty);
    return paragraphs.join('\n\n');
  }

  if (lower.endsWith('.pptx')) {
    final slides = archive.files
        .where((f) =>
            f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        int number(String name) => int.tryParse(
              RegExp(r'slide(\d+)\.xml$').firstMatch(name)?.group(1) ?? '',
            ) ?? 0;
        return number(a.name).compareTo(number(b.name));
      });
    final output = <String>[];
    for (var i = 0; i < slides.length; i++) {
      final xml = utf8.decode(slides[i].content, allowMalformed: true);
      final paragraphs = RegExp(r'<a:p\b[^>]*>([\s\S]*?)</a:p>')
          .allMatches(xml)
          .map((m) => _xmlRuns(m.group(1) ?? '', 't').trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (paragraphs.isNotEmpty) {
        output.add('Diapositive ' + (i + 1).toString() + '\n' + paragraphs.join('\n'));
      }
    }
    if (output.isEmpty) throw const FormatException('Invalid PPTX document.');
    return output.join('\n\n');
  }

  if (lower.endsWith('.xlsx')) {
    final sharedXml = _archiveXml(archive, 'xl/sharedStrings.xml');
    final sharedStrings = RegExp(r'<si\b[^>]*>([\s\S]*?)</si>')
        .allMatches(sharedXml)
        .map((m) => _xmlRuns(m.group(1) ?? '', 't'))
        .toList(growable: false);
    final sheets = archive.files
        .where((f) =>
            f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        int number(String name) => int.tryParse(
              RegExp(r'sheet(\d+)\.xml$').firstMatch(name)?.group(1) ?? '',
            ) ?? 0;
        return number(a.name).compareTo(number(b.name));
      });
    final output = <String>[];
    for (var i = 0; i < sheets.length; i++) {
      final xml = utf8.decode(sheets[i].content, allowMalformed: true);
      final rows = RegExp(r'<row\b[^>]*>([\s\S]*?)</row>')
          .allMatches(xml)
          .map((rowMatch) {
        final cells = <String>[];
        final rowXml = rowMatch.group(1) ?? '';
        final cellExpression = RegExp(
          r'<c\b([^>]*)>([\s\S]*?)</c>|<c\b([^>]*)/>',
        );
        for (final cell in cellExpression.allMatches(rowXml)) {
          final attrs = cell.group(1) ?? cell.group(3) ?? '';
          final body = cell.group(2) ?? '';
          final type = RegExp(r'\bt="([^"]+)"').firstMatch(attrs)?.group(1);
          final raw = RegExp(r'<v\b[^>]*>([\s\S]*?)</v>')
                  .firstMatch(body)
                  ?.group(1) ??
              '';
          var value = _decodeXmlText(raw);
          if (type == 's') {
            final index = int.tryParse(value);
            value = index != null && index >= 0 && index < sharedStrings.length
                ? sharedStrings[index]
                : '';
          } else if (type == 'inlineStr') {
            value = _xmlRuns(body, 't');
          }
          final reference = RegExp(r'\br="([^"]+)"').firstMatch(attrs)?.group(1);
          if (reference != null && value.isNotEmpty) {
            cells.add(reference + ': ' + value);
          } else if (value.isNotEmpty) {
            cells.add(value);
          }
        }
        return cells.join('  |  ');
      }).where((line) => line.isNotEmpty);
      output.add('Feuille ' + (i + 1).toString() + '\n' + rows.join('\n'));
    }
    if (output.isEmpty) throw const FormatException('Invalid XLSX document.');
    return output.join('\n\n');
  }

  throw UnsupportedError(
    'Aperçu intégré disponible pour DOCX, PPTX et XLSX. Convertissez les anciens formats binaires en PDF.',
  );
}

class OfflineResourceViewer extends StatefulWidget {
  final Locale locale;
  final String userId;
  final CourseResource resource;
  final String? localPath;
  final String? signedUrl;

  const OfflineResourceViewer({
    super.key,
    required this.locale,
    required this.userId,
    required this.resource,
    this.localPath,
    this.signedUrl,
  });

  @override
  State<OfflineResourceViewer> createState() => _OfflineResourceViewerState();
}

class _OfflineResourceViewerState extends State<OfflineResourceViewer> {
  PdfControllerPinch? _pdfController;
  Future<String>? _officeTextFuture;

  bool get _fr => widget.locale.languageCode != 'en';

  /// Choisit le lecteur à partir du type, du MIME ou de l'extension réelle.
  String get _effectiveType {
    final declared = widget.resource.resourceType.toLowerCase().trim();
    final mime = (widget.resource.mimeType ?? '').toLowerCase().trim();
    final name = widget.resource.fileName.toLowerCase();

    bool hasExtension(List<String> extensions) =>
        extensions.any((extension) => name.endsWith(extension));

    if (declared == 'pdf' ||
        mime == 'application/pdf' ||
        name.endsWith('.pdf')) {
      return 'pdf';
    }
    if (hasExtension(['.docx', '.pptx', '.xlsx'])) {
      return 'office';
    }
    if (hasExtension(['.rtf'])) {
      return 'text';
    }
    if (declared == 'image' ||
        mime.startsWith('image/') ||
        hasExtension(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp'])) {
      return 'image';
    }
    if (declared == 'audio' ||
        mime.startsWith('audio/') ||
        hasExtension(['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.flac'])) {
      return 'audio';
    }
    if (declared == 'video' ||
        mime.startsWith('video/') ||
        hasExtension(['.mp4', '.mov', '.mkv', '.webm', '.3gp', '.avi', '.m4v'])) {
      return 'video';
    }
    if (declared == 'text' ||
        mime.startsWith('text/') ||
        hasExtension(['.txt', '.csv', '.json', '.xml', '.md'])) {
      return 'text';
    }
    return declared;
  }

  @override
  void initState() {
    super.initState();
    final path = widget.localPath;
    if (path != null && _effectiveType == 'pdf') {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(path),
      );
    }
    if (path != null && _effectiveType == 'office') {
      _officeTextFuture = _readOfficeDocument(path, widget.resource.fileName);
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.localPath;
    final title = widget.resource.labelFor(widget.locale.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: path == null || !File(path).existsSync()
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _fr
                      ? 'Le fichier n’est pas disponible hors ligne. Connectez-vous à Internet puis réessayez de le télécharger.'
                      : 'This file is not available offline. Connect to the internet and try downloading it again.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _buildLocal(path),
    );
  }

  Widget _buildLocal(String path) {
    switch (_effectiveType) {
      case 'pdf':
        final controller = _pdfController;
        if (controller == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfViewPinch(controller: controller);
      case 'image':
        return Center(
          child: InteractiveViewer(
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        );
      case 'audio':
        return _AudioLocalPlayer(path: path, locale: widget.locale);
      case 'video':
        return _VideoLocalPlayer(path: path, locale: widget.locale);
      case 'office':
        return FutureBuilder<String>(
          future: _officeTextFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _fr
                        ? 'Impossible de lire ce document Office. Essayez de le convertir en PDF.'
                        : 'Unable to preview this Office document. Try converting it to PDF.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snapshot.data!,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            );
          },
        );
      case 'text':
        return FutureBuilder<String>(
          future: File(path).readAsString(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(_fr ? 'Impossible de lire ce fichier texte.' : 'Unable to read this text file.'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(snapshot.data!),
            );
          },
        );
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _fr
                  ? 'Ce type de fichier ne possède pas encore de lecteur intégré.'
                  : 'This file type does not have an integrated viewer yet.',
              textAlign: TextAlign.center,
            ),
          ),
        );
    }
  }
}

class _VideoLocalPlayer extends StatefulWidget {
  final String path;
  final Locale locale;

  const _VideoLocalPlayer({required this.path, required this.locale});

  @override
  State<_VideoLocalPlayer> createState() => _VideoLocalPlayerState();
}

class _VideoLocalPlayerState extends State<_VideoLocalPlayer> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio == 0
            ? 16 / 9
            : _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller),
            VideoProgressIndicator(_controller, allowScrubbing: true),
            Center(
              child: IconButton.filled(
                onPressed: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioLocalPlayer extends StatefulWidget {
  final String path;
  final Locale locale;

  const _AudioLocalPlayer({required this.path, required this.locale});

  @override
  State<_AudioLocalPlayer> createState() => _AudioLocalPlayerState();
}

class _AudioLocalPlayerState extends State<_AudioLocalPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.locale.languageCode != 'en';

    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.audiotrack_rounded,
                size: 64,
                color: Color(0xFF166534),
              ),
              const SizedBox(height: 16),
              Text(
                fr ? 'Audio du cours' : 'Course audio',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    if (_playing) {
                      await _player.pause();
                    } else {
                      await _player.play(DeviceFileSource(widget.path));
                    }
                    if (mounted) setState(() => _playing = !_playing);
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          fr ? 'Impossible de lire cet audio.' : 'Unable to play this audio.',
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Pause' : (fr ? 'Lire' : 'Play')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
