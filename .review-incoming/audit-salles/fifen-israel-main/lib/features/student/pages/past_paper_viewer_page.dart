import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

class PastPaperViewerPage extends StatefulWidget {
  final Locale locale;
  final String localPath;
  final String fileName;

  const PastPaperViewerPage({
    super.key,
    required this.locale,
    required this.localPath,
    required this.fileName,
  });

  @override
  State<PastPaperViewerPage> createState() => _PastPaperViewerPageState();
}

class _PastPaperViewerPageState extends State<PastPaperViewerPage> {
  PdfControllerPinch? _pdfController;
  bool _openingExternal = false;

  bool get _fr => widget.locale.languageCode != 'en';
  bool get _isPdf => widget.fileName.toLowerCase().endsWith('.pdf');
  bool get _isImage => RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false)
      .hasMatch(widget.fileName);

  @override
  void initState() {
    super.initState();
    if (_isPdf && File(widget.localPath).existsSync()) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.localPath),
      );
    }
    if (!_isPdf && !_isImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openExternal());
    }
  }

  Future<void> _openExternal() async {
    if (_openingExternal) return;
    _openingExternal = true;
    final ok = await launchUrl(
      Uri.file(widget.localPath),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_fr
            ? 'Aucune application compatible pour ce type de fichier.'
            : 'No compatible app found for this file type.'),
      ));
    }
    _openingExternal = false;
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.localPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: !file.existsSync()
          ? Center(child: Text(_fr
              ? 'Le fichier téléchargé est introuvable.'
              : 'Downloaded file not found.'))
          : _isPdf
              ? (_pdfController == null
                  ? const Center(child: CircularProgressIndicator())
                  : PdfViewPinch(controller: _pdfController!))
              : _isImage
                  ? Center(
                      child: InteractiveViewer(
                        child: Image.file(file, fit: BoxFit.contain),
                      ),
                    )
                  : Center(
                      child: FilledButton.icon(
                        onPressed: _openExternal,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(_fr ? 'Ouvrir le document' : 'Open document'),
                      ),
                    ),
    );
  }
}
