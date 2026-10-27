import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../offline/course_offline_service.dart';
import '../offline/json_cache.dart';
import '../offline/offline_repository.dart';
import 'profile_service.dart';

class StudentClassChangeService {
  StudentClassChangeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ProfileService _profiles = ProfileService();

  /// Toutes les salles compatibles (recommandées en premier).
  /// Le cache est propre à chaque compte et permet d'ouvrir l'écran sans attendre
  /// le réseau après une première consultation.
  Future<List<Map<String, dynamic>>> listNextClasses() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('No active user session.');
    }

    return JsonCache.instance.cachedRead<List<Map<String, dynamic>>>(
      key: 'student_available_classes_$userId',
      fetch: _fetchAvailableClasses,
      decode: (raw) => List<Map<String, dynamic>>.from(
        (raw as List).map((row) => Map<String, dynamic>.from(row as Map)),
      ),
    );
  }

  Future<Object?> _fetchAvailableClasses() async {
    try {
      return await _client.rpc('list_student_available_classes') as Object?;
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      final response = await _client.rpc('list_student_next_classes');
      return (response as List).map((row) => <String, dynamic>{
        ...Map<String, dynamic>.from(row as Map),
        'relation': 'next',
        'recommended': true,
      }).toList(growable: false);
    }
  }

  Future<UserProfile> changeClass(String destinationClassId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('No active user session.');
    }

    await _client.rpc(
      'change_student_class',
      params: {'target_class_id': destinationClassId},
    );
    await JsonCache.instance.remove('student_available_classes_${user.id}');

    // Remove old-class downloads and cached lesson state only after the server
    // commits the new membership. Historical grades, payments and messages stay.
    try {
      await CourseOfflineService().deleteUserFiles(user.id);
    } catch (_) {}
    try {
      final offline = OfflineRepository();
      await offline.clearCourses();
      await offline.clearLessons();
      await offline.clearProgress();
    } catch (_) {}

    final updated = await _profiles.getCurrentProfile();
    if (updated == null || updated.id != user.id) {
      throw const AuthException(
        'Class changed, but the updated profile could not be reloaded.',
      );
    }
    return updated;
  }
}
