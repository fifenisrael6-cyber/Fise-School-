import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/past_paper.dart';
import '../offline/json_cache.dart';
import '../offline/connectivity_service.dart';

class PastPaperService {
  PastPaperService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const bucket = 'past-papers';
  static const _timeout = Duration(seconds: 3);

  String _cacheKey() => 'past_papers_${_client.auth.currentUser?.id ?? 'signed_out'}';

  Future<List<PastPaper>> list({bool includeUnpublished = false}) async {
    final key = _cacheKey();
    if (!await ConnectivityService().isOnline()) {
      final cached = await JsonCache.instance.read(key);
      if (cached is List) {
        return cached.whereType<Map>()
            .map((row) => PastPaper.fromMap(Map<String, dynamic>.from(row)))
            .where((paper) => includeUnpublished || paper.isPublished)
            .toList(growable: false);
      }
    }
    try {
      var query = _client.from('past_papers').select();
      if (!includeUnpublished) {
        query = query.eq('is_published', true);
      }
      final rows = await query
          .order('exam_year', ascending: false)
          .order('subject_fr')
          .timeout(_timeout);
      final raw = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      try {
        await JsonCache.instance.write(key, raw);
      } catch (_) {}
      return raw.map(PastPaper.fromMap).toList(growable: false);
    } catch (_) {
      final cached = await JsonCache.instance.read(key);
      if (cached is List) {
        final papers = cached
            .whereType<Map>()
            .map((row) => PastPaper.fromMap(Map<String, dynamic>.from(row)))
            .where((paper) => includeUnpublished || paper.isPublished)
            .toList(growable: false);
        return papers;
      }
      rethrow;
    }
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(bucket).createSignedUrl(path, 3600).timeout(_timeout);

  Future<String?> localFilePath(PastPaper paper) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'fise_past_papers',
          _client.auth.currentUser?.id ?? 'signed_out'));
      final safe = paper.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File(p.join(dir.path, '${paper.id}_$safe'));
      if (await file.exists() && await file.length() > 0) return file.path;
    } catch (_) {}
    return null;
  }

  Future<String> download(PastPaper paper) async {
    final existing = await localFilePath(paper);
    if (existing != null) return existing;
    final url = await signedUrl(paper.filePath);
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
      throw HttpException('Téléchargement du document impossible (HTTP ${response.statusCode}).');
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'fise_past_papers',
        _client.auth.currentUser?.id ?? 'signed_out'));
    await dir.create(recursive: true);
    final safe = paper.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(p.join(dir.path, '${paper.id}_$safe'));
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  String _contentType(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> create({
    required PlatformFile file,
    required int year,
    required String subjectFr,
    required String subjectEn,
    required String kind,
    String? examId,
    String? subsystem,
    String? session,
    List<String> classIds = const [],
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Session utilisateur absente.');
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fichier illisible ou vide.');
    }
    final path =
        '${DateTime.now().millisecondsSinceEpoch}/${_safeName(file.name)}';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(file.extension),
            upsert: false,
          ),
        );
    String? paperId;
    try {
      final row = await _client.from('past_papers').insert({
        'exam_id': examId,
        'subsystem': subsystem,
        'exam_year': year,
        'session_label': (session == null || session.trim().isEmpty)
            ? null
            : session.trim(),
        'subject_fr': subjectFr.trim(),
        'subject_en': subjectEn.trim().isEmpty ? subjectFr.trim() : subjectEn.trim(),
        'kind': kind,
        'file_path': path,
        'file_name': file.name,
        'created_by': user.id,
      }).select('id').single();
      paperId = row['id'].toString();
      // Liste vide = visible par toutes les salles.
      await setTargets(paperId, classIds);
    } catch (_) {
      // Nettoyage : ne pas laisser un fichier orphelin ni une annale ouverte à tous
      // si l'enregistrement des salles échoue.
      if (paperId != null) {
        try {
          await _client.from('past_papers').delete().eq('id', paperId);
        } catch (_) {}
      }
      try {
        await _client.storage.from(bucket).remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> setPublished(String id, bool published) async {
    await _client
        .from('past_papers')
        .update({'is_published': published, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> delete(PastPaper paper) async {
    await _client.from('past_papers').delete().eq('id', paper.id);
    try {
      await _client.storage.from(bucket).remove([paper.filePath]);
    } catch (_) {}
  }

  /// Salles ciblées par annale (paper_id -> class ids). Absent = toutes les salles.
  Future<Map<String, List<String>>> listTargets() async {
    final rows = await _client.from('past_paper_classes').select('paper_id, class_id');
    final result = <String, List<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['paper_id'].toString(), () => <String>[])
          .add(row['class_id'].toString());
    }
    return result;
  }

  /// Remplace les salles de diffusion. Liste vide = toutes les salles.
  Future<void> setTargets(String paperId, List<String> classIds) async {
    await _client.from('past_paper_classes').delete().eq('paper_id', paperId);
    if (classIds.isEmpty) {
      return;
    }
    await _client.from('past_paper_classes').insert([
      for (final classId in classIds) {'paper_id': paperId, 'class_id': classId},
    ]);
  }
}
