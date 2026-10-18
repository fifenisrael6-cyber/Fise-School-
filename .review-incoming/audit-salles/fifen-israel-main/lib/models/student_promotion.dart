enum StudentPromotionStatus { pending, approved, rejected, cancelled }

StudentPromotionStatus promotionStatusFromValue(Object? value) {
  return StudentPromotionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => StudentPromotionStatus.pending,
  );
}

class StudentPromotion {
  final String id;
  final String studentId;
  final String sourceClassId;
  final String destinationClassId;
  final String sourceAcademicYearId;
  final String destinationAcademicYearId;
  final StudentPromotionStatus status;
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  const StudentPromotion({
    required this.id,
    required this.studentId,
    required this.sourceClassId,
    required this.destinationClassId,
    required this.sourceAcademicYearId,
    required this.destinationAcademicYearId,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  factory StudentPromotion.fromMap(Map<String, dynamic> map) {
    return StudentPromotion(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      sourceClassId: map['source_class_id'] as String,
      destinationClassId: map['destination_class_id'] as String,
      sourceAcademicYearId: map['source_academic_year_id'] as String,
      destinationAcademicYearId: map['destination_academic_year_id'] as String,
      status: promotionStatusFromValue(map['status']),
      requestedAt: DateTime.parse(map['requested_at'] as String),
      reviewedAt: _parseDate(map['reviewed_at']),
      reviewedBy: map['reviewed_by'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class PromotionReviewItem {
  final StudentPromotion promotion;
  final String studentName;
  final String sourceClassName;
  final String destinationClassName;

  const PromotionReviewItem({
    required this.promotion,
    required this.studentName,
    required this.sourceClassName,
    required this.destinationClassName,
  });

  factory PromotionReviewItem.fromMap(Map<String, dynamic> map) {
    final profile = Map<String, dynamic>.from(map['profiles'] as Map);
    final sourceClass = Map<String, dynamic>.from(map['source_class'] as Map);
    final destinationClass = Map<String, dynamic>.from(
      map['destination_class'] as Map,
    );
    final firstName = profile['first_name'] as String? ?? '';
    final lastName = profile['last_name'] as String? ?? '';
    return PromotionReviewItem(
      promotion: StudentPromotion.fromMap(map),
      studentName: '$firstName $lastName'.trim(),
      sourceClassName: sourceClass['display_name'] as String,
      destinationClassName: destinationClass['display_name'] as String,
    );
  }
}
