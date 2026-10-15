import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../../models/pedagogy.dart';

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
