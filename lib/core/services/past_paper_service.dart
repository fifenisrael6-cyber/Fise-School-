import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/past_paper.dart';
import '../offline/json_cache.dart';

class PastPaperService {
  PastPaperService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const bucket = 'past-papers';

  Future<List<PastPaper>> list({bool includeUnpublished = false}) {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    return JsonCache.instance.cachedRead<List<PastPaper>>(
      key: 'past_papers_${userId}_${includeUnpublished ? 'all' : 'published'}',
      fetch: () async {
        var query = _client.from('past_papers').select();
        if (!includeUnpublished) {
          query = query.eq('is_published', true);
        }
        return await query
            .order('exam_year', ascending: false)
            .order('subject_fr') as Object?;
      },
      decode: (raw) => (raw as List)
          .map((row) => PastPaper.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false),
    );
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(bucket).createSignedUrl(path, 3600);

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
    if (examId == null || examId.trim().isEmpty) {
      throw ArgumentError('Une annale doit être associée à un examen.');
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fichier illisible ou vide.');
    }
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}/${_safeName(file.name)}';
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
        'is_published': false,
      }).select('id').single();
      paperId = row['id'].toString();
      // Les annales d'examen sont diffusées par examen, pas par salle.
      // Les anciennes cibles restent possibles pour les appels d'administration
      // qui les utilisent encore; l'enseignant ne fournit plus de cibles de salles.
      if (classIds.isNotEmpty) {
        await setTargets(paperId, classIds);
      }
      await setPublished(paperId, true);
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
    final updated = await _client
        .from('past_papers')
        .update({
          'is_published': published,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw StateError(
        'Publication refusée : vérifiez les salles destinataires et vos autorisations.',
      );
    }
  }

  Future<void> updateMetadata({
    required String id,
    required String examId,
    required String subsystem,
    required int year,
    required String subjectFr,
    required String subjectEn,
    required String kind,
    String? session,
  }) async {
    if (examId.trim().isEmpty) {
      throw ArgumentError('Une annale doit être associée à un examen.');
    }
    if (year < 1990 || year > 2100) {
      throw ArgumentError('Année d’épreuve invalide.');
    }
    if (subjectFr.trim().isEmpty) {
      throw ArgumentError('La matière est obligatoire.');
    }

    final updated = await _client
        .from('past_papers')
        .update({
          'exam_id': examId,
          'subsystem': subsystem,
          'exam_year': year,
          'session_label': (session == null || session.trim().isEmpty)
              ? null
              : session.trim(),
          'subject_fr': subjectFr.trim(),
          'subject_en': subjectEn.trim().isEmpty
              ? subjectFr.trim()
              : subjectEn.trim(),
          'kind': kind,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id')
        .maybeSingle();

    if (updated == null) {
      throw StateError(
        'Modification refusée : vérifiez vos autorisations et le sous-système de l’examen.',
      );
    }
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
