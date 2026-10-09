class GradeClassOption {
  final String id;
  final String name;
  final String displayName;

  const GradeClassOption({
    required this.id,
    required this.name,
    required this.displayName,
  });

  factory GradeClassOption.fromMap(Map<String, dynamic> map) {
    return GradeClassOption(
      id: map['id'].toString(),
      name: (map['name'] ?? '').toString(),
      displayName: (map['display_name'] ?? map['name'] ?? '').toString(),
    );
  }
}

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

class GradePeriod {
  final String id;
  final String labelFr;
  final String labelEn;
  final int position;
  final bool isPublished;

  const GradePeriod({
    required this.id,
    required this.labelFr,
    required this.labelEn,
    required this.position,
    required this.isPublished,
  });

  factory GradePeriod.fromMap(Map<String, dynamic> map) => GradePeriod(
        id: map['id'].toString(),
        labelFr: (map['label_fr'] ?? '').toString(),
        labelEn: (map['label_en'] ?? '').toString(),
        position: (map['position'] as num?)?.toInt() ?? 0,
        isPublished: map['is_published'] as bool? ?? false,
      );

  String labelFor(String lang) => lang == 'en' ? labelEn : labelFr;
}

class GradeSubject {
  final String classSubjectId;
  final String subjectId;
  final String nameFr;
  final String nameEn;
  final double coefficient;

  const GradeSubject({
    required this.classSubjectId,
    required this.subjectId,
    required this.nameFr,
    required this.nameEn,
    required this.coefficient,
  });

  factory GradeSubject.fromMap(Map<String, dynamic> map) {
    final subject = map['subjects'] is Map
        ? Map<String, dynamic>.from(map['subjects'] as Map)
        : <String, dynamic>{};
    return GradeSubject(
      classSubjectId: map['id'].toString(),
      subjectId: map['subject_id'].toString(),
      nameFr: (subject['name_fr'] ?? subject['name_en'] ?? '').toString(),
      nameEn: (subject['name_en'] ?? subject['name_fr'] ?? '').toString(),
      coefficient: _num(map['coefficient']) ?? 1,
    );
  }

  String nameFor(String lang) => lang == 'en' ? nameEn : nameFr;
}

class RosterStudent {
  final String id;
  final String firstName;
  final String lastName;

  const RosterStudent({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  factory RosterStudent.fromMap(Map<String, dynamic> map) => RosterStudent(
        id: map['student_id'].toString(),
        firstName: (map['first_name'] ?? '').toString(),
        lastName: (map['last_name'] ?? '').toString(),
      );

  String get fullName => '$lastName $firstName'.trim();
}

class StoredGrade {
  final double score;
  final String? comment;
  const StoredGrade({required this.score, this.comment});
}

class BulletinLine {
  final String nameFr;
  final String nameEn;
  final double score;
  final double maxScore;
  final double score20;
  final double coefficient;
  final double? classAverage;
  final double? classMin;
  final double? classMax;
  final String? comment;

  const BulletinLine({
    required this.nameFr,
    required this.nameEn,
    required this.score,
    required this.maxScore,
    required this.score20,
    required this.coefficient,
    this.classAverage,
    this.classMin,
    this.classMax,
    this.comment,
  });

  factory BulletinLine.fromMap(Map<String, dynamic> map) => BulletinLine(
        nameFr: (map['name_fr'] ?? '').toString(),
        nameEn: (map['name_en'] ?? '').toString(),
        score: _num(map['score']) ?? 0,
        maxScore: _num(map['max_score']) ?? 20,
        score20: _num(map['score20']) ?? 0,
        coefficient: _num(map['coefficient']) ?? 1,
        classAverage: _num(map['class_average']),
        classMin: _num(map['class_min']),
        classMax: _num(map['class_max']),
        comment: map['comment']?.toString(),
      );

  String nameFor(String lang) {
    final v = lang == 'en' ? nameEn : nameFr;
    return v.isEmpty ? (nameFr.isEmpty ? nameEn : nameFr) : v;
  }
}

class Bulletin {
  final double? average;
  final int? rank;
  final int classSize;
  final double? classAverage;
  final List<BulletinLine> lines;

  const Bulletin({
    required this.average,
    required this.rank,
    required this.classSize,
    required this.classAverage,
    required this.lines,
  });

  factory Bulletin.fromMap(Map<String, dynamic> map) {
    final raw = map['subjects'];
    final lines = raw is List
        ? raw
            .map((e) => BulletinLine.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false)
        : const <BulletinLine>[];
    return Bulletin(
      average: _num(map['average']),
      rank: (map['rank'] as num?)?.toInt(),
      classSize: (map['class_size'] as num?)?.toInt() ?? 0,
      classAverage: _num(map['class_average']),
      lines: lines,
    );
  }

  /// Appréciation à partir de la moyenne sur 20.
  static String appreciation(double? avg, bool fr) {
    if (avg == null) {
      return '-';
    }
    if (avg >= 16) {
      return fr ? 'Très bien' : 'Excellent';
    }
    if (avg >= 14) {
      return fr ? 'Bien' : 'Very good';
    }
    if (avg >= 12) {
      return fr ? 'Assez bien' : 'Good';
    }
    if (avg >= 10) {
      return fr ? 'Passable' : 'Fair';
    }
    return fr ? 'Insuffisant' : 'Insufficient';
  }
}
