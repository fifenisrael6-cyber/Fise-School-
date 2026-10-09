import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

class MessageAttachmentViewerPage extends StatefulWidget {
  const MessageAttachmentViewerPage({
    super.key,
    required this.url,
    required this.title,
    required this.mimeType,
  });

  final String url;
  final String title;
  final String mimeType;

  @override
  State<MessageAttachmentViewerPage> createState() => _MessageAttachmentViewerPageState();
}

class _MessageAttachmentViewerPageState extends State<MessageAttachmentViewerPage> {
  Uint8List? _bytes;
  PdfControllerPinch? _pdfController;
  AudioPlayer? _audioPlayer;
  VideoPlayerController? _videoController;
  String? _error;
  bool _loading = true;

  bool get _isPdf => widget.mimeType.toLowerCase().contains('pdf');
  bool get _isAudio => widget.mimeType.toLowerCase().startsWith('audio/');
  bool get _isVideo => widget.mimeType.toLowerCase().startsWith('video/');

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (_isPdf) {
        final response = await http.get(Uri.parse(widget.url));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError('HTTP ${response.statusCode}');
        }
        if (response.bodyBytes.isEmpty) throw StateError('Fichier vide');
        _bytes = response.bodyBytes;
        _pdfController = PdfControllerPinch(document: PdfDocument.openData(_bytes!));
      } else if (_isAudio) {
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.setSource(UrlSource(widget.url));
      } else if (_isVideo) {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.url));
        await _videoController!.initialize();
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Impossible d’ouvrir ce fichier. Vérifiez votre connexion ou son accès.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _audioPlayer?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.mimeType.toLowerCase();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _isPdf
                  ? PdfViewPinch(controller: _pdfController!)
                  : _isAudio
                      ? _audioControls()
                      : _isVideo
                          ? _videoView()
                          : type.startsWith('image/')
                              ? InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 5,
                                  child: Center(
                                    child: Image.network(
                                      widget.url,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Text('Image indisponible'),
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Ce format ne peut pas être affiché dans l’application.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
    );
  }

  Widget _audioControls() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.graphic_eq_rounded, size: 64),
          const SizedBox(height: 12),
          Text(widget.title, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          StreamBuilder<PlayerState>(
            stream: _audioPlayer!.onPlayerStateChanged,
            initialData: _audioPlayer!.state,
            builder: (context, snapshot) {
              final playing = snapshot.data == PlayerState.playing;
              return FilledButton.icon(
                onPressed: () async {
                  if (playing) {
                    await _audioPlayer!.pause();
                  } else {
                    await _audioPlayer!.resume();
                  }
                },
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(playing ? 'Pause' : 'Écouter'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _videoView() {
    final controller = _videoController!;
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            IconButton.filledTonal(
              iconSize: 40,
              onPressed: () async {
                if (controller.value.isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
