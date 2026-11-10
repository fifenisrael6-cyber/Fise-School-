import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Renders inline course images stored as data URIs in the Quill Delta.
/// Base64 keeps the illustration available offline and independent of the
/// original PDF or a temporary signed Supabase URL.
class CourseImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data.toString();
    final theme = Theme.of(context);
    Widget image;

    if (source.startsWith('data:image/')) {
      try {
        final separator = source.indexOf(',');
        if (separator < 0) throw const FormatException('Invalid image data URI');
        final bytes = base64Decode(source.substring(separator + 1));
        image = Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _imageError(theme),
        );
      } catch (_) {
        image = _imageError(theme);
      }
    } else {
      image = Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _imageError(theme),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 420, minHeight: 72),
          alignment: Alignment.center,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35),
          padding: const EdgeInsets.all(8),
          child: image,
        ),
      ),
    );
  }

  Widget _imageError(ThemeData theme) => Container(
        constraints: const BoxConstraints(minHeight: 72),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Icon(Icons.broken_image_outlined,
            color: theme.colorScheme.onSurfaceVariant, size: 30),
      );
}
