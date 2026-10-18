class TimetableEntry {
  final String id;
  final String? classId;
  final String? subjectId;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String subject;
  final String? subjectEn;
  final String? teacherId;
  final String? teacherName;
  final String? room;
  final String? notes;

  const TimetableEntry({
    required this.id,
    this.classId,
    this.subjectId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.subjectEn,
    this.teacherId,
    this.teacherName,
    this.room,
    this.notes,
  });

  factory TimetableEntry.fromMap(Map<String, dynamic> map) {
    String time(Object? value) {
      final raw = value?.toString() ?? '';
      return raw.length >= 5 ? raw.substring(0, 5) : raw;
    }
    return TimetableEntry(
      id: map['id'] as String,
      classId: map['class_id'] as String?,
      subjectId: map['subject_id'] as String?,
      dayOfWeek: (map['day_of_week'] as num).toInt(),
      startTime: time(map['start_time']),
      endTime: time(map['end_time']),
      subject: (map['subject_fr'] ?? map['subject'] ?? '') as String,
      subjectEn: map['subject_en'] as String?,
      teacherId: map['teacher_id'] as String?,
      teacherName: map['teacher_name'] as String?,
      room: map['room'] as String?,
      notes: map['notes'] as String?,
    );
  }
}
