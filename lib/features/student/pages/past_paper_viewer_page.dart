import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Displays exam papers inside Fise School instead of sending students to a browser.
class PastPaperViewerPage extends StatefulWidget {
  final String title;
  final Uint8List bytes;
  final bool isPdf;

  const PastPaperViewerPage({
    super.key,
    required this.title,
    required this.bytes,
    required this.isPdf,
  });

  @override
  State<PastPaperViewerPage> createState() => _PastPaperViewerPageState();
}

class _PastPaperViewerPageState extends State<PastPaperViewerPage> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isPdf) {
      try {
        _controller = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));
      } catch (e) {
        _error = e.toString();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: widget.isPdf
            ? _error != null
                ? Center(child: Text(_error!))
                : _controller == null
                    ? const Center(child: CircularProgressIndicator())
                    : PdfViewPinch(controller: _controller!)
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(child: Image.memory(widget.bytes, fit: BoxFit.contain)),
              ),
      );
}
