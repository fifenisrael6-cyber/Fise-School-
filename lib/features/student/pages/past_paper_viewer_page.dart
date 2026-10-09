import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

/// Ouvre une annale dans Fise School au lieu de quitter l'application.
class PastPaperViewerPage extends StatefulWidget {
  const PastPaperViewerPage({
    super.key,
    required this.url,
    required this.title,
    required this.isPdf,
  });

  final String url;
  final String title;
  final bool isPdf;

  @override
  State<PastPaperViewerPage> createState() => _PastPaperViewerPageState();
}

class _PastPaperViewerPageState extends State<PastPaperViewerPage> {
  Uint8List? _bytes;
  PdfControllerPinch? _pdfController;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) throw Exception('Fichier vide');
      if (widget.isPdf) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openData(bytes),
        );
      }
      if (!mounted) {
        _pdfController?.dispose();
        return;
      }
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Impossible d’ouvrir ce document. Vérifiez votre connexion ou le fichier dans Supabase.';
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
                        child: Image.memory(_bytes!, fit: BoxFit.contain),
                      ),
                    ),
    );
  }
}
