import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Persistent cache for message attachments. The remote object path is the cache key,
/// so a refreshed signed URL does not cause the same file to be downloaded again.
class _MessageMediaCache {
  static Future<String?> find({
    required String? remotePath,
    required String? fileName,
    String? url,
  }) async {
    final key = (remotePath?.isNotEmpty == true) ? remotePath! : url;
    if (key == null || key.isEmpty) return null;
    try {
      final file = await _cacheFile(key, fileName);
      return await file.exists() ? file.path : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> download({
    required String? remotePath,
    required String? fileName,
    required String? url,
  }) async {
    if (url == null || url.isEmpty) return null;
    final key = (remotePath?.isNotEmpty == true) ? remotePath! : url;
    final cached = await find(remotePath: key, fileName: fileName, url: url);
    if (cached != null) return cached;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return await saveBytes(remotePath: key, fileName: fileName, bytes: response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  static Future<String> saveBytes({
    required String remotePath,
    required String? fileName,
    required List<int> bytes,
  }) async {
    final file = await _cacheFile(remotePath, fileName);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<File> _cacheFile(String key, String? name) async {
    final support = await getApplicationSupportDirectory();
    final safeName = (name ?? 'attachment.bin').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return File('${support.path}/message_media_cache/${hash.toRadixString(16)}_$safeName');
  }
}

/// Affiche une pièce jointe de message dans l'application. Au premier accès,
/// le contenu est ouvert en streaming puis mis en cache; les ouvertures suivantes
/// utilisent le fichier local et fonctionnent hors ligne.
class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    super.key,
    required this.name,
    required this.type,
    required this.localPath,
    required this.remotePath,
    required this.resolveUrl,
    this.cacheScope,
    this.french = true,
  });

  final String? name;
  final String? type;
  final String? localPath;
  final String? remotePath;
  final Future<String?> Function(String? path) resolveUrl;
  final String? cacheScope;
  final bool french;

  String? get _cacheKey => remotePath == null
      ? null
      : (cacheScope == null ? remotePath : '$cacheScope::$remotePath');

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
        future: _hasLocal
            ? Future.value(localPath)
            : _MessageMediaCache.find(remotePath: _cacheKey, fileName: name),
        builder: (context, cacheSnapshot) {
          final cachedPath = cacheSnapshot.data;
          if (!_hasLocal && cacheSnapshot.connectionState != ConnectionState.done) {
            return _DocumentCard(
              name: name,
              type: type,
              french: french,
              onTap: null,
              subtitle: french ? 'Préparation du fichier…' : 'Preparing file…',
            );
          }
          return FutureBuilder<String?>(
            future: (cachedPath != null && File(cachedPath).existsSync())
                ? Future.value(null)
                : resolveUrl(remotePath),
            builder: (context, snapshot) {
              final effectiveLocal = (cachedPath != null && File(cachedPath).existsSync())
                  ? cachedPath
                  : (_hasLocal ? localPath : null);
              final url = snapshot.data;
              final waiting = effectiveLocal == null && snapshot.connectionState != ConnectionState.done;
              final unavailable = effectiveLocal == null && !waiting && url == null;
              if (unavailable) {
                return _DocumentCard(
                  name: name,
                  type: type,
                  french: french,
                  onTap: null,
                  subtitle: french ? 'Indisponible hors ligne' : 'Unavailable offline',
                );
              }
              if (_isImage) return _imageThumb(context, url, effectiveLocal);
              if (_isAudio) {
                return AudioMessagePlayer(
                  localPath: effectiveLocal,
                  url: url,
                  remotePath: _cacheKey,
                  fileName: name,
                  loading: waiting,
                );
              }
              if (_isVideo) return _videoCard(context, url, effectiveLocal);
              return _DocumentCard(
                name: name,
                type: type,
                french: french,
                onTap: waiting ? null : () => _openDocument(context, url, effectiveLocal),
                subtitle: _isPdf
                    ? (french ? 'PDF • Appuyer pour lire' : 'PDF • Tap to read')
                    : (french ? 'Appuyer pour ouvrir dans Fise School' : 'Tap to open in Fise School'),
              );
            },
          );
        },
      ),
    );
  }

  Widget _imageThumb(BuildContext context, String? url, String? effectiveLocal) {
    final image = effectiveLocal != null && File(effectiveLocal).existsSync()
        ? Image.file(File(effectiveLocal), width: 220, height: 180, fit: BoxFit.cover)
        : (url == null
            ? const SizedBox(width: 220, height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : Image.network(url, width: 220, height: 180, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 180, child: Icon(Icons.broken_image_outlined))));
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaImageViewerPage(
          localPath: effectiveLocal,
          url: url,
          remotePath: _cacheKey,
          title: name ?? '',
        ),
      )),
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
    );
  }

  Widget _videoCard(BuildContext context, String? url, String? effectiveLocal) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaVideoViewerPage(
          localPath: effectiveLocal,
          url: url,
          remotePath: _cacheKey,
          title: name ?? '',
        ),
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

  Future<void> _openDocument(BuildContext context, String? url, String? effectiveLocal) async {
    if (_isPdf) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaPdfViewerPage(
          localPath: effectiveLocal,
          url: url,
          remotePath: _cacheKey,
          title: name ?? 'PDF',
        ),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaDocumentViewerPage(
        localPath: effectiveLocal,
        url: url,
        remotePath: _cacheKey,
        title: name ?? (french ? 'Fichier' : 'File'),
        mimeType: type,
        french: french,
      ),
    ));
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
  const AudioMessagePlayer({super.key, this.localPath, this.url, this.remotePath, this.fileName, this.loading = false});
  final String? localPath;
  final String? url;
  final String? remotePath;
  final String? fileName;
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
    var local = widget.localPath;
    if (local == null || !File(local).existsSync()) {
      local = await _MessageMediaCache.find(
        remotePath: widget.remotePath,
        fileName: widget.fileName,
        url: widget.url,
      );
    }
    if (local != null && File(local).existsSync()) {
      await _player.play(DeviceFileSource(local));
    } else if (widget.url != null) {
      // Start playback immediately; persist the full audio for later offline use.
      unawaited(_MessageMediaCache.download(
        remotePath: widget.remotePath,
        fileName: widget.fileName,
        url: widget.url,
      ).then<void>((_) {}));
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

class MediaImageViewerPage extends StatefulWidget {
  const MediaImageViewerPage({super.key, this.localPath, this.url, this.remotePath, required this.title});
  final String? localPath;
  final String? url;
  final String? remotePath;
  final String title;

  @override
  State<MediaImageViewerPage> createState() => _MediaImageViewerPageState();
}

class _MediaImageViewerPageState extends State<MediaImageViewerPage> {
  String? _cachedPath;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareCache());
  }

  Future<void> _prepareCache() async {
    if (widget.localPath != null && await File(widget.localPath!).exists()) return;
    final cached = await _MessageMediaCache.find(
      remotePath: widget.remotePath,
      fileName: widget.title,
      url: widget.url,
    );
    if (cached != null) {
      if (mounted) setState(() => _cachedPath = cached);
      return;
    }
    final saved = await _MessageMediaCache.download(
      remotePath: widget.remotePath,
      fileName: widget.title,
      url: widget.url,
    );
    if (mounted && saved != null) setState(() => _cachedPath = saved);
  }

  @override
  Widget build(BuildContext context) {
    final local = _cachedPath ??
        ((widget.localPath != null && File(widget.localPath!).existsSync()) ? widget.localPath : null);
    final size = MediaQuery.sizeOf(context);
    final Widget image = local != null
        ? Image.file(
            File(local),
            width: size.width,
            height: size.height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white, size: 64),
          )
        : (widget.url != null
            ? Image.network(
                widget.url!,
                width: size.width,
                height: size.height,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white, size: 64),
              )
            : const Icon(Icons.broken_image_outlined, color: Colors.white, size: 64));
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: SizedBox.expand(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: image,
          ),
        ),
      ),
    );
  }
}

class MediaVideoViewerPage extends StatefulWidget {
  const MediaVideoViewerPage({super.key, this.localPath, this.url, this.remotePath, required this.title});
  final String? localPath;
  final String? url;
  final String? remotePath;
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
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    var local = widget.localPath;
    if (local == null || !await File(local).exists()) {
      local = await _MessageMediaCache.find(
        remotePath: widget.remotePath,
        fileName: widget.title,
        url: widget.url,
      );
    }
    if (local == null && widget.url != null) {
      // Stream the video now; cache it in parallel for the next offline opening.
      unawaited(_MessageMediaCache.download(
        remotePath: widget.remotePath,
        fileName: widget.title,
        url: widget.url,
      ).then<void>((_) {}));
    }
    final VideoPlayerController? c = local != null && await File(local).exists()
        ? VideoPlayerController.file(File(local))
        : (widget.url != null ? VideoPlayerController.networkUrl(Uri.parse(widget.url!)) : null);
    if (c == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() {});
      await c.play();
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
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: _failed || c == null
          ? const Center(child: Icon(Icons.error_outline, color: Colors.white, size: 56))
          : !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: c.value.size.width,
                          height: c.value.size.height,
                          child: VideoPlayer(c),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 20,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8)),
                              ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: c,
                                builder: (_, value, __) => IconButton(
                                  iconSize: 46,
                                  color: Colors.white,
                                  onPressed: () => value.isPlaying ? c.pause() : c.play(),
                                  icon: Icon(value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class MediaPdfViewerPage extends StatefulWidget {
  const MediaPdfViewerPage({super.key, this.localPath, this.url, this.remotePath, required this.title});
  final String? localPath;
  final String? url;
  final String? remotePath;
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
      var local = widget.localPath;
      if (local == null || !await File(local).exists()) {
        local = await _MessageMediaCache.find(
          remotePath: widget.remotePath,
          fileName: widget.title,
          url: widget.url,
        );
      }
      if (local != null && await File(local).exists()) {
        final doc = PdfDocument.openFile(local);
        if (!mounted) return;
        setState(() => _controller = PdfControllerPinch(document: doc));
        return;
      }
      if (widget.url == null) throw Exception('no source');
      final res = await http.get(Uri.parse(widget.url!)).timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('http ${res.statusCode}');
      final key = (widget.remotePath?.isNotEmpty == true) ? widget.remotePath! : widget.url!;
      final savedPath = await _MessageMediaCache.saveBytes(
        remotePath: key,
        fileName: widget.title,
        bytes: res.bodyBytes,
      );
      final doc = PdfDocument.openFile(savedPath);
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

/// In-app document screen. Web-readable formats are rendered in the embedded
/// WebView; text formats are rendered natively. The original file is cached so
/// subsequent opens do not need to download it again.
class MediaDocumentViewerPage extends StatefulWidget {
  const MediaDocumentViewerPage({
    super.key,
    this.localPath,
    this.url,
    this.remotePath,
    required this.title,
    this.mimeType,
    this.french = true,
  });

  final String? localPath;
  final String? url;
  final String? remotePath;
  final String title;
  final String? mimeType;
  final bool french;

  @override
  State<MediaDocumentViewerPage> createState() => _MediaDocumentViewerPageState();
}

class _MediaDocumentViewerPageState extends State<MediaDocumentViewerPage> {
  String? _localPath;
  String? _textContent;
  WebViewController? _webController;
  bool _loading = true;
  bool _failed = false;

  bool get _isTextFile {
    final name = widget.title.toLowerCase();
    return name.endsWith('.txt') || name.endsWith('.csv') ||
        name.endsWith('.json') || name.endsWith('.md') || name.endsWith('.xml');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      var local = widget.localPath;
      if (local == null || !await File(local).exists()) {
        local = await _MessageMediaCache.find(
          remotePath: widget.remotePath,
          fileName: widget.title,
          url: widget.url,
        );
      }
      if (local != null && await File(local).exists()) {
        _localPath = local;
        if (_isTextFile) {
          _textContent = await File(local).readAsString();
        } else if (widget.url == null) {
          if (mounted) setState(() { _loading = false; });
          return;
        }
      }

      if (local != null &&
          (widget.title.toLowerCase().endsWith('.html') || widget.title.toLowerCase().endsWith('.htm'))) {
        final controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.loadFile(local);
        _webController = controller;
      } else if (local == null && widget.url != null) {
        final controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.loadRequest(Uri.parse(widget.url!));
        _webController = controller;
        unawaited(_cacheInBackground());
      } else if (local == null) {
        throw Exception('no source');
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() { _failed = _localPath == null; _loading = false; });
    }
  }

  Future<void> _cacheInBackground() async {
    final saved = await _MessageMediaCache.download(
      remotePath: widget.remotePath,
      fileName: widget.title,
      url: widget.url,
    );
    if (mounted && saved != null) setState(() => _localPath = saved);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? Center(child: Text(widget.french ? 'Impossible d’ouvrir ce fichier.' : 'Unable to open this file.'))
                : _textContent != null
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(_textContent!),
                      )
                    : _webController != null
                        ? WebViewWidget(controller: _webController!)
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.insert_drive_file_outlined, size: 56),
                                  const SizedBox(height: 12),
                                  Text(widget.title, textAlign: TextAlign.center),
                                  const SizedBox(height: 8),
                                  Text(widget.french
                                      ? 'Fichier conservé sur cet appareil. L’aperçu intégré de ce format n’est pas disponible.'
                                      : 'File saved on this device. An embedded preview for this format is unavailable.'),
                                ],
                              ),
                            ),
                          ),
      );
}
