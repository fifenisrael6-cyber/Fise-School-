import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Affiche les pièces jointes dans Fise School sans ouvrir une page Supabase.
class MessageAttachmentViewer extends StatefulWidget {
  final String messageId;
  final String attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final bool isFrench;
  final Future<String?> Function() loadUrl;

  const MessageAttachmentViewer({
    super.key,
    required this.messageId,
    required this.attachmentPath,
    required this.attachmentName,
    required this.attachmentType,
    required this.isFrench,
    required this.loadUrl,
  });

  @override
  State<MessageAttachmentViewer> createState() => _MessageAttachmentViewerState();
}

class _MessageAttachmentViewerState extends State<MessageAttachmentViewer> {
  late Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = widget.loadUrl();
  }

  @override
  void didUpdateWidget(covariant MessageAttachmentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachmentPath != widget.attachmentPath ||
        oldWidget.messageId != widget.messageId) {
      _urlFuture = widget.loadUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final url = snapshot.data;
        if (snapshot.hasError || url == null || url.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.isFrench
                ? 'Fichier indisponible. Actualisez la conversation.'
                : 'Attachment unavailable. Refresh the conversation.'),
          );
        }

        final type = (widget.attachmentType ?? '').toLowerCase();
        final name = (widget.attachmentName ?? '').toLowerCase();
        if (type.startsWith('image/')) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ImageViewerPage(
                    imageUrl: url, messageId: widget.messageId,
                    isFrench: widget.isFrench,
                  ),
                ),
              ),
              child: Hero(
                tag: 'message-image-${widget.messageId}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url, width: 230, height: 185, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _brokenPreview(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        width: 230, height: 185,
                        child: Center(child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes == null
                              ? null
                              : progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!,
                        )),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        }

        final isPdf = type.contains('pdf') || name.endsWith('.pdf');
        final isAudio = type.startsWith('audio/') || name.endsWith('.mp3') ||
            name.endsWith('.m4a') || name.endsWith('.aac') ||
            name.endsWith('.wav') || name.endsWith('.ogg');
        final isVideo = type.startsWith('video/') || name.endsWith('.mp4') ||
            name.endsWith('.mov') || name.endsWith('.webm');

        if (isAudio) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _AudioMessagePlayer(url: url, isFrench: widget.isFrench),
          );
        }
        if (isVideo) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _VideoViewerPage(
                    videoUrl: url,
                    title: widget.attachmentName ??
                        (widget.isFrench ? 'Vidéo' : 'Video'),
                    isFrench: widget.isFrench,
                  ),
                ),
              ),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: Text(widget.attachmentName ??
                  (widget.isFrench ? 'Lire la vidéo' : 'Play video')),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () {
              if (isPdf) {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _PdfViewerPage(
                    pdfUrl: url,
                    title: widget.attachmentName ??
                        (widget.isFrench ? 'Document PDF' : 'PDF document'),
                    isFrench: widget.isFrench,
                  ),
                ));
              } else {
                launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
              }
            },
            icon: Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.attach_file_rounded),
            label: Text(widget.attachmentName ??
                (isPdf
                    ? (widget.isFrench ? 'Ouvrir le PDF' : 'Open PDF')
                    : (widget.isFrench ? 'Ouvrir le fichier' : 'Open file'))),
          ),
        );
      },
    );
  }

  Widget _brokenPreview() => SizedBox(
    width: 230, height: 185,
    child: Center(child: Text(widget.isFrench
        ? 'Aperçu indisponible' : 'Preview unavailable')),
  );
}

class _ImageViewerPage extends StatelessWidget {
  final String imageUrl;
  final String messageId;
  final bool isFrench;

  const _ImageViewerPage({
    required this.imageUrl, required this.messageId, required this.isFrench,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black, foregroundColor: Colors.white,
      title: Text(isFrench ? 'Photo' : 'Photo'),
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 0.5, maxScale: 6,
        child: Hero(
          tag: 'message-image-${messageId}',
          child: Image.network(
            imageUrl, fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const Center(
                  child: CircularProgressIndicator()),
            errorBuilder: (_, __, ___) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(isFrench
                  ? 'Impossible de charger cette photo. Vérifiez votre connexion.'
                  : 'Could not load this photo. Check your connection.',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PdfViewerPage extends StatefulWidget {
  final String pdfUrl;
  final String title;
  final bool isFrench;
  const _PdfViewerPage({
    required this.pdfUrl, required this.title, required this.isFrench,
  });
  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  late final PdfControllerPinch _controller =
      PdfControllerPinch(document: _loadDocument());

  Future<PdfDocument> _loadDocument() async {
    final response = await http.get(Uri.parse(widget.pdfUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('PDF unavailable (${response.statusCode})');
    }
    return PdfDocument.openData(response.bodyBytes);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: PdfViewPinch(
      controller: _controller,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) => const Center(
          child: CircularProgressIndicator()),
        pageLoaderBuilder: (_) => const Center(
          child: CircularProgressIndicator()),
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(widget.isFrench
                ? 'Impossible d’ouvrir ce PDF. Vérifiez la connexion et réessayez.'
                : 'Could not open this PDF. Check the connection and retry.'),
          ),
        ),
      ),
    ),
  );
}

class _AudioMessagePlayer extends StatefulWidget {
  final String url;
  final bool isFrench;
  const _AudioMessagePlayer({required this.url, required this.isFrench});
  @override
  State<_AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<_AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSubscription;
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.setSourceUrl(widget.url);
        await _player.resume();
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isFrench
            ? 'Impossible de lire ce message vocal.'
            : 'Could not play this audio message.'),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _loading ? null : _toggle,
    icon: _loading
        ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    label: Text(_playing
        ? 'Pause audio'
        : (widget.isFrench ? 'Écouter le vocal' : 'Play voice message')),
  );
}

class _VideoViewerPage extends StatefulWidget {
  final String videoUrl;
  final String title;
  final bool isFrench;
  const _VideoViewerPage({
    required this.videoUrl, required this.title, required this.isFrench,
  });
  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
  late final Future<void> _initialization = _controller.initialize();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(widget.isFrench
              ? 'Impossible de lire cette vidéo.' : 'Could not play this video.');
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 38,
                    onPressed: () => setState(() {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    }),
                    icon: Icon(_controller.value.isPlaying
                        ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  ),
                  Expanded(child: VideoProgressIndicator(
                    _controller, allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12))),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}
