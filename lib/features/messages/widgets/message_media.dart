import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Affiche une pièce jointe de message comme dans les applications de messagerie :
/// image (plein écran zoomable), note vocale / audio (lecteur), vidéo (lecteur),
/// PDF (lecteur intégré) et autres documents (carte + ouverture).
class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    super.key,
    required this.name,
    required this.type,
    required this.localPath,
    required this.remotePath,
    required this.resolveUrl,
    this.french = true,
  });

  final String? name;
  final String? type;
  final String? localPath;
  final String? remotePath;
  final Future<String?> Function(String? path) resolveUrl;
  final bool french;

  bool get _hasLocal => localPath != null && File(localPath!).existsSync();
  String get _mime => (type ?? '').toLowerCase();
  String get _lowerName => (name ?? '').toLowerCase();

  bool get _isImage => _mime.startsWith('image/');
  bool get _isAudio => _mime.startsWith('audio/') || _lowerName.endsWith('.m4a') || _lowerName.endsWith('.mp3') || _lowerName.endsWith('.aac');
  bool get _isVideo => _mime.startsWith('video/') || _lowerName.endsWith('.mp4');
  bool get _isPdf => _mime == 'application/pdf' || _lowerName.endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: FutureBuilder<String?>(
        future: _hasLocal ? Future.value(null) : resolveUrl(remotePath),
        builder: (context, snapshot) {
          final url = snapshot.data;
          final waiting = !_hasLocal && snapshot.connectionState != ConnectionState.done;
          final unavailable = !_hasLocal && !waiting && url == null;
          if (unavailable) return _DocumentCard(name: name, type: type, french: french, onTap: null, subtitle: french ? 'Indisponible hors ligne' : 'Unavailable offline');
          if (_isImage) return _imageThumb(context, url);
          if (_isAudio) return AudioMessagePlayer(localPath: _hasLocal ? localPath : null, url: url, loading: waiting);
          if (_isVideo) return _videoCard(context, url);
          return _DocumentCard(
            name: name,
            type: type,
            french: french,
            onTap: waiting ? null : () => _openDocument(context, url),
            subtitle: _isPdf ? (french ? 'PDF • Appuyer pour lire' : 'PDF • Tap to read') : (french ? 'Appuyer pour ouvrir' : 'Tap to open'),
          );
        },
      ),
    );
  }

  Widget _imageThumb(BuildContext context, String? url) {
    final image = _hasLocal
        ? Image.file(File(localPath!), width: 220, height: 180, fit: BoxFit.cover)
        : (url == null
            ? const SizedBox(width: 220, height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : Image.network(url, width: 220, height: 180, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 180, child: Icon(Icons.broken_image_outlined))));
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaImageViewerPage(localPath: _hasLocal ? localPath : null, url: url, title: name ?? ''),
      )),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
    );
  }

  Widget _videoCard(BuildContext context, String? url) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaVideoViewerPage(localPath: _hasLocal ? localPath : null, url: url, title: name ?? ''),
      )),
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: Stack(alignment: Alignment.center, children: [
          const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 54),
          Positioned(
            left: 10, right: 10, bottom: 8,
            child: Text(name ?? (french ? 'Vidéo' : 'Video'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Future<void> _openDocument(BuildContext context, String? url) async {
    if (_isPdf) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPdfViewerPage(localPath: _hasLocal ? localPath : null, url: url, title: name ?? 'PDF'),
      ));
      return;
    }
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.name, required this.type, required this.french, required this.onTap, required this.subtitle});

  final String? name;
  final String? type;
  final bool french;
  final VoidCallback? onTap;
  final String subtitle;

  IconData _icon() {
    final n = (name ?? '').toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (n.endsWith('.doc') || n.endsWith('.docx')) return Icons.description_rounded;
    if (n.endsWith('.xls') || n.endsWith('.xlsx') || n.endsWith('.csv')) return Icons.table_chart_rounded;
    if (n.endsWith('.ppt') || n.endsWith('.pptx')) return Icons.slideshow_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(_icon(), size: 34, color: const Color(0xFF166534)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name ?? (french ? 'Fichier' : 'File'), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Lecteur de note vocale / audio : lecture-pause, barre de progression, durée.
class AudioMessagePlayer extends StatefulWidget {
  const AudioMessagePlayer({super.key, this.localPath, this.url, this.loading = false});
  final String? localPath;
  final String? url;
  final bool loading;

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _state = s); }));
    _subs.add(_player.onPositionChanged.listen((d) { if (mounted) setState(() => _position = d); }));
    _subs.add(_player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); }));
    _subs.add(_player.onPlayerComplete.listen((_) { if (mounted) setState(() { _position = Duration.zero; _state = PlayerState.stopped; }); }));
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_state == PlayerState.paused) {
      await _player.resume();
      return;
    }
    final local = widget.localPath;
    if (local != null && File(local).existsSync()) {
      await _player.play(DeviceFileSource(local));
    } else if (widget.url != null) {
      await _player.play(UrlSource(widget.url!));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final maxMs = _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final posMs = _position.inMilliseconds.clamp(0, maxMs);
    return SizedBox(
      width: 230,
      child: Row(children: [
        widget.loading
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                onPressed: _toggle,
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 36, color: const Color(0xFF166534)),
              ),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
              child: Slider(
                value: posMs.toDouble(),
                max: maxMs.toDouble(),
                onChanged: _duration.inMilliseconds <= 0 ? null : (v) => _player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_position), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                Text(_fmt(_duration), style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

class MediaImageViewerPage extends StatelessWidget {
  const MediaImageViewerPage({super.key, this.localPath, this.url, required this.title});
  final String? localPath;
  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final Widget image = localPath != null && File(localPath!).existsSync()
        ? Image.file(File(localPath!))
        : (url != null ? Image.network(url!) : const Icon(Icons.broken_image_outlined, color: Colors.white, size: 64));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Center(child: InteractiveViewer(minScale: 0.8, maxScale: 5, child: image)),
    );
  }
}

class MediaVideoViewerPage extends StatefulWidget {
  const MediaVideoViewerPage({super.key, this.localPath, this.url, required this.title});
  final String? localPath;
  final String? url;
  final String title;

  @override
  State<MediaVideoViewerPage> createState() => _MediaVideoViewerPageState();
}

class _MediaVideoViewerPageState extends State<MediaVideoViewerPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final local = widget.localPath;
    final VideoPlayerController? c = (local != null && File(local).existsSync())
        ? VideoPlayerController.file(File(local))
        : (widget.url != null ? VideoPlayerController.networkUrl(Uri.parse(widget.url!)) : null);
    if (c == null) {
      _failed = true;
      return;
    }
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _failed || c == null
          ? const Center(child: Icon(Icons.error_outline, color: Colors.white, size: 56))
          : !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))),
                  VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, value, __) => IconButton(
                      iconSize: 46,
                      color: Colors.white,
                      onPressed: () => value.isPlaying ? c.pause() : c.play(),
                      icon: Icon(value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ]),
    );
  }
}

class MediaPdfViewerPage extends StatefulWidget {
  const MediaPdfViewerPage({super.key, this.localPath, this.url, required this.title});
  final String? localPath;
  final String? url;
  final String title;

  @override
  State<MediaPdfViewerPage> createState() => _MediaPdfViewerPageState();
}

class _MediaPdfViewerPageState extends State<MediaPdfViewerPage> {
  PdfControllerPinch? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final local = widget.localPath;
      final Future<PdfDocument> doc;
      if (local != null && File(local).existsSync()) {
        doc = PdfDocument.openFile(local);
      } else if (widget.url != null) {
        final res = await http.get(Uri.parse(widget.url!)).timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
        doc = PdfDocument.openData(res.bodyBytes);
      } else {
        throw Exception('no source');
      }
      if (!mounted) return;
      setState(() => _controller = PdfControllerPinch(document: doc));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
        body: _failed
            ? const Center(child: Icon(Icons.error_outline, size: 56))
            : _controller == null
                ? const Center(child: CircularProgressIndicator())
                : PdfViewPinch(controller: _controller!),
      );
}
