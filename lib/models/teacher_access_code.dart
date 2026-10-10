class TeacherAccessCode {
  final String id;
  final String teacherId;
  final String code;
  final String classId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  const TeacherAccessCode({
    required this.id,
    required this.teacherId,
    required this.code,
    required this.classId,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  factory TeacherAccessCode.fromMap(Map<String, dynamic> map) => TeacherAccessCode(
    id: map['id'] as String,
    teacherId: map['teacher_id'] as String,
    code: map['code'] as String,
    classId: map['class_id'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt: map['updated_at'] is String ? DateTime.parse(map['updated_at'] as String) : null,
    isActive: map['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'teacher_id': teacherId,
    'code': code,
    'class_id': classId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'is_active': isActive,
  };

  String get displayCode => 'FISE-${code.replaceFirst(RegExp(r'^FISE-', caseSensitive: false), '').toUpperCase()}';

  TeacherAccessCode copyWith({
    String? code,
    bool? isActive,
  }) => TeacherAccessCode(
    id: id,
    teacherId: teacherId,
    code: code ?? this.code,
    classId: classId,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    isActive: isActive ?? this.isActive,
  );
}
