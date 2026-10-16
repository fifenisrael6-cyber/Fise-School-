import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/teacher_access_code.dart';

class TeacherAccessCodeService {
  final SupabaseClient _client;

  TeacherAccessCodeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

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
      return response == null ? null : TeacherAccessCode.fromMap(response);
    } catch (_) {
      return null;
    }
  }

  Future<TeacherAccessCode> getOrCreateAccessCode(
    String teacherId,
    String classId,
    String? suggestedCode,
  ) async {
    final existing = await getAccessCodeForClass(teacherId, classId);
    if (existing != null) return existing;
    final code = _normalizeCode(suggestedCode ?? _generateCode());
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

  /// Met à jour le code unique partagé par toutes les salles de l'enseignant.
  Future<TeacherAccessCode> updateAccessCode(
    String accessCodeId,
    String newCode,
  ) async {
    final suffix = _normalizeCode(newCode).replaceAll('-', '').toUpperCase();
    _validateCode(suffix);
    final result = await _client.rpc(
      'set_teacher_group_access_code',
      params: {'p_code': 'FISE-$suffix'},
    );
    final fullCode = (result as String).toUpperCase();
    final teacherId = _client.auth.currentUser?.id ?? '';
    final now = DateTime.now();
    return TeacherAccessCode(
      id: 'master-$teacherId',
      teacherId: teacherId,
      code: fullCode.replaceFirst(RegExp(r'^FISE-'), ''),
      classId: 'ALL',
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
  }

  Future<bool> validateAccessCode(String code, String studentClassId) async {
    try {
      final response = await _client.rpc(
        'validate_teacher_access_code',
        params: {'p_code': code.trim(), 'p_class_id': studentClassId},
      );
      return response == true || response == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Retourne et crée au besoin le code unique FISE de l'enseignant.
  /// Retourne le code FISE partagé. Les erreurs serveur remontent à l'écran
  /// enseignant au lieu d'être transformées silencieusement en liste vide.
  Future<List<TeacherAccessCode>> getTeacherAccessCodes(String teacherId) async {
    final result = await _client.rpc('get_or_create_teacher_group_access_code');
    final fullCode = (result as String).toUpperCase();
    final now = DateTime.now();
    return [
      TeacherAccessCode(
        id: 'master-$teacherId',
        teacherId: teacherId,
        code: fullCode.replaceFirst(RegExp(r'^FISE-'), ''),
        classId: 'ALL',
        createdAt: now,
        isActive: true,
      ),
    ];
  }

  Future<void> deactivateAccessCode(String accessCodeId) async {
    // Le code partagé n'est pas désactivé par l'ancienne action par-classe.
    throw UnsupportedError('The shared teacher code cannot be disabled here.');
  }

  String _generateCode() {
    final value = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return value.substring(value.length > 6 ? value.length - 6 : 0).toUpperCase();
  }

  String _normalizeCode(String value) {
    var clean = value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    clean = clean.replaceFirst(RegExp(r'^FISE-?'), '');
    return clean;
  }

  void _validateCode(String code) {
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      throw ArgumentError('Code must contain exactly six letters or digits after FISE-.');
    }
  }
}
