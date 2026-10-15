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
  AudioPlayer? _audioPlayer;
  PdfControllerPinch? _pdfController;

  bool get _fr => widget.locale.languageCode != 'en';

  /// Les anciennes ressources peuvent avoir un resource_type générique.
  /// Déduire le lecteur du type MIME et du nom de fichier évite d'afficher
  /// le message « pas de lecteur » pour un PDF, une image, un audio ou une vidéo.
  String get _effectiveType {
    final declared = widget.resource.resourceType.toLowerCase().trim();
    final mime = (widget.resource.mimeType ?? '').toLowerCase().trim();
    final name = widget.resource.fileName.toLowerCase();
    if (declared == 'pdf' || mime == 'application/pdf' || name.endsWith('.pdf')) return 'pdf';
    if (declared == 'image' || mime.startsWith('image/') ||
        RegExp(r'\\.(jpg|jpeg|png|gif|webp|heic|bmp)

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && _effectiveType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath!));
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
    switch (_effectiveType) {
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Ce type de fichier ne possède pas encore de lecteur intégré.' : 'This file type does not have an integrated viewer yet.'),
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
).hasMatch(name)) return 'image';
    if (declared == 'audio' || mime.startsWith('audio/') ||
        RegExp(r'\\.(mp3|m4a|aac|wav|ogg|opus|flac)

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && widget.resource.resourceType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath!));
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Ce type de fichier ne possède pas encore de lecteur intégré.' : 'This file type does not have an integrated viewer yet.'),
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
).hasMatch(name)) return 'audio';
    if (declared == 'video' || mime.startsWith('video/') ||
        RegExp(r'\\.(mp4|mov|mkv|webm|3gp|avi|m4v)

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && widget.resource.resourceType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath!));
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Ce type de fichier ne possède pas encore de lecteur intégré.' : 'This file type does not have an integrated viewer yet.'),
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
).hasMatch(name)) return 'video';
    if (declared == 'text' || mime.startsWith('text/') ||
        RegExp(r'\\.(txt|csv|json|xml|md)

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && widget.resource.resourceType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath!));
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Ce type de fichier ne possède pas encore de lecteur intégré.' : 'This file type does not have an integrated viewer yet.'),
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
).hasMatch(name)) return 'text';
    return declared;
  }

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null && widget.resource.resourceType == 'pdf') {
      _pdfController = PdfControllerPinch(document: PdfDocument.openFile(widget.localPath!));
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
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_fr ? 'Ce type de fichier ne possède pas encore de lecteur intégré.' : 'This file type does not have an integrated viewer yet.'),
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
