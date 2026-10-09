import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/grades.dart';

class GradeService {
  GradeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<GradePeriod>> listPeriods({bool onlyPublished = false}) async {
    var query = _client.from('grade_periods').select();
    if (onlyPublished) {
      query = query.eq('is_published', true);
    }
    final rows = await query.order('position');
    return rows
        .map((r) => GradePeriod.fromMap(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  Future<List<GradeClassOption>> listTeacherClasses(String teacherId) async {
    final assignments = await _client
        .from('class_teachers')
        .select('class_id')
        .eq('teacher_id', teacherId)
        .eq('is_active', true);
    final classIds = assignments
        .map((row) => row['class_id'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (classIds.isEmpty) return const <GradeClassOption>[];

    final rows = await _client
        .from('school_classes')
        .select('id, name, display_name')
        .inFilter('id', classIds)
        .order('display_name');
    return rows
        .map((row) => GradeClassOption.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<GradeClassOption>> listAllClasses() async {
    final rows = await _client
        .from('school_classes')
        .select('id, name, display_name')
        .order('display_name');
    return rows
        .map((r) => GradeClassOption.fromMap(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  Future<List<GradeSubject>> listClassSubjects(String classId) async {
    final rows = await _client
        .from('class_subjects')
        .select('id, subject_id, coefficient, subjects(id, name_fr, name_en)')
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('position');
    return rows
        .map((r) => GradeSubject.fromMap(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  Future<List<RosterStudent>> roster(String classId) async {
    final rows = await _client.rpc('list_grade_roster', params: {'p_class_id': classId});
    return (rows as List)
        .map((r) => RosterStudent.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  Future<Map<String, StoredGrade>> listGrades({
    required String classId,
    required String subjectId,
    required String periodId,
  }) async {
    final rows = await _client
        .from('grades')
        .select('student_id, score, comment')
        .eq('class_id', classId)
        .eq('subject_id', subjectId)
        .eq('period_id', periodId);
    return {
      for (final r in rows)
        r['student_id'].toString(): StoredGrade(
          score: (r['score'] as num).toDouble(),
          comment: r['comment']?.toString(),
        ),
    };
  }

  Future<void> saveGrades({
    required String classId,
    required String subjectId,
    required String periodId,
    required Map<String, double> scores,
    Map<String, String> comments = const {},
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Session utilisateur absente.');
    }
    if (scores.isEmpty) {
      return;
    }
    final rows = scores.entries.map((e) {
      final c = comments[e.key]?.trim();
      return {
        'class_id': classId,
        'subject_id': subjectId,
        'period_id': periodId,
        'student_id': e.key,
        'score': e.value,
        'max_score': 20,
        'comment': (c == null || c.isEmpty) ? null : c,
        'entered_by': user.id,
      };
    }).toList();
    await _client
        .from('grades')
        .upsert(rows, onConflict: 'student_id,subject_id,period_id');
  }

  Future<Bulletin> bulletin(String studentId, String periodId) async {
    final res = await _client.rpc(
      'get_student_bulletin',
      params: {'p_student_id': studentId, 'p_period_id': periodId},
    );
    return Bulletin.fromMap(Map<String, dynamic>.from(res as Map));
  }

  Future<void> createPeriod(String label, int position) async {
    final clean = label.trim();
    await _client.from('grade_periods').insert({
      'label_fr': clean,
      'label_en': clean,
      'position': position,
    });
  }

  Future<void> setPeriodPublished(String id, bool published) async {
    await _client
        .from('grade_periods')
        .update({'is_published': published})
        .eq('id', id);
  }

  Future<void> updateCoefficient(String classSubjectId, double coefficient) async {
    await _client
        .from('class_subjects')
        .update({'coefficient': coefficient})
        .eq('id', classSubjectId);
  }
}
