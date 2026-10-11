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
          .eq('is_active', true)
          .maybeSingle();
      return response == null ? null : TeacherAccessCode.fromMap(response);
    } catch (_) {
      return null;
    }
  }

  /// Saves the code chosen manually by the teacher and synchronizes payment.
  Future<String> setMySharedCode(String code) async {
    final clean = _normalizeCode(code);
    _validateCode(clean);
    try {
      final result = await _client.rpc(
        'set_teacher_shared_code',
        params: {'p_code': clean},
      );
      if (result == null || result.toString().trim().isEmpty) {
        throw StateError('Impossible d’enregistrer ce code.');
      }
      return result.toString();
    } on PostgrestException catch (error) {
      throw StateError(_friendlyTeacherError(error.message));
    }
  }

  /// Legacy compatibility: no code is generated automatically anymore.
  Future<TeacherAccessCode> getOrCreateAccessCode(
    String teacherId,
    String classId,
    String? suggestedCode,
  ) async {
    final existing = await getAccessCodeForClass(teacherId, classId);
    if (existing != null && (suggestedCode == null || suggestedCode.trim().isEmpty)) {
      return existing;
    }
    if (suggestedCode == null || suggestedCode.trim().isEmpty) {
      throw StateError('Choisis toi-même ton code unique avant de continuer.');
    }
    await setMySharedCode(suggestedCode);
    final updated = await getAccessCodeForClass(teacherId, classId);
    if (updated == null) {
      throw StateError('Le code a été enregistré, mais la salle doit être vérifiée.');
    }
    return updated;
  }

  /// Older screens may call this method; the canonical shared-code RPC is used.
  Future<TeacherAccessCode> updateAccessCode(
    String accessCodeId,
    String newCode,
  ) async {
    await setMySharedCode(newCode);
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Session expirée.');
    final rows = await _client
        .from('teacher_access_codes')
        .select()
        .eq('teacher_id', user.id)
        .eq('is_active', true)
        .order('created_at')
        .limit(1);
    if (rows.isEmpty) throw StateError('Code introuvable après enregistrement.');
    return TeacherAccessCode.fromMap(rows.first);
  }

  Future<void> joinAccessCode(String code) async {
    try {
      final response = await _client.rpc(
        'join_teacher_access_code',
        params: {'p_code': code.trim()},
      );
      if (response is List && response.isNotEmpty) return;
      if (response is Map && response['teacher_id'] != null) return;
      throw StateError('Ce code est invalide ou n’est plus actif.');
    } on PostgrestException catch (error) {
      throw StateError(_friendlyStudentError(error.message));
    }
  }

  Future<bool> validateAccessCode(String code, String studentClassId) async {
    try {
      final response = await _client.rpc(
        'validate_teacher_access_code',
        params: {
          'p_code': code.trim(),
          'p_class_id': studentClassId,
        },
      );
      return response == true || response == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<List<TeacherAccessCode>> getTeacherAccessCodes(String teacherId) async {
    final response = await _client
        .from('teacher_access_codes')
        .select()
        .eq('teacher_id', teacherId)
        .eq('is_active', true)
        .order('created_at', ascending: true);
    return (response as List)
        .map((item) => TeacherAccessCode.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> deactivateAccessCode(String accessCodeId) async {
    await _client
        .from('teacher_access_codes')
        .update({'is_active': false})
        .eq('id', accessCodeId);
  }

  String _normalizeCode(String value) {
    var clean = value.trim().toUpperCase();
    if (clean.startsWith('FISE-')) clean = clean.substring(5);
    else if (clean.startsWith('FISE')) clean = clean.substring(4);
    return clean.trim();
  }

  void _validateCode(String code) {
    if (code.length < 3 || code.length > 40 ||
        !RegExp(r'^[A-Z0-9_-]+$').hasMatch(code)) {
      throw ArgumentError('Le code doit contenir de 3 à 40 lettres, chiffres, tirets ou tirets bas.');
    }
  }

  String _friendlyTeacherError(String message) {
    final value = message.toLowerCase();
    if (value.contains('already used') || value.contains('unique')) {
      return 'Ce code est déjà utilisé. Choisis un autre code.';
    }
    if (value.contains('no classroom') || value.contains('classroom')) {
      return 'Aucune salle n’est associée à ton compte enseignant. Contacte l’administration.';
    }
    if (value.contains('only teachers')) return 'Seul un compte enseignant peut créer ce code.';
    if (value.contains('authentication')) return 'Ta session a expiré. Reconnecte-toi.';
    return 'Impossible d’enregistrer le code. Vérifie les informations et réessaie.';
  }

  String _friendlyStudentError(String message) {
    final value = message.toLowerCase();
    if (value.contains('invalid') || value.contains('inactive')) {
      return 'Ce code est invalide ou n’est plus actif.';
    }
    if (value.contains('already assigned') || value.contains('another classroom')) {
      return 'Ton compte est déjà rattaché à une autre salle. Contacte ton établissement.';
    }
    if (value.contains('classroom') && value.contains('unavailable')) {
      return 'La salle associée à ce code n’est plus disponible.';
    }
    if (value.contains('only students')) return 'Seul un compte élève peut utiliser ce code.';
    if (value.contains('authentication')) return 'Ta session a expiré. Reconnecte-toi.';
    return 'Impossible de valider ce code. Vérifie ta connexion ou contacte ton enseignant.';
  }
}
