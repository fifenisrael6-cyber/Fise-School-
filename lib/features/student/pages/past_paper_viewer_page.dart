import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/offline/course_offline_service.dart';

/// Ouvre une annale dans Fise School et conserve la copie après sa première ouverture.
class PastPaperViewerPage extends StatefulWidget {
  const PastPaperViewerPage({
    super.key,
    required this.userId,
    required this.resourceId,
    required this.signedUrlProvider,
    required this.title,
    required this.isPdf,
  });

  final String userId;
  final String resourceId;
  final Future<String> Function() signedUrlProvider;
  final String title;
  final bool isPdf;

  @override
  State<PastPaperViewerPage> createState() => _PastPaperViewerPageState();
}

class _PastPaperViewerPageState extends State<PastPaperViewerPage> {
  String? _localPath;
  PdfControllerPinch? _pdfController;
  String? _error;
  bool _loading = true;

  String get _imageMime {
    final name = widget.title.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final localPath = await CourseOfflineService().openExternalFile(
        userId: widget.userId,
        resourceId: widget.resourceId,
        courseId: 'past-papers',
        fileName: widget.title,
        mimeType: widget.isPdf ? 'application/pdf' : _imageMime,
        signedUrlProvider: widget.signedUrlProvider,
      );
      final controller = widget.isPdf
          ? PdfControllerPinch(document: PdfDocument.openFile(localPath))
          : null;
      if (!mounted) {
        controller?.dispose();
        return;
      }
      setState(() {
        _localPath = localPath;
        _pdfController = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Impossible d’ouvrir ce document. Connectez-vous pour le télécharger une première fois.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = _localPath;
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
              : widget.isPdf
                  ? PdfViewPinch(controller: _pdfController!)
                  : InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5,
                      child: Center(
                        child: Image.file(File(path!), fit: BoxFit.contain),
                      ),
                    ),
    );
  }
}
