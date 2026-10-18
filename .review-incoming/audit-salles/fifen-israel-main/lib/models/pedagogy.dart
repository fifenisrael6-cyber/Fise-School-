import 'exam_catalog.dart';

class Subject {
  final String id, nameFr, nameEn, code;
  final ExamSubsystem subsystem;
  final ExamSector sector;
  final String? descriptionFr, descriptionEn;
  final bool isActive;

  const Subject({
    required this.id,
    required this.nameFr,
    required this.nameEn,
    required this.code,
    required this.subsystem,
    required this.sector,
    this.descriptionFr,
    this.descriptionEn,
    this.isActive = true,
  });
  factory Subject.fromMap(Map<String, dynamic> map) => Subject(
    id: map['id'] as String,
    nameFr: map['name_fr'] as String,
    nameEn: map['name_en'] as String,
    code: map['code'] as String,
    subsystem: examSubsystemFromValue(map['subsystem'])!,
    sector: examSectorFromValue(map['sector'])!,
    descriptionFr: map['description_fr'] as String?,
    descriptionEn: map['description_en'] as String?,
    isActive: map['is_active'] as bool? ?? true,
  );
  String labelFor(String languageCode) =>
      languageCode == 'en' ? nameEn : nameFr;
}


class ClassSubjectEntry {
  final Subject subject;
  final bool isCompulsory;
  final String? optionGroup;
  final int position;

  const ClassSubjectEntry({
    required this.subject,
    required this.isCompulsory,
    this.optionGroup,
    this.position = 0,
  });

  factory ClassSubjectEntry.fromMap(Map<String, dynamic> map) {
    final raw = map['subjects'];
    if (raw is! Map) {
      throw const FormatException('Subject missing');
    }
    return ClassSubjectEntry(
      subject: Subject.fromMap(Map<String, dynamic>.from(raw)),
      isCompulsory: map['is_compulsory'] as bool? ?? true,
      optionGroup: map['option_group'] as String?,
      position: map['position'] as int? ?? 0,
    );
  }
}

class Curriculum {
  final String id, subjectId, titleFr, titleEn;
  final ExamSubsystem subsystem;
  final ExamSector sector;
  final String? examLevelId,
      seriesId,
      specialtyId,
      descriptionFr,
      descriptionEn;
  final bool isActive;
  const Curriculum({
    required this.id,
    required this.subjectId,
    required this.titleFr,
    required this.titleEn,
    required this.subsystem,
    required this.sector,
    this.examLevelId,
    this.seriesId,
    this.specialtyId,
    this.descriptionFr,
    this.descriptionEn,
    this.isActive = true,
  });
  factory Curriculum.fromMap(Map<String, dynamic> map) => Curriculum(
    id: map['id'] as String,
    subjectId: map['subject_id'] as String,
    titleFr: map['title_fr'] as String,
    titleEn: map['title_en'] as String,
    subsystem: examSubsystemFromValue(map['subsystem'])!,
    sector: examSectorFromValue(map['sector'])!,
    examLevelId: map['exam_level_id'] as String?,
    seriesId: map['series_id'] as String?,
    specialtyId: map['specialty_id'] as String?,
    descriptionFr: map['description_fr'] as String?,
    descriptionEn: map['description_en'] as String?,
    isActive: map['is_active'] as bool? ?? true,
  );
  String labelFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;
}

class CourseChapter {
  final String id, curriculumId, titleFr, titleEn;
  final String? descriptionFr, descriptionEn;
  final int position;
  final bool isActive;
  const CourseChapter({
    required this.id,
    required this.curriculumId,
    required this.titleFr,
    required this.titleEn,
    this.descriptionFr,
    this.descriptionEn,
    this.position = 0,
    this.isActive = true,
  });
  factory CourseChapter.fromMap(Map<String, dynamic> map) => CourseChapter(
    id: map['id'] as String,
    curriculumId: map['curriculum_id'] as String,
    titleFr: map['title_fr'] as String,
    titleEn: map['title_en'] as String,
    descriptionFr: map['description_fr'] as String?,
    descriptionEn: map['description_en'] as String?,
    position: map['position'] as int? ?? 0,
    isActive: map['is_active'] as bool? ?? true,
  );
  String labelFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;
}

class Course {
  final String id, subjectId, teacherId, titleFr, titleEn, status;
  final String? curriculumId,
      chapterId,
      classId,
      descriptionFr,
      descriptionEn,
      contentFr,
      contentEn;
  final bool smartLessonEnabled;
  final int minimumExerciseScore;
  final DateTime? publishedAt;
  const Course({
    required this.id,
    this.curriculumId,
    this.chapterId,
    required this.subjectId,
    required this.teacherId,
    required this.titleFr,
    required this.titleEn,
    required this.status,
    this.classId,
    this.descriptionFr,
    this.descriptionEn,
    this.contentFr,
    this.contentEn,
    this.smartLessonEnabled = true,
    this.minimumExerciseScore = 50,
    this.publishedAt,
  });
  factory Course.fromMap(Map<String, dynamic> map) => Course(
    id: map['id'] as String,
    curriculumId: map['curriculum_id'] as String?,
    chapterId: map['chapter_id'] as String?,
    subjectId: map['subject_id'] as String,
    teacherId: map['teacher_id'] as String,
    classId: map['class_id'] as String?,
    titleFr: map['title_fr'] as String,
    titleEn: map['title_en'] as String,
    descriptionFr: map['description_fr'] as String?,
    descriptionEn: map['description_en'] as String?,
    contentFr: map['content_fr'] as String?,
    contentEn: map['content_en'] as String?,
    smartLessonEnabled: map['smart_lesson_enabled'] as bool? ?? true,
    minimumExerciseScore: (map['minimum_exercise_score'] as num?)?.toInt() ?? 50,
    status: map['status'] as String? ?? 'draft',
    publishedAt: map['published_at'] is String
        ? DateTime.tryParse(map['published_at'] as String)
        : null,
  );
  String labelFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;
}

class Lesson {
  final String id, courseId, titleFr, titleEn;
  final String? contentFr,
      contentEn,
      objectivesFr,
      objectivesEn,
      examplesFr,
      examplesEn,
      summaryFr,
      summaryEn;
  final int position;
  final int? estimatedMinutes;
  final bool isPublished;
  const Lesson({
    required this.id,
    required this.courseId,
    required this.titleFr,
    required this.titleEn,
    this.contentFr,
    this.contentEn,
    this.objectivesFr,
    this.objectivesEn,
    this.examplesFr,
    this.examplesEn,
    this.summaryFr,
    this.summaryEn,
    this.position = 0,
    this.estimatedMinutes,
    this.isPublished = false,
  });
  factory Lesson.fromMap(Map<String, dynamic> map) => Lesson(
    id: map['id'] as String,
    courseId: map['course_id'] as String,
    titleFr: map['title_fr'] as String,
    titleEn: map['title_en'] as String,
    contentFr: map['content_fr'] as String?,
    contentEn: map['content_en'] as String?,
    objectivesFr: map['objectives_fr'] as String?,
    objectivesEn: map['objectives_en'] as String?,
    examplesFr: map['examples_fr'] as String?,
    examplesEn: map['examples_en'] as String?,
    summaryFr: map['summary_fr'] as String?,
    summaryEn: map['summary_en'] as String?,
    position: map['position'] as int? ?? 0,
    estimatedMinutes: map['estimated_minutes'] as int?,
    isPublished: map['is_published'] as bool? ?? false,
  );
  String labelFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;
}

class CourseResource {
  final String id,
      courseId,
      resourceType,
      storagePath,
      fileName,
      titleFr,
      titleEn;
  final String? lessonId, mimeType;
  final int? fileSize, position, indexWordCount;
  final String indexStatus, indexError, indexPreview;
  final bool indexApproved;
  final DateTime? indexedAt, updatedAt;
  const CourseResource({
    required this.id,
    required this.courseId,
    required this.resourceType,
    required this.storagePath,
    required this.fileName,
    required this.titleFr,
    required this.titleEn,
    this.lessonId,
    this.mimeType,
    this.fileSize,
    this.position,
    this.indexStatus = 'pending',
    this.indexError = '',
    this.indexPreview = '',
    this.indexWordCount = 0,
    this.indexApproved = false,
    this.indexedAt,
    this.updatedAt,
  });
  factory CourseResource.fromMap(Map<String, dynamic> map) => CourseResource(
    id: map['id'] as String,
    courseId: map['course_id'] as String,
    lessonId: map['lesson_id'] as String?,
    resourceType: map['resource_type'] as String,
    storagePath: map['storage_path'] as String,
    fileName: map['file_name'] as String,
    mimeType: map['mime_type'] as String?,
    fileSize: (map['file_size'] as num?)?.toInt(),
    titleFr: map['title_fr'] as String,
    titleEn: map['title_en'] as String,
    position: (map['position'] as num?)?.toInt(),
    indexStatus: map['index_status'] as String? ?? 'pending',
    indexError: map['index_error'] as String? ?? '',
    indexPreview: map['index_preview'] as String? ?? '',
    indexWordCount: (map['index_word_count'] as num?)?.toInt() ?? 0,
    indexApproved: map['index_approved'] as bool? ?? false,
    indexedAt: _parseOptionalDate(map['indexed_at']),
    updatedAt: _parseOptionalDate(map['updated_at']),
  );
  static DateTime? _parseOptionalDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  String labelFor(String languageCode) =>
      languageCode == 'en' ? titleEn : titleFr;
}

class LessonProgress {
  final String id, studentId, lessonId, status;
  final int progressPercent;
  final DateTime? startedAt, completedAt, lastOpenedAt, updatedAt;
  const LessonProgress({
    required this.id,
    required this.studentId,
    required this.lessonId,
    required this.status,
    required this.progressPercent,
    this.startedAt,
    this.completedAt,
    this.lastOpenedAt,
    this.updatedAt,
  });
  factory LessonProgress.fromMap(Map<String, dynamic> map) => LessonProgress(
    id: map['id'] as String,
    studentId: map['student_id'] as String,
    lessonId: map['lesson_id'] as String,
    status: map['status'] as String,
    progressPercent: map['progress_percent'] as int? ?? 0,
    startedAt: _date(map['started_at']),
    completedAt: _date(map['completed_at']),
    lastOpenedAt: _date(map['last_opened_at']),
    updatedAt: _date(map['updated_at']),
  );
  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
