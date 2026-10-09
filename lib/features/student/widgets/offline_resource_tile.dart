import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/offline/app_database.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

class OfflineResourceTile extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final CourseResource resource;

  const OfflineResourceTile({super.key, required this.locale, required this.profile, required this.resource});

  @override
  State<OfflineResourceTile> createState() => _OfflineResourceTileState();
}

class _OfflineResourceTileState extends State<OfflineResourceTile> {
  final CourseOfflineService _offline = CourseOfflineService();
  final ResourceService _resources = ResourceService();
  StreamSubscription<OfflineDownloadProgress>? _subscription;
  OfflineDownloadProgress? _progress;
  DownloadedFileRecord? _local;
  String? _signedUrl;
  bool _loading = true;

  bool get _fr => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = _offline.progressStream.listen((event) {
      if (event.resourceId != widget.resource.id || !mounted) {
        return;
      }
      setState(() => _progress = event);
      if (event.status == 'done') {
        _load();
      }
    });
  }

  Future<void> _load() async {
    final local = await _offline.getLocal(widget.profile.id, widget.resource.id);
    if (mounted) {
      setState(() { _local = local; _loading = false; });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    var localPath = _local?.localPath;
    final localExists = localPath != null &&
        _local?.status == 'done' &&
        File(localPath).existsSync();

    try {
      if (!localExists) {
        if (widget.resource.storagePath.isEmpty) {
          throw StateError('offline-only');
        }
        _signedUrl ??= await _resources.createSignedUrl(widget.resource.storagePath);
        final signedUrl = _signedUrl;
        if (signedUrl == null || signedUrl.isEmpty) {
          throw StateError('signed-url-unavailable');
        }

        // Download the private Supabase file to a temporary local file and
        // open it with the in-app viewer instead of leaving the application.
        final response = await http.get(Uri.parse(signedUrl));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Resource download failed: ${response.statusCode}');
        }
        final tempDir = await getTemporaryDirectory();
        final safeName = p.basename(widget.resource.fileName).replaceAll(
          RegExp(r'[^A-Za-z0-9._-]'),
          '_',
        );
        final file = File(p.join(
          tempDir.path,
          'fise_preview_${widget.resource.id}_$safeName',
        ));
        await file.writeAsBytes(response.bodyBytes, flush: true);
        localPath = file.path;
      } else {
        await _offline.markOpened(widget.profile.id, widget.resource.id);
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfflineResourceViewer(
            locale: widget.locale,
            userId: widget.profile.id,
            resource: widget.resource,
            localPath: localPath,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _fr
                  ? 'Impossible d’ouvrir ce fichier. Vérifie ta connexion puis réessaie.'
                  : 'Unable to open this file. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _download() async {
    await _offline.queueResource(userId: widget.profile.id, resource: widget.resource, manual: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    final done = _local?.status == 'done' && _local?.localPath != null && File(_local!.localPath).existsSync();
    final progress = _progress;
    IconData icon = Icons.insert_drive_file_rounded;
    if (resource.resourceType == 'pdf') {
      icon = Icons.picture_as_pdf_rounded;
    }
    if (resource.resourceType == 'image') {
      icon = Icons.image_rounded;
    }
    if (resource.resourceType == 'video') {
      icon = Icons.videocam_rounded;
    }
    if (resource.resourceType == 'audio') {
      icon = Icons.audiotrack_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F2), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF166534)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(resource.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (done) ...[
            const SizedBox(height: 3),
            Text(_fr ? 'Disponible hors ligne' : 'Available offline', style: const TextStyle(fontSize: 11, color: Color(0xFF166534), fontWeight: FontWeight.w600)),
          ] else if (progress?.status == 'downloading') ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: 2),
            Text(_fr ? 'Téléchargement…' : 'Downloading…', style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ] else if (progress?.status == 'failed' || _local?.status == 'failed')
            Text(_fr ? 'Échec — appuyez pour réessayer' : 'Failed — tap to retry', style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
        ])),
        const SizedBox(width: 6),
        if (_loading) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else if (done)
          IconButton(onPressed: _open, tooltip: _fr ? 'Ouvrir' : 'Open', icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF166534)))
        else
          IconButton(onPressed: _download, tooltip: _fr ? 'Télécharger' : 'Download', icon: const Icon(Icons.download_rounded, color: Color(0xFF166534))),
      ]),
    );
  }
}
