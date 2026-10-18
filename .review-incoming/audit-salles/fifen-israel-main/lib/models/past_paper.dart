class PastPaper {
  final String id;
  final String? examId;
  final String? subsystem;
  final int year;
  final String? session;
  final String subjectFr;
  final String subjectEn;
  final String kind;
  final String filePath;
  final String fileName;
  final bool isPublished;

  const PastPaper({
    required this.id,
    required this.year,
    required this.subjectFr,
    required this.subjectEn,
    required this.kind,
    required this.filePath,
    required this.fileName,
    required this.isPublished,
    this.examId,
    this.subsystem,
    this.session,
  });

  factory PastPaper.fromMap(Map<String, dynamic> map) {
    return PastPaper(
      id: map['id'].toString(),
      examId: map['exam_id']?.toString(),
      subsystem: map['subsystem']?.toString(),
      year: (map['exam_year'] as num).toInt(),
      session: map['session_label']?.toString(),
      subjectFr: (map['subject_fr'] ?? '').toString(),
      subjectEn: (map['subject_en'] ?? '').toString(),
      kind: (map['kind'] ?? 'subject').toString(),
      filePath: map['file_path'].toString(),
      fileName: (map['file_name'] ?? '').toString(),
      isPublished: map['is_published'] as bool? ?? true,
    );
  }

  bool get isCorrection => kind == 'correction';

  String subjectFor(String languageCode) {
    final value = languageCode == 'en' ? subjectEn : subjectFr;
    return value.trim().isEmpty ? (subjectFr.isEmpty ? subjectEn : subjectFr) : value;
  }
}
