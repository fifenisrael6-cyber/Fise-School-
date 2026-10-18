import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../offline/course_offline_service.dart';
import '../offline/offline_repository.dart';
import 'profile_service.dart';

class StudentClassChangeService {
  StudentClassChangeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final ProfileService _profiles = ProfileService();

  /// Toutes les salles compatibles (recommandées en premier). Si la nouvelle
  /// fonction n'est pas encore déployée, on retombe sur le niveau suivant.
  Future<List<Map<String, dynamic>>> listNextClasses() async {
    try {
      final response = await _client.rpc('list_student_available_classes');
      return List<Map<String, dynamic>>.from(
        (response as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      final response = await _client.rpc('list_student_next_classes');
      return List<Map<String, dynamic>>.from(
        (response as List).map((e) => <String, dynamic>{
              ...Map<String, dynamic>.from(e as Map),
              'relation': 'next',
              'recommended': true,
            }),
      );
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
