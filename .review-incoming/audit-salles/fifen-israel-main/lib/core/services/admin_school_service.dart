import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/school_class.dart';
import '../../models/exam_catalog.dart';
import '../../models/user_profile.dart';

class AdminSchoolService {
  final SupabaseClient _client;

  AdminSchoolService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<Map<String, int>> loadStats() async {
    final students = await _client
        .from('profiles')
        .select('id')
        .eq('role', 'student');

    final teachers = await _client
        .from('profiles')
        .select('id')
        .eq('role', 'teacher');

    final classes = await _client
        .from('school_classes')
        .select('id')
        .eq('is_active', true);

    final promotions = await _client
        .from('student_promotions')
        .select('id')
        .eq('status', 'pending');

    final years = await _client
        .from('academic_years')
        .select('id')
        .eq('is_current', true);

    return {
      'students': students.length,
      'teachers': teachers.length,
      'classes': classes.length,
      'pendingPromotions': promotions.length,
      'activeYears': years.length,
    };
  }

  Future<List<AcademicYear>> listAcademicYears() async {
    final rows = await _client
        .from('academic_years')
        .select()
        .order('start_date');

    return rows
        .map((row) => AcademicYear.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<AcademicYear> createAcademicYear({
    required String label,
    DateTime? startDate,
    DateTime? endDate,
    bool isCurrent = false,
  }) async {
    if (isCurrent) {
      await _client
          .from('academic_years')
          .update({'is_current': false})
          .eq('is_current', true);
    }

    final row = await _client
        .from('academic_years')
        .insert({
          'label': label,
          'start_date': startDate?.toIso8601String().substring(0, 10),
          'end_date': endDate?.toIso8601String().substring(0, 10),
          'is_current': isCurrent,
        })
        .select()
        .single();

    return AcademicYear.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> setCurrentAcademicYear(String id) async {
    await _client
        .from('academic_years')
        .update({'is_current': false})
        .eq('is_current', true);

    await _client
        .from('academic_years')
        .update({'is_current': true})
        .eq('id', id);
  }

  Future<void> updateAcademicYear(
    String id, {
    required String label,
    required bool isCurrent,
  }) async {
    if (isCurrent) {
      await _client
          .from('academic_years')
          .update({'is_current': false})
          .eq('is_current', true);
    }

    await _client
        .from('academic_years')
        .update({'label': label, 'is_current': isCurrent})
        .eq('id', id);
  }

  Future<List<SchoolClass>> listClasses({String? academicYearId}) async {
    var query = _client.from('school_classes').select();

    if (academicYearId != null) {
      query = query.eq('academic_year_id', academicYearId);
    }

    final rows = await query.order('display_name');

    return rows
        .map((row) => SchoolClass.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<SchoolClass> createClass({
    required String name,
    required String displayName,
    required ExamSubsystem subsystem,
    required ExamSector sector,
    required String academicYearId,
    String? examLevelId,
    String? seriesId,
    String? specialtyId,
  }) async {
    final row = await _client
        .from('school_classes')
        .insert({
          'name': name,
          'display_name': displayName,
          'subsystem': subsystem.name,
          'sector': sector.name,
          'academic_year_id': academicYearId,
          'exam_level_id': examLevelId,
          'series_id': seriesId,
          'specialty_id': specialtyId,
        })
        .select()
        .single();

    return SchoolClass.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> setClassActive(String id, bool active) async {
    await _client
        .from('school_classes')
        .update({'is_active': active})
        .eq('id', id);
  }

  Future<List<UserProfile>> listPeople({
    required String role,
    String query = '',
  }) async {
    var request = _client.from('profiles').select().eq('role', role);

    if (query.trim().isNotEmpty) {
      final value = query.trim();

      request = request.or(
        'first_name.ilike.%$value%,'
        'last_name.ilike.%$value%,'
        'email.ilike.%$value%',
      );
    }

    final rows = await request.order('last_name');

    return rows
        .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SchoolClass>> classesForStudent(String studentId) async {
    final rows = await _client
        .from('class_students')
        .select('school_classes!inner(*)')
        .eq('student_id', studentId)
        .order('joined_at', ascending: false);

    return rows
        .map(
          (row) => SchoolClass.fromMap(
            Map<String, dynamic>.from(row['school_classes'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<SchoolClass>> classesForTeacher(String teacherId) async {
    final rows = await _client
        .from('class_teachers')
        .select('school_classes!inner(*)')
        .eq('teacher_id', teacherId)
        .order('assigned_at', ascending: false);

    return rows
        .map(
          (row) => SchoolClass.fromMap(
            Map<String, dynamic>.from(row['school_classes'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> assignStudent(String studentId, String classId) async {
    await _client.from('class_students').insert({
      'student_id': studentId,
      'class_id': classId,
    });
  }

  Future<void> assignTeacher(String teacherId, String classId) async {
    await _client.from('class_teachers').insert({
      'teacher_id': teacherId,
      'class_id': classId,
    });
  }

  Future<void> deactivateStudentMembership(
    String studentId,
    String classId,
  ) async {
    await _client
        .from('class_students')
        .update({'is_active': false})
        .eq('student_id', studentId)
        .eq('class_id', classId)
        .eq('is_active', true);
  }

  Future<void> deactivateTeacherAssignment(
    String teacherId,
    String classId,
  ) async {
    await _client
        .from('class_teachers')
        .update({'is_active': false})
        .eq('teacher_id', teacherId)
        .eq('class_id', classId)
        .eq('is_active', true);
  }
}
