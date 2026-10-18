enum ExamSubsystem { francophone, anglophone }

enum ExamSector { general, technical }

enum VerificationStatus { verified, pendingOfficialConfirmation }

ExamSubsystem? examSubsystemFromValue(Object? value) {
  return ExamSubsystem.values.cast<ExamSubsystem?>().firstWhere(
    (item) => item!.name == value,
    orElse: () => null,
  );
}

ExamSector? examSectorFromValue(Object? value) {
  return ExamSector.values.cast<ExamSector?>().firstWhere(
    (item) => item!.name == value,
    orElse: () => null,
  );
}

VerificationStatus verificationStatusFromValue(Object? value) {
  return value == 'verified'
      ? VerificationStatus.verified
      : VerificationStatus.pendingOfficialConfirmation;
}

class ExamDefinition {
  final String id;
  final String code;
  final String nameFr;
  final String nameEn;
  final VerificationStatus verification;
  final String? sourceUrl;
  final bool active;

  const ExamDefinition({
    required this.id,
    required this.code,
    required this.nameFr,
    required this.nameEn,
    required this.verification,
    required this.active,
    this.sourceUrl,
  });

  factory ExamDefinition.fromMap(Map<String, dynamic> map) {
    return ExamDefinition(
      id: map['id'] as String,
      code: map['code'] as String,
      nameFr: map['name_fr'] as String,
      nameEn: map['name_en'] as String,
      verification: verificationStatusFromValue(map['verification_status']),
      sourceUrl: map['source_url'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }

  String labelFor(String languageCode) =>
      languageCode == 'en' ? nameEn : nameFr;
}

class ExamCatalogEntry {
  final String id;
  final String code;
  final String nameFr;
  final String nameEn;
  final VerificationStatus verification;
  final String? sourceUrl;
  final bool active;

  const ExamCatalogEntry({
    required this.id,
    required this.code,
    required this.nameFr,
    required this.nameEn,
    required this.verification,
    required this.active,
    this.sourceUrl,
  });

  factory ExamCatalogEntry.fromMap(Map<String, dynamic> map) {
    return ExamCatalogEntry(
      id: map['id'] as String,
      code: map['code'] as String,
      nameFr: map['name_fr'] as String,
      nameEn: map['name_en'] as String,
      verification: verificationStatusFromValue(map['verification_status']),
      sourceUrl: map['source_url'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }

  String labelFor(String languageCode) =>
      languageCode == 'en' ? nameEn : nameFr;
}

class ExamLevel {
  final String id;
  final String code;
  final ExamSubsystem subsystem;
  final ExamSector sector;
  final String levelNameFr;
  final String levelNameEn;

  /// Examen préparé dans cette classe. Null pour une classe sans examen
  /// (6ème, Form 1, ...).
  final ExamDefinition? exam;
  final bool isExamClass;
  final int levelOrder;
  final String? curriculumFr;
  final String? curriculumEn;
  final VerificationStatus verification;
  final String? sourceUrl;
  final bool active;

  const ExamLevel({
    required this.id,
    required this.code,
    required this.subsystem,
    required this.sector,
    required this.levelNameFr,
    required this.levelNameEn,
    required this.verification,
    required this.active,
    this.exam,
    this.isExamClass = false,
    this.levelOrder = 0,
    this.curriculumFr,
    this.curriculumEn,
    this.sourceUrl,
  });

  factory ExamLevel.fromMap(Map<String, dynamic> map) {
    final examMap = map['exams'];
    return ExamLevel(
      id: map['id'] as String,
      code: map['code'] as String,
      subsystem: examSubsystemFromValue(map['subsystem'])!,
      sector: examSectorFromValue(map['sector'])!,
      levelNameFr: map['level_name_fr'] as String,
      levelNameEn: map['level_name_en'] as String,
      exam: examMap is Map
          ? ExamDefinition.fromMap(Map<String, dynamic>.from(examMap))
          : null,
      isExamClass: map['is_exam_class'] as bool? ?? examMap is Map,
      levelOrder: (map['level_order'] as num?)?.toInt() ?? 0,
      curriculumFr: map['curriculum_fr'] as String?,
      curriculumEn: map['curriculum_en'] as String?,
      verification: verificationStatusFromValue(map['verification_status']),
      sourceUrl: map['source_url'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }

  String labelFor(String languageCode) =>
      languageCode == 'en' ? levelNameEn : levelNameFr;

  String? curriculumFor(String languageCode) =>
      languageCode == 'en' ? curriculumEn : curriculumFr;
}

class ExamSelection {
  final ExamLevel level;
  final ExamCatalogEntry? series;
  final ExamCatalogEntry? specialty;

  const ExamSelection({required this.level, this.series, this.specialty});

  String? get seriesId => series?.id;
  String? get specialtyId => specialty?.id;
}
