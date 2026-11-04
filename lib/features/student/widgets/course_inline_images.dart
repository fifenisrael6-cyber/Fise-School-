import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';

/// Affiche les images déjà publiées avec le cours ou la leçon directement
/// dans la page de contenu. Les fichiers téléchargés sont lus depuis le cache
/// local avant toute tentative d'accès réseau.
class CourseInlineImages extends StatelessWidget {
  final Locale locale;
  final String userId;
  final List<CourseResource> resources;

  const CourseInlineImages({
    super.key,
    required this.locale,
    required this.userId,
    required this.resources,
  });

  @override
  Widget build(BuildContext context) {
    final images = resources
        .where((resource) => resource.resourceType == 'image')
        .toList(growable: false);

    if (images.isEmpty) return const SizedBox.shrink();

    final isEnglish = locale.languageCode == 'en';

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEnglish ? 'ILLUSTRATIONS AND FIGURES' : 'ILLUSTRATIONS ET FIGURES',
            style: const TextStyle(
              color: Color(0xFF166534),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          for (final resource in images)
            _InlineCourseImage(
              key: ValueKey(resource.id),
              locale: locale,
              userId: userId,
              resource: resource,
            ),
        ],
      ),
    );
  }
}

class _InlineCourseImage extends StatefulWidget {
  final Locale locale;
  final String userId;
  final CourseResource resource;

  const _InlineCourseImage({
    super.key,
    required this.locale,
    required this.userId,
    required this.resource,
  });

  @override
  State<_InlineCourseImage> createState() => _InlineCourseImageState();
}

class _InlineCourseImageState extends State<_InlineCourseImage> {
  final CourseOfflineService _offline = CourseOfflineService();
  final ResourceService _resourceService = ResourceService();
  final ConnectivityService _connectivity = ConnectivityService();

  String? _localPath;
  String? _signedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _InlineCourseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.id != widget.resource.id ||
        oldWidget.userId != widget.userId) {
      _localPath = null;
      _signedUrl = null;
      _loading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    DownloadedFileRecord? local;
    try {
      local = await _offline.getLocal(widget.userId, widget.resource.id);
    } catch (_) {
      // A cache read error must not prevent the online image fallback.
    }

    if (local != null &&
        local.status == 'done' &&
        File(local.localPath).existsSync()) {
      if (!mounted) return;
      setState(() {
        _localPath = local!.localPath;
        _signedUrl = null;
        _loading = false;
      });
      return;
    }

    String? signedUrl;
    if (widget.resource.storagePath.trim().isNotEmpty) {
      try {
        if (await _connectivity.isOnline()) {
          signedUrl = await _resourceService.createSignedUrl(
            widget.resource.storagePath,
            expiresIn: 3600,
          );
        }
      } catch (_) {
        // Keep a clear offline placeholder when no valid image source exists.
      }
    }

    if (!mounted) return;
    setState(() {
      _localPath = null;
      _signedUrl = signedUrl;
      _loading = false;
    });
  }

  Widget _buildImage({double? height}) {
    final localPath = _localPath;
    if (localPath != null) {
      return Image.file(
        File(localPath),
        width: double.infinity,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildImageFallback(),
      );
    }

    final signedUrl = _signedUrl;
    if (signedUrl != null) {
      return Image.network(
        signedUrl,
        width: double.infinity,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildImageFallback(),
      );
    }

    return _buildImageFallback();
  }

  Widget _buildImageFallback() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined,
              color: Color(0xFF78909C), size: 30),
          const SizedBox(height: 6),
          Text(
            widget.locale.languageCode == 'en'
                ? 'Image unavailable. Download this resource while online to view it offline.'
                : 'Image indisponible. Téléchargez cette ressource en ligne pour la consulter hors connexion.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _openPreview() {
    if (_localPath == null && _signedUrl == null) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.of(dialogContext).size;
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: size.width,
            height: size.height * 0.78,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(child: _buildImage(height: size.height * 0.72)),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: widget.locale.languageCode == 'en' ? 'Close' : 'Fermer',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    final title = widget.locale.languageCode == 'en'
        ? widget.resource.titleEn
        : widget.resource.titleFr;
    final caption = title.trim().isNotEmpty
        ? title.trim()
        : widget.resource.fileName;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7DFC9)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _openPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 90, maxHeight: 290),
                color: const Color(0xFFF8FAFC),
                alignment: Alignment.center,
                child: _buildImage(height: 270),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
