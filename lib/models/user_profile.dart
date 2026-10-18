class UserProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final String role;
  final String preferredLanguage;
  final String? subsystem;
  final String? sector;
  final String? examLevelId;
  final String? examId;
  final String? seriesId;
  final String? specialtyId;
  final String? examLevel;
  final String? exam;
  final String? track;
  final String? className;
  final String? avatarPath;

  const UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.role = 'student',
    this.preferredLanguage = 'fr',
    this.subsystem,
    this.sector,
    this.examLevelId,
    this.examId,
    this.seriesId,
    this.specialtyId,
    this.examLevel,
    this.exam,
    this.track,
    this.className,
    this.avatarPath,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      email: map['email'] as String?,
      role: map['role'] as String? ?? 'student',
      preferredLanguage: map['preferred_language'] as String? ?? 'fr',
      subsystem: map['subsystem'] as String?,
      sector: map['sector'] as String?,
      examLevelId: map['exam_level_id'] as String?,
      examId: map['exam_id'] as String?,
      seriesId: map['series_id'] as String?,
      specialtyId: map['specialty_id'] as String?,
      examLevel:
          map['exam_level_label'] as String? ?? map['exam_level'] as String?,
      exam: map['exam_label'] as String? ?? map['exam'] as String?,
      track: map['track_label'] as String? ?? map['track'] as String?,
      className: map['class_name'] as String?,
      avatarPath: map['avatar_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': role,
      'preferred_language': preferredLanguage,
      'subsystem': subsystem,
      'sector': sector,
      'exam_level_id': examLevelId,
      'exam_id': examId,
      'series_id': seriesId,
      'specialty_id': specialtyId,
      'exam_level_label': examLevel,
      'exam_label': exam,
      'track_label': track,
      'class_name': className,
      'avatar_path': avatarPath,
    };
  }
}
