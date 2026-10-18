import 'exam_catalog.dart';

class AcademicYear {
  final String id;
  final String label;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;

  const AcademicYear({
    required this.id,
    required this.label,
    this.startDate,
    this.endDate,
    this.isCurrent = false,
  });

  factory AcademicYear.fromMap(Map<String, dynamic> map) {
    return AcademicYear(
      id: map['id'] as String,
      label: map['label'] as String,
      startDate: _parseDate(map['start_date']),
      endDate: _parseDate(map['end_date']),
      isCurrent: map['is_current'] as bool? ?? false,
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class SchoolClass {
  final String id;
  final String name;
  final String displayName;
  final ExamSubsystem subsystem;
  final ExamSector sector;
  final String academicYearId;
  final String? examLevelId;
  final String? seriesId;
  final String? specialtyId;
  final bool isActive;

  const SchoolClass({
    required this.id,
    required this.name,
    required this.displayName,
    required this.subsystem,
    required this.sector,
    required this.academicYearId,
    required this.isActive,
    this.examLevelId,
    this.seriesId,
    this.specialtyId,
  });

  factory SchoolClass.fromMap(Map<String, dynamic> map) {
    return SchoolClass(
      id: map['id'] as String,
      name: map['name'] as String,
      displayName: map['display_name'] as String,
      subsystem: examSubsystemFromValue(map['subsystem'])!,
      sector: examSectorFromValue(map['sector'])!,
      academicYearId: map['academic_year_id'] as String,
      examLevelId: map['exam_level_id'] as String?,
      seriesId: map['series_id'] as String?,
      specialtyId: map['specialty_id'] as String?,
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}
