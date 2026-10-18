import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/timetable_entry.dart';

class TimetableService {
  TimetableService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<TimetableEntry>> listForStudent(String studentId) async {
    final memberships = await _client
        .from('class_students')
        .select('class_id')
        .eq('student_id', studentId)
        .eq('is_active', true);
    final classIds = memberships.map((r) => r['class_id']?.toString()).whereType<String>().toList();
    if (classIds.isNotEmpty) {
      // Élève affecté à une salle : seul l'emploi du temps de la salle fait foi.
      final rows = await _client
          .from('class_timetable_entries')
          .select()
          .inFilter('class_id', classIds)
          .eq('is_active', true)
          .order('day_of_week')
          .order('start_time');
      return rows.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
    }
    // Ancien emploi du temps individuel : uniquement pour un élève sans salle.
    final legacy = await _client
        .from('student_timetable_entries')
        .select('id, day_of_week, start_time, end_time, subject, teacher_name, room, notes')
        .eq('student_id', studentId)
        .order('day_of_week')
        .order('start_time');
    return legacy.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  /// Emploi du temps de la salle de l'élève (lecture seule). Vide si l'élève n'a pas de salle.
  Future<List<TimetableEntry>> listClassTimetableForStudent(String studentId) async {
    final memberships = await _client
        .from('class_students')
        .select('class_id')
        .eq('student_id', studentId)
        .eq('is_active', true);
    final classIds = memberships.map((r) => r['class_id']?.toString()).whereType<String>().toList();
    if (classIds.isEmpty) {
      return const [];
    }
    final rows = await _client
        .from('class_timetable_entries')
        .select()
        .inFilter('class_id', classIds)
        .eq('is_active', true)
        .order('day_of_week')
        .order('start_time');
    return rows.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  /// Emploi du temps que l'élève construit lui-même.
  Future<List<TimetableEntry>> listPersonal(String studentId) async {
    final rows = await _client
        .from('student_timetable_entries')
        .select('id, subject_id, day_of_week, start_time, end_time, subject, subject_en, teacher_name, room, notes')
        .eq('student_id', studentId)
        .order('day_of_week')
        .order('start_time');
    return rows.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  Future<void> savePersonal({
    String? id,
    required String studentId,
    String? subjectId,
    required String subjectFr,
    String? subjectEn,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    String? room,
    String? notes,
  }) async {
    final values = <String, dynamic>{
      'student_id': studentId,
      'subject_id': subjectId,
      'subject': subjectFr.trim(),
      'subject_en': (subjectEn == null || subjectEn.trim().isEmpty) ? null : subjectEn.trim(),
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'room': (room == null || room.trim().isEmpty) ? null : room.trim(),
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
    };
    if (id == null) {
      await _client.from('student_timetable_entries').insert(values);
    } else {
      values['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _client.from('student_timetable_entries').update(values).eq('id', id).eq('student_id', studentId);
    }
  }

  Future<void> deletePersonal(String id, String studentId) async {
    await _client.from('student_timetable_entries').delete().eq('id', id).eq('student_id', studentId);
  }

  /// Copie les créneaux de la salle dans le planning personnel (sans doublons).
  Future<int> importClassTimetable(String studentId) async {
    final classEntries = await listClassTimetableForStudent(studentId);
    final existing = await listPersonal(studentId);
    final keys = {for (final e in existing) '${e.dayOfWeek}|${e.startTime}|${e.subject}'};
    var added = 0;
    for (final entry in classEntries) {
      if (keys.contains('${entry.dayOfWeek}|${entry.startTime}|${entry.subject}')) {
        continue;
      }
      await savePersonal(
        studentId: studentId,
        subjectId: entry.subjectId,
        subjectFr: entry.subject,
        subjectEn: entry.subjectEn,
        dayOfWeek: entry.dayOfWeek,
        startTime: entry.startTime,
        endTime: entry.endTime,
        room: entry.room,
        notes: entry.notes,
      );
      added++;
    }
    return added;
  }

  Future<List<TimetableEntry>> listForTeacher(String teacherId) async {
    final rows = await _client
        .from('class_timetable_entries')
        .select()
        .eq('teacher_id', teacherId)
        .eq('is_active', true)
        .order('day_of_week')
        .order('start_time');
    return rows.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  Future<List<TimetableEntry>> listForClass(String classId) async {
    final rows = await _client
        .from('class_timetable_entries')
        .select()
        .eq('class_id', classId)
        .eq('is_active', true)
        .order('day_of_week')
        .order('start_time');
    return rows.map((r) => TimetableEntry.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  Future<void> create({
    required String classId,
    String? subjectId,
    required String subjectFr,
    required String subjectEn,
    String? teacherId,
    String? teacherName,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    String? room,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Session utilisateur absente.');
    }
    await _client.from('class_timetable_entries').insert({
      'class_id': classId,
      'subject_id': subjectId,
      'subject_fr': subjectFr.trim(),
      'subject_en': subjectEn.trim(),
      'teacher_id': teacherId,
      'teacher_name': teacherName?.trim(),
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'room': room?.trim(),
      'notes': notes?.trim(),
      'created_by': user.id,
    });
  }

  Future<void> delete(String id) async {
    await _client.from('class_timetable_entries').delete().eq('id', id);
  }
}
