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
    var existing = await getAccessCodeForClass(teacherId, classId);

    if (existing != null) {
      return existing;
    }

    // Le code doit être choisi explicitement par l'enseignant.
    if (suggestedCode == null || suggestedCode.trim().isEmpty) {
      throw ArgumentError('Choisissez votre code après le préfixe FISE-.');
    }
    final code = _normalizeCode(suggestedCode);

    if (code.isEmpty) {
      throw ArgumentError('La suite du code ne peut pas être vide.');
    }

    // Valider le format
    _validateCode(code);

    final now = DateTime.now();
    final newCode = TeacherAccessCode(
      id: '${teacherId}_${classId}_${now.millisecondsSinceEpoch}',
      teacherId: teacherId,
      code: code,
      classId: classId,
      createdAt: now,
      isActive: true,
    );

    await _client.from('teacher_access_codes').insert(newCode.toMap());

    return newCode;
  }

  /// Met à jour le code d'accès
  Future<TeacherAccessCode> updateAccessCode(
    String accessCodeId,
    String newCode,
  ) async {
    final cleanCode = _normalizeCode(newCode);
    _validateCode(cleanCode);

    final response = await _client
        .from('teacher_access_codes')
        .update({
          'code': cleanCode,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', accessCodeId)
        .select()
        .single();

    return TeacherAccessCode.fromMap(response);
  }

  /// Vérifie le code sans modifier l'inscription de l'élève.
  Future<bool> validateAccessCode(
    String code,
    String studentClassId,
  ) async {
    try {
      final response = await _client.rpc(
        'validate_teacher_access_code',
        params: {
          'p_code': _normalizeCode(code),
          'p_class_id': studentClassId,
        },
      );
      return response == true || response == 'true';
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

  String _normalizeCode(String value) {
    var clean = value.trim().toUpperCase();
    if (clean.startsWith('FISE-')) {
      clean = clean.substring(5);
    }
    return clean;
  }

  /// Valide uniquement la suite saisie après le préfixe fixe FISE-.
  void _validateCode(String code) {
    final cleanCode = _normalizeCode(code);
    if (cleanCode.length < 3) {
      throw ArgumentError('La suite du code doit contenir au moins 3 caractères.');
    }
    if (cleanCode.contains(RegExp(r'\s'))) {
      throw ArgumentError('Le code ne doit contenir aucun espace.');
    }
    if (!RegExp(r'^[A-Z0-9-]+$').hasMatch(cleanCode)) {
      throw ArgumentError('Utilisez uniquement des lettres, des chiffres et des tirets.');
    }
  }
}
