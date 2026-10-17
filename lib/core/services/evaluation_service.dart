import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../offline/json_cache.dart';
import '../../models/evaluation.dart';
import 'free_tier_service.dart';

/// Accès au système d'évaluation automatisée. Aucune clé secrète ici : toutes les
/// autorisations sont imposées par les politiques RLS et les fonctions SQL de Supabase.
class EvaluationService {
  EvaluationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _papers = 'evaluation-papers';
  static const _photos = 'evaluation-photos';

  /// Message lisible pour l'utilisateur à partir d'une erreur Supabase.
  static String friendlyError(Object error, {bool fr = true}) {
    var message = error is PostgrestException
        ? error.message
        : error is StorageException
            ? error.message
            : error.toString();
    if (message.contains('DEADLINE_PASSED')) {
      return fr
          ? 'La date limite est dépassée : la remise n\'est plus acceptée.'
          : 'The deadline has passed: submissions are closed.';
    }
    message = message.replaceFirst('Exception: ', '');
    return message;
  }

  // ---------------------------------------------------------------- Élève --

  Future<StudentEvaluationList> listMine() async {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    final result = await JsonCache.instance.cachedRead<StudentEvaluationList>(
      key: 'student_evaluations_$userId',
      fetch: () async => await _client.rpc('list_my_evaluations') as Object?,
      decode: (raw) => StudentEvaluationList.fromMap(
        Map<String, dynamic>.from(raw as Map),
      ),
    );
    try {
      final profile = await _client.from('profiles').select('role')
          .eq('id', userId).maybeSingle();
      if (profile?['role'] != 'student') return result;
      final premium = await _client.rpc(
        'is_student_premium',
        params: {'p_user_id': userId},
      );
      if (premium == true) return result;
      final freeTier = FreeTierService(client: _client);
      final previouslyGranted = await freeTier.cachedResourceIds('evaluation');
      final ordered = [...result.items]..sort((a, b) {
        final aGranted = previouslyGranted.contains(a.id);
        final bGranted = previouslyGranted.contains(b.id);
        if (aGranted == bGranted) return 0;
        return aGranted ? -1 : 1;
      });
      final allowedIds = <String>{};
      for (final evaluation in ordered) {
        if (await freeTier.consume('evaluation', evaluation.id)) {
          allowedIds.add(evaluation.id);
        } else {
          break;
        }
      }
      final allowed = result.items.where((evaluation) => allowedIds.contains(evaluation.id)).toList(growable: false);
      return StudentEvaluationList(serverOffset: result.serverOffset, items: allowed);
    } catch (_) {
      return const StudentEvaluationList(serverOffset: Duration.zero, items: []);
    }
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<({String path, String name})?> teacherPaper(String evaluationId) async {
    final row = await _client
        .from('evaluations')
        .select('pdf_path,pdf_name')
        .eq('id', evaluationId)
        .maybeSingle();
    final path = row?['pdf_path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final rawName = row?['pdf_name']?.toString().trim() ?? '';
    return (path: path, name: rawName.isEmpty ? 'evaluation.pdf' : rawName);
  }

  Future<String> openPaperUrl(String path) {
    return _client.storage.from(_papers).createSignedUrl(path, 900);
  }

  Future<String> startSubmission(String evaluationId) async {
    final id = await _client.rpc('start_evaluation_submission', params: {'p_evaluation': evaluationId});
    return id.toString();
  }

  /// Envoie une photographie dans le stockage privé puis l'enregistre pour la remise.
  Future<({String photoId, String path})> uploadPhoto({
    required String evaluationId,
    required Uint8List bytes,
    required String extension,
    required int position,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Session utilisateur absente.');
    final ext = extension.toLowerCase().replaceAll('.', '');
    final safeExt = const ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
    final contentType = safeExt == 'png'
        ? 'image/png'
        : safeExt == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final name = '${DateTime.now().microsecondsSinceEpoch}_$position.$safeExt';
    final path = '$evaluationId/$uid/$name';
    await _client.storage.from(_photos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    final photoId = await _client.rpc('register_evaluation_photo', params: {
      'p_evaluation': evaluationId,
      'p_path': path,
      'p_position': position,
    });
    return (photoId: photoId.toString(), path: path);
  }

  Future<List<ReviewPhoto>> listMyPhotos(String submissionId) {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    return JsonCache.instance.cachedRead<List<ReviewPhoto>>(
      key: 'evaluation_photos_${userId}_$submissionId',
      fetch: () async => await _client
          .from('evaluation_photos')
          .select('id,storage_path,position')
          .eq('submission_id', submissionId)
          .order('position') as Object?,
      decode: (raw) => (raw as List)
          .map((r) => ReviewPhoto(
                id: r['id'].toString(),
                storagePath: r['storage_path'].toString(),
                position: (r['position'] as num?)?.toInt() ?? 1,
              ))
          .toList(growable: false),
    );
  }

  Future<void> removePhoto({required String photoId, required String path}) async {
    await _client.rpc('remove_evaluation_photo', params: {'p_photo': photoId});
    try {
      await _client.storage.from(_photos).remove([path]);
    } catch (_) {
      // Le fichier orphelin est sans effet : la remise ne le référence plus.
    }
  }

  Future<EvalSubmissionInfo> submit(String evaluationId) async {
    final data = await _client.rpc('submit_evaluation', params: {'p_evaluation': evaluationId});
    final map = Map<String, dynamic>.from(data as Map);
    return EvalSubmissionInfo(
      id: '',
      status: 'submitted',
      submittedAt: DateTime.tryParse(map['submitted_at']?.toString() ?? '')?.toLocal(),
      isLate: map['is_late'] == true,
      lateMinutes: (map['late_minutes'] as num?)?.toInt() ?? 0,
    );
  }

  // ----------------------------------------------------------- Enseignant --

  Future<List<TeacherEvaluation>> listTeacherEvaluations({bool forceRefresh = false}) async {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    final cacheKey = 'teacher_evaluations_$userId';

    Future<Object?> fetch() async =>
        await _client.rpc('list_teacher_evaluations') as Object?;
    List<TeacherEvaluation> decode(Object? raw) => (raw as List)
        .map((e) => TeacherEvaluation.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);

    // L'écran d'administration doit pouvoir actualiser les erreurs Gemini
    // depuis le serveur au lieu d'afficher une copie hors ligne potentiellement ancienne.
    if (forceRefresh) {
      final raw = await fetch().timeout(const Duration(seconds: 12));
      try {
        await JsonCache.instance.write(cacheKey, raw);
      } catch (_) {
        // Le cache ne doit pas empêcher l'affichage d'un résultat réseau valide.
      }
      return decode(raw);
    }

    return JsonCache.instance.cachedRead<List<TeacherEvaluation>>(
      key: cacheKey,
      fetch: fetch,
      decode: decode,
    );
  }

  /// Crée l'épreuve, téléverse le PDF, enregistre barème/critères et classes, puis publie.
  /// En cas d'échec, le brouillon et le fichier sont supprimés (pas de demi-publication).
  Future<String> createAndPublish({
    required String teacherId,
    required String subjectId,
    required List<String> classIds,
    required String title,
    String? instructions,
    required DateTime startsAt,
    required DateTime dueAt,
    int? durationMinutes,
    required String latePolicy,
    int lateGraceMinutes = 5,
    double latePenaltyPercent = 0,
    double maxScore = 20,
    double weight = 1,
    String? periodId,
    DateTime? resultsVisibleAt,
    required Uint8List pdfBytes,
    required String pdfName,
    List<Map<String, dynamic>> scheme = const [],
    String? criteria,
  }) async {
    final inserted = await _client
        .from('evaluations')
        .insert({
          'teacher_id': teacherId,
          'subject_id': subjectId,
          'period_id': periodId,
          'title': title.trim(),
          'instructions': (instructions ?? '').trim().isEmpty ? null : instructions!.trim(),
          'starts_at': startsAt.toUtc().toIso8601String(),
          'due_at': dueAt.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          'late_policy': latePolicy,
          'late_grace_minutes': lateGraceMinutes,
          'late_penalty_percent': latePenaltyPercent,
          'max_score': maxScore,
          'weight': weight,
          'results_visible_at': resultsVisibleAt?.toUtc().toIso8601String(),
          'status': 'draft',
        })
        .select('id')
        .single();
    final id = inserted['id'].toString();
    final pdfPath = '$teacherId/$id.pdf';
    var uploaded = false;
    try {
      await _client.storage.from(_papers).uploadBinary(
            pdfPath,
            pdfBytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
          );
      uploaded = true;
      await _client.from('evaluations').update({
        'pdf_path': pdfPath,
        'pdf_name': pdfName,
      }).eq('id', id);
      if (scheme.isNotEmpty || (criteria ?? '').trim().isNotEmpty) {
        await _client.from('evaluation_keys').upsert({
          'evaluation_id': id,
          'scheme': scheme,
          'criteria': (criteria ?? '').trim().isEmpty ? null : criteria!.trim(),
        });
      }
      await _client.from('evaluation_classes').insert(
            classIds.map((c) => {'evaluation_id': id, 'class_id': c}).toList(),
          );
      await _client.from('evaluations').update({'status': 'published'}).eq('id', id);
      return id;
    } catch (_) {
      try {
        await _client.from('evaluations').delete().eq('id', id);
      } catch (_) {}
      if (uploaded) {
        try {
          await _client.storage.from(_papers).remove([pdfPath]);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> closeEvaluation(String id) async {
    await _client.from('evaluations').update({'status': 'closed'}).eq('id', id);
  }

  Future<List<ReviewRow>> listReview(String evaluationId) {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    return JsonCache.instance.cachedRead<List<ReviewRow>>(
      key: 'evaluation_review_${userId}_$evaluationId',
      fetch: () async => await _client.rpc(
        'list_evaluation_review',
        params: {'p_evaluation': evaluationId},
      ) as Object?,
      decode: (raw) => (raw as List)
          .map((e) => ReviewRow.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  Future<SubmissionDetail> submissionDetail(String submissionId) {
    final userId = _client.auth.currentUser?.id ?? 'anonymous';
    return JsonCache.instance.cachedRead<SubmissionDetail>(
      key: 'evaluation_submission_detail_${userId}_$submissionId',
      fetch: () async => await _client.rpc(
        'get_evaluation_submission_detail',
        params: {'p_submission': submissionId},
      ) as Object?,
      decode: (raw) => SubmissionDetail.fromMap(
        Map<String, dynamic>.from(raw as Map),
      ),
    );
  }

  Future<String> photoUrl(String path) {
    return _client.storage.from(_photos).createSignedUrl(path, 900);
  }

  Future<Map<String, dynamic>> reviewSubmission({
    required String submissionId,
    List<Map<String, dynamic>> questions = const [],
    String? comment,
    bool validate = false,
    double? manualScore,
  }) async {
    final data = await _client.rpc('review_evaluation_submission', params: {
      'p_submission': submissionId,
      'p_questions': questions,
      'p_comment': comment,
      'p_validate': validate,
      'p_manual_score': manualScore,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> validateReady(String evaluationId) async {
    final data = await _client.rpc('validate_ready_evaluation_scores', params: {'p_evaluation': evaluationId});
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> reopen(String submissionId, String reason) async {
    await _client.rpc('reopen_evaluation_score', params: {'p_submission': submissionId, 'p_reason': reason});
  }

  Future<void> retryCorrection(String submissionId) async {
    await _client.rpc('retry_evaluation_correction', params: {'p_submission': submissionId});
  }

  // -------------------------------------------------------- Administrateur --

  Future<PublicationReport> publicationReport(String periodId) async {
    final data = await _client.rpc('admin_period_publication_report', params: {'p_period': periodId});
    return PublicationReport(Map<String, dynamic>.from(data as Map));
  }

  Future<void> schedulePublication({
    required String periodId,
    required DateTime publishAt,
    required String policy,
  }) async {
    await _client.rpc('admin_schedule_period_publication', params: {
      'p_period': periodId,
      'p_publish_at': publishAt.toUtc().toIso8601String(),
      'p_policy': policy,
    });
  }

  Future<void> cancelPublication(String periodId) async {
    await _client.rpc('admin_cancel_period_publication', params: {'p_period': periodId});
  }

  Future<Map<String, dynamic>> publishNow(String periodId, {String? policy}) async {
    final data = await _client.rpc('admin_publish_period_now', params: {
      'p_period': periodId,
      'p_policy': policy,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}
