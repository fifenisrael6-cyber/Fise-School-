import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  AudioPlayer? _audioPlayer;
  PdfControllerPinch? _pdfController;
  String? _textContent;
  WebViewController? _webController;

  bool get _fr => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    final path = widget.localPath;
    if (path != null && widget.resource.resourceType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(path));
    } else if (path != null && widget.resource.resourceType != 'image' &&
        widget.resource.resourceType != 'audio' && widget.resource.resourceType != 'video') {
      _prepareDocument(path);
    }
  }

  Future<void> _prepareDocument(String path) async {
    final name = widget.resource.fileName.toLowerCase();
    try {
      if (name.endsWith('.txt') || name.endsWith('.csv') || name.endsWith('.json') ||
          name.endsWith('.md') || name.endsWith('.xml')) {
        final text = await File(path).readAsString();
        if (mounted) setState(() => _textContent = text);
      } else if (name.endsWith('.html') || name.endsWith('.htm')) {
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.loadFile(path);
        if (mounted) setState(() => _webController = controller);
      }
    } catch (_) {
      // The downloaded file remains available even if this format has no previewer.
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _audioPlayer?.dispose();
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
          ? Center(child: Text(_fr ? 'Le fichier n’est pas disponible hors ligne.' : 'This file is not available offline.'))
          : _buildLocal(path),
    );
  }

  Widget _buildLocal(String path) {
    switch (widget.resource.resourceType) {
      case 'pdf':
        final controller = _pdfController;
        if (controller == null) {
          return const SizedBox.shrink();
        }
        return PdfViewPinch(controller: controller);
      case 'image':
        return Center(child: InteractiveViewer(child: Image.file(File(path), fit: BoxFit.contain)));
      case 'audio':
        return _AudioLocalPlayer(path: path, locale: widget.locale);
      case 'video':
        return _VideoLocalPlayer(path: path, locale: widget.locale);
      default:
        if (_textContent != null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_textContent!),
          );
        }
        if (_webController != null) {
          return WebViewWidget(controller: _webController!);
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 56, color: Color(0xFF166534)),
                const SizedBox(height: 12),
                Text(widget.resource.fileName, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(_fr
                    ? 'Le fichier est téléchargé et conservé hors ligne. L’aperçu intégré n’est pas disponible pour ce format.'
                    : 'The file is downloaded and stored offline. An embedded preview is not available for this format.',
                    textAlign: TextAlign.center),
              ],
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
    _controller = VideoPlayerController.file(File(widget.path))..initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
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
        aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          VideoPlayer(_controller),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          Center(
            child: IconButton.filled(
              onPressed: () { setState(() { _controller.value.isPlaying ? _controller.pause() : _controller.play(); }); },
              icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
          ),
        ]),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.audiotrack_rounded, size: 64, color: Color(0xFF166534)),
            const SizedBox(height: 16),
            Text(fr ? 'Audio du cours' : 'Course audio', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                if (_playing) {
                  await _player.pause();
                } else {
                  await _player.play(DeviceFileSource(widget.path));
                }
                if (mounted) {
                  setState(() => _playing = !_playing);
                }
              },
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              label: Text(_playing ? (fr ? 'Pause' : 'Pause') : (fr ? 'Lire' : 'Play')),
            ),
          ]),
        ),
      ),
    );
  }
}
