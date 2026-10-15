import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/offline/app_database.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_resource_viewer.dart';
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
  StreamSubscription<OfflineDownloadProgress>? _subscription;
  OfflineDownloadProgress? _progress;
  DownloadedFileRecord? _local;
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
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // À la première ouverture, le fichier est téléchargé vers le stockage
      // durable de Fise School. Ensuite, les ouvertures utilisent cette copie.
      final localPath = await _offline.openResource(
        userId: widget.profile.id,
        resource: widget.resource,
      );
      await _load();
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
                  ? 'Ce fichier doit être ouvert une première fois avec Internet pour rester disponible hors ligne.'
                  : 'Open this file once while online to keep it available offline.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        if (_loading)
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          IconButton(
            onPressed: _open,
            tooltip: _fr ? 'Ouvrir dans l’application' : 'Open in app',
            icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF166534)),
          ),
        ],
      ]),
    );
  }
}
