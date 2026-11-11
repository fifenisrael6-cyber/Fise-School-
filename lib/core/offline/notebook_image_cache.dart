import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cache local partagé des images intégrées aux pages des cahiers.
class NotebookImageCache {
  static String _key(String path) {
    var hash = 2166136261;
    for (final unit in path.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static Future<File> fileFor({
    required String userId,
    required String storagePath,
  }) async {
    final base = await getApplicationSupportDirectory();
    final safeUser = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(
      base.path,
      'offline',
      'notebook_pages',
      safeUser,
      '${_key(storagePath)}.bin',
    ));
  }

  static Future<File?> getCached({
    required String userId,
    required String storagePath,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;
    final file = await fileFor(userId: userId, storagePath: path);
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  static Future<File?> download({
    required String userId,
    required String storagePath,
    SupabaseClient? client,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;
    final existing = await getCached(userId: userId, storagePath: path);
    if (existing != null) return existing;
    final db = client ?? Supabase.instance.client;
    final destination = await fileFor(userId: userId, storagePath: path);
    final temporary = File('${destination.path}.part');
    try {
      final url = await db.storage.from('chapter-content').createSignedUrl(path, 900);
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        return null;
      }
      await destination.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      return destination;
    } catch (_) {
      if (await temporary.exists()) {
        try { await temporary.delete(); } catch (_) {}
      }
      return null;
    }
  }
}
