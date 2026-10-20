import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/teacher_access_code.dart';

class TeacherAccessCodeService {
  final SupabaseClient _client;

  TeacherAccessCodeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Récupère le code d'accès de l'enseignant pour une classe
  Future<TeacherAccessCode?> getAccessCodeForClass(
    String teacherId,
    String classId,
  ) async {
    try {
      final response = await _client
          .from('teacher_access_codes')
          .select()
          .eq('teacher_id', teacherId)
          .eq('class_id', classId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return TeacherAccessCode.fromMap(response);
    } catch (_) {
      return null;
    }
  }

  /// Crée ou récupère le code d'accès pour une classe
  Future<TeacherAccessCode> getOrCreateAccessCode(
    String teacherId,
    String classId,
    String? suggestedCode,
  ) async {
    // Always use the single canonical teacher code; never generate a per-room
    // GRP/IGPGRP code.
    final canonical = (await _client.rpc('get_or_create_teacher_group_access_code'))
        .toString()
        .trim()
        .toUpperCase();
    if (!RegExp(r'^FISE-[A-Z0-9]{6}$').hasMatch(canonical)) {
      throw StateError('The teacher FISE code is invalid.');
    }

    final row = await _client
        .from('teacher_access_codes')
        .upsert({
          'id': '${teacherId}:${classId}',
          'teacher_id': teacherId,
          'code': canonical,
          'class_id': classId,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'teacher_id,class_id')
        .select()
        .single();
    return TeacherAccessCode.fromMap(Map<String, dynamic>.from(row));
  }

  /// Updates the one canonical code, not an individual classroom code.
  Future<TeacherAccessCode> updateAccessCode(
    String accessCodeId,
    String newCode,
  ) async {
    final suffix = _cleanCode(newCode);
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(suffix)) {
      throw ArgumentError('Use exactly six letters or numbers after FISE-.');
    }
    await _client.rpc('set_teacher_fise_code', params: {'p_code': 'FISE-$suffix'});
    final response = await _client
        .from('teacher_access_codes')
        .select()
        .eq('id', accessCodeId)
        .single();
    return TeacherAccessCode.fromMap(Map<String, dynamic>.from(response));
  }

  /// Valide le code ET active immédiatement l'accès de l'élève au groupe.
  /// Le RPC serveur ajoute aussi l'élève à class_students et
  /// teacher_access_memberships, utilisés pour autoriser les évaluations.
  Future<bool> validateAccessCode(
    String code,
    String studentClassId,
  ) async {
    try {
      final suffix = _cleanCode(code);
      if (!RegExp(r'^[A-Z0-9]{6}

      return response is List && response.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Récupère tous les codes d'accès de l'enseignant
  Future<List<TeacherAccessCode>> getTeacherAccessCodes(String teacherId) async {
    try {
      // This call synchronizes all legacy per-class rows to the shared FISE code.
      await _client.rpc('get_or_create_teacher_group_access_code');
      var response = await _client
          .from('teacher_access_codes')
          .select()
          .eq('teacher_id', teacherId)
          .order('created_at', ascending: false);

      var rows = (response as List)
          .map((item) => TeacherAccessCode.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();

      if (rows.isEmpty) {
        String? classId;
        final teacherClasses = await _client
            .from('class_teachers')
            .select('class_id')
            .eq('teacher_id', teacherId)
            .eq('is_active', true)
            .limit(1);
        if (teacherClasses.isNotEmpty) {
          classId = (teacherClasses.first as Map)['class_id']?.toString();
        }
        if (classId == null) {
          final groups = await _client
              .from('message_groups')
              .select('class_id')
              .eq('owner_id', teacherId)
              .not('class_id', 'is', null)
              .limit(1);
          if (groups.isNotEmpty) {
            classId = (groups.first as Map)['class_id']?.toString();
          }
        }
        if (classId != null && classId.isNotEmpty) {
          await getOrCreateAccessCode(teacherId, classId, null);
          response = await _client
              .from('teacher_access_codes')
              .select()
              .eq('teacher_id', teacherId)
              .order('created_at', ascending: false);
          rows = (response as List)
              .map((item) => TeacherAccessCode.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }

      final seen = <String>{};
      return rows.where((item) => seen.add(item.code.toUpperCase())).toList();
    } catch (_) {
      return [];
    }
  }

  /// Désactive un code d'accès
  Future<void> deactivateAccessCode(String accessCodeId) async {
    await _client
        .from('teacher_access_codes')
        .update({'is_active': false})
        .eq('id', accessCodeId);
  }

  String _cleanCode(String value) => value.trim().toUpperCase().replaceFirst(RegExp(r'^FISE-?'), '');

}
).hasMatch(suffix)) return false;
      final canonicalCode = 'FISE-$suffix';

      final response = await _client.rpc(
        'join_teacher_access_code_for_class',
        params: {
          'p_code': canonicalCode,
          'p_expected_class_id': studentClassId,
        },
      );

      return response is List && response.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Récupère tous les codes d'accès de l'enseignant
  Future<List<TeacherAccessCode>> getTeacherAccessCodes(String teacherId) async {
    try {
      final response = await _client
          .from('teacher_access_codes')
          .select()
          .eq('teacher_id', teacherId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((item) => TeacherAccessCode.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Désactive un code d'accès
  Future<void> deactivateAccessCode(String accessCodeId) async {
    await _client
        .from('teacher_access_codes')
        .update({'is_active': false})
        .eq('id', accessCodeId);
  }

  String _cleanCode(String value) => value.trim().toUpperCase().replaceFirst(RegExp(r'^FISE-?'), '');

}
