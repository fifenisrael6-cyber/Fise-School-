import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolClassService {
  final SupabaseClient _client;

  SchoolClassService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listAcademicYears() async {
    final response = await _client
        .from('academic_years')
        .select()
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listClasses({
    String? academicYearId,
    bool activeOnly = false,
  }) async {
    dynamic query = _client.from('school_classes').select();

    if (academicYearId != null && academicYearId.trim().isNotEmpty) {
      query = query.eq('academic_year_id', academicYearId);
    }

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    final response = await query.order('display_name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> getClass(String classId) async {
    final response = await _client
        .from('school_classes')
        .select()
        .eq('id', classId)
        .single();

    return Map<String, dynamic>.from(response);
  }

  Future<void> createAcademicYear({
    required String label,
    DateTime? startDate,
    DateTime? endDate,
    bool isCurrent = false,
  }) async {
    final cleanedLabel = label.trim();

    if (cleanedLabel.isEmpty) {
      throw ArgumentError('Le nom de l’année scolaire est obligatoire.');
    }

    if (startDate != null && endDate != null && !endDate.isAfter(startDate)) {
      throw ArgumentError(
        'La date de fin doit être postérieure à la date de début.',
      );
    }

    if (isCurrent) {
      await _client
          .from('academic_years')
          .update({'is_current': false})
          .eq('is_current', true);
    }

    await _client.from('academic_years').insert({
      'label': cleanedLabel,
      'start_date': _dateOnly(startDate),
      'end_date': _dateOnly(endDate),
      'is_current': isCurrent,
    });
  }

  Future<void> setAcademicYearCurrent(
    String academicYearId,
    bool isCurrent,
  ) async {
    if (isCurrent) {
      await _client
          .from('academic_years')
          .update({'is_current': false})
          .eq('is_current', true);
    }

    await _client
        .from('academic_years')
        .update({'is_current': isCurrent})
        .eq('id', academicYearId);
  }

  Future<void> updateAcademicYear({
    required String academicYearId,
    required String label,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final cleanedLabel = label.trim();

    if (cleanedLabel.isEmpty) {
      throw ArgumentError('Le nom de l’année scolaire est obligatoire.');
    }

    if (startDate != null && endDate != null && !endDate.isAfter(startDate)) {
      throw ArgumentError(
        'La date de fin doit être postérieure à la date de début.',
      );
    }

    await _client
        .from('academic_years')
        .update({
          'label': cleanedLabel,
          'start_date': _dateOnly(startDate),
          'end_date': _dateOnly(endDate),
        })
        .eq('id', academicYearId);
  }

  Future<void> createClass({
    required String name,
    required String displayName,
    required String subsystem,
    required String sector,
    required String academicYearId,
    String? examLevelId,
    String? seriesId,
    String? specialtyId,
    bool isActive = true,
  }) async {
    final cleanedName = name.trim();
    final cleanedDisplayName = displayName.trim();
    final cleanedAcademicYearId = academicYearId.trim();

    if (cleanedName.isEmpty) {
      throw ArgumentError('Le nom interne de la classe est obligatoire.');
    }

    if (cleanedDisplayName.isEmpty) {
      throw ArgumentError('Le nom affiché de la classe est obligatoire.');
    }

    if (cleanedAcademicYearId.isEmpty) {
      throw ArgumentError('L’année scolaire est obligatoire.');
    }

    if (!_isValidSubsystem(subsystem)) {
      throw ArgumentError('Sous-système scolaire invalide.');
    }

    if (!_isValidSector(sector)) {
      throw ArgumentError('Secteur scolaire invalide.');
    }

    await _client.from('school_classes').insert({
      'name': cleanedName,
      'display_name': cleanedDisplayName,
      'subsystem': subsystem,
      'sector': sector,
      'academic_year_id': cleanedAcademicYearId,
      'exam_level_id': _nullable(examLevelId),
      'series_id': _nullable(seriesId),
      'specialty_id': _nullable(specialtyId),
      'is_active': isActive,
    });
  }

  Future<void> updateClass({
    required String classId,
    required String name,
    required String displayName,
    required String subsystem,
    required String sector,
    String? examLevelId,
    String? seriesId,
    String? specialtyId,
  }) async {
    final cleanedName = name.trim();
    final cleanedDisplayName = displayName.trim();

    if (cleanedName.isEmpty) {
      throw ArgumentError('Le nom interne de la classe est obligatoire.');
    }

    if (cleanedDisplayName.isEmpty) {
      throw ArgumentError('Le nom affiché de la classe est obligatoire.');
    }

    if (!_isValidSubsystem(subsystem)) {
      throw ArgumentError('Sous-système scolaire invalide.');
    }

    if (!_isValidSector(sector)) {
      throw ArgumentError('Secteur scolaire invalide.');
    }

    await _client
        .from('school_classes')
        .update({
          'name': cleanedName,
          'display_name': cleanedDisplayName,
          'subsystem': subsystem,
          'sector': sector,
          'exam_level_id': _nullable(examLevelId),
          'series_id': _nullable(seriesId),
          'specialty_id': _nullable(specialtyId),
        })
        .eq('id', classId);
  }

  Future<void> setClassActive(String classId, bool active) async {
    await _client
        .from('school_classes')
        .update({'is_active': active})
        .eq('id', classId);
  }

  Future<List<Map<String, dynamic>>> listStudents() async {
    final response = await _client
        .from('profiles')
        .select(
          'id, first_name, last_name, email, '
          'preferred_language, subsystem, sector, '
          'exam_level_id, exam_id, series_id, specialty_id, class_name',
        )
        .eq('role', 'student')
        .order('last_name', ascending: true)
        .order('first_name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listTeachers() async {
    final response = await _client
        .from('profiles')
        .select(
          'id, first_name, last_name, email, '
          'preferred_language, subsystem, sector, '
          'exam_level_id, exam_id, series_id, specialty_id',
        )
        .eq('role', 'teacher')
        .order('last_name', ascending: true)
        .order('first_name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listClassStudents(String classId) async {
    final response = await _client
        .from('class_students')
        .select(
          'id, class_id, student_id, joined_at, is_active, '
          'profiles!class_students_student_id_fkey('
          'id, first_name, last_name, email, '
          'preferred_language, subsystem, sector, '
          'exam_level_id, exam_id, series_id, specialty_id, class_name'
          ')',
        )
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('joined_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listClassSubjects(String classId) async {
    final response = await _client
        .from('class_subjects')
        .select('id, class_id, subject_id, is_compulsory, option_group, position, is_active, subjects(*)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('position')
        .order('subject_id');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAvailableSubjectsForClass({
    required String classId,
    required String subsystem,
    required String sector,
  }) async {
    final assigned = await _client
        .from('class_subjects')
        .select('subject_id')
        .eq('class_id', classId);
    final assignedIds = assigned
        .map((row) => row['subject_id']?.toString())
        .whereType<String>()
        .toSet();

    final response = await _client
        .from('subjects')
        .select('id, name_fr, name_en, code, subsystem, sector, description_fr, description_en, is_active')
        .eq('subsystem', subsystem)
        .eq('sector', sector)
        .eq('is_active', true)
        .order('name_fr');

    return response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .where((row) => !assignedIds.contains(row['id']?.toString()))
        .toList(growable: false);
  }

  Future<void> assignSubjectToClass({
    required String classId,
    required String subjectId,
    required int position,
  }) async {
    await _client.from('class_subjects').upsert({
      'class_id': classId,
      'subject_id': subjectId,
      'is_compulsory': true,
      'position': position,
      'is_active': true,
    }, onConflict: 'class_id,subject_id');
  }

  Future<void> removeSubjectFromClass(String classSubjectId) async {
    await _client
        .from('class_subjects')
        .update({'is_active': false})
        .eq('id', classSubjectId);
  }

  Future<List<Map<String, dynamic>>> listClassTeachers(String classId) async {
    final response = await _client
        .from('class_teachers')
        .select(
          'id, class_id, teacher_id, assigned_at, is_active, '
          'profiles!class_teachers_teacher_id_fkey('
          'id, first_name, last_name, email, '
          'preferred_language, subsystem, sector, '
          'exam_level_id, exam_id, series_id, specialty_id'
          ')',
        )
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('assigned_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> assignStudent({
    required String classId,
    required String studentId,
  }) async {
    final existingResponse = await _client
        .from('class_students')
        .select('id, is_active')
        .eq('class_id', classId)
        .eq('student_id', studentId)
        .limit(1);

    final existingRows = List<Map<String, dynamic>>.from(existingResponse);

    if (existingRows.isNotEmpty) {
      final existingId = existingRows.first['id'] as String;

      final isActive = existingRows.first['is_active'] as bool? ?? false;

      if (isActive) {
        return;
      }

      await _client
          .from('class_students')
          .update({
            'is_active': true,
            'joined_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existingId);

      return;
    }

    await _client.from('class_students').insert({
      'class_id': classId,
      'student_id': studentId,
      'is_active': true,
    });
  }

  Future<void> removeStudent({
    required String classId,
    required String studentId,
  }) async {
    await _client
        .from('class_students')
        .update({'is_active': false})
        .eq('class_id', classId)
        .eq('student_id', studentId)
        .eq('is_active', true);
  }

  Future<void> assignTeacher({
    required String classId,
    required String teacherId,
  }) async {
    final existingResponse = await _client
        .from('class_teachers')
        .select('id, is_active')
        .eq('class_id', classId)
        .eq('teacher_id', teacherId)
        .limit(1);

    final existingRows = List<Map<String, dynamic>>.from(existingResponse);

    if (existingRows.isNotEmpty) {
      final existingId = existingRows.first['id'] as String;

      final isActive = existingRows.first['is_active'] as bool? ?? false;

      if (isActive) {
        return;
      }

      await _client
          .from('class_teachers')
          .update({
            'is_active': true,
            'assigned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existingId);

      return;
    }

    await _client.from('class_teachers').insert({
      'class_id': classId,
      'teacher_id': teacherId,
      'is_active': true,
    });
  }

  Future<void> removeTeacher({
    required String classId,
    required String teacherId,
  }) async {
    await _client
        .from('class_teachers')
        .update({'is_active': false})
        .eq('class_id', classId)
        .eq('teacher_id', teacherId)
        .eq('is_active', true);
  }

  Future<void> removeStudentMembershipById(String membershipId) async {
    await _client
        .from('class_students')
        .update({'is_active': false})
        .eq('id', membershipId);
  }

  Future<void> removeTeacherAssignmentById(String assignmentId) async {
    await _client
        .from('class_teachers')
        .update({'is_active': false})
        .eq('id', assignmentId);
  }

  Future<List<Map<String, dynamic>>> listClassesForStudent(
    String studentId,
  ) async {
    final response = await _client
        .from('class_students')
        .select('school_classes(*)')
        .eq('student_id', studentId)
        .eq('is_active', true);

    return response
        .map<Map<String, dynamic>>(
          (row) => Map<String, dynamic>.from(row['school_classes'] as Map),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listClassesForTeacher(
    String teacherId,
  ) async {
    final response = await _client
        .from('class_teachers')
        .select('school_classes(*)')
        .eq('teacher_id', teacherId)
        .eq('is_active', true);

    return response
        .map<Map<String, dynamic>>(
          (row) => Map<String, dynamic>.from(row['school_classes'] as Map),
        )
        .toList(growable: false);
  }

  String? _dateOnly(DateTime? date) {
    if (date == null) {
      return null;
    }

    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  bool _isValidSubsystem(String value) {
    return value == 'francophone' || value == 'anglophone';
  }

  bool _isValidSector(String value) {
    return value == 'general' || value == 'technical';
  }
}
