import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 56, color: Color(0xFF166534)),
                const SizedBox(height: 12),
                Text(_fr
                    ? 'Ce document est enregistré sur le téléphone. Ouvre-le avec une application compatible.'
                    : 'This document is saved on the phone. Open it with a compatible app.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(
                      Uri.file(path),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(_fr
                            ? 'Aucune application compatible pour ce document.'
                            : 'No compatible app found for this document.'),
                      ));
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_fr ? 'Ouvrir le document' : 'Open document'),
                ),
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
