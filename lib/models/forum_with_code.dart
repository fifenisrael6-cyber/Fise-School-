/// Forum unique avec code d'accès enseignant/élève
/// Structure simplifiée type "groupe WhatsApp de classe"
class ClassForum {
  final String id;
  final String accessCode; // Code unique généré (ex: FISE-AB12C)
  final String classId;
  final String className;
  final String? filière; // Filière au programme Cameroun
  final String createdBy; // ID enseignant
  final DateTime createdAt;
  final bool isActive;

  const ClassForum({
    required this.id,
    required this.accessCode,
    required this.classId,
    required this.className,
    this.filière,
    required this.createdBy,
    required this.createdAt,
    required this.isActive,
  });

  factory ClassForum.fromMap(Map<String, dynamic> map) {
    return ClassForum(
      id: map['id'] as String,
      accessCode: map['access_code'] as String,
      classId: map['class_id'] as String,
      className: map['class_name'] as String,
      filière: map['filière'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'].toString()),
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

/// Message de forum - simple et chronologique
class ClassForumMessage {
  final String id;
  final String forumId;
  final String authorId;
  final String authorName;
  final String authorRole; // 'teacher' ou 'student'
  final String body;
  final DateTime createdAt;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;

  const ClassForumMessage({
    required this.id,
    required this.forumId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    this.attachmentSize,
  });

  bool get hasAttachment =>
      attachmentPath != null && attachmentPath!.trim().isNotEmpty;

  bool get isImage =>
      attachmentType != null && attachmentType!.startsWith('image/');

  bool get isPdf => attachmentType == 'application/pdf';

  bool get isVideo =>
      attachmentType != null && attachmentType!.startsWith('video/');

  bool get isAudio =>
      attachmentType != null && attachmentType!.startsWith('audio/');

  factory ClassForumMessage.fromMap(Map<String, dynamic> map) {
    return ClassForumMessage(
      id: map['id'] as String,
      forumId: map['forum_id'] as String,
      authorId: map['author_id'] as String,
      authorName: (map['author_name'] ?? '').toString(),
      authorRole: (map['author_role'] ?? 'student').toString(),
      body: (map['body'] ?? '').toString(),
      createdAt: DateTime.parse(map['created_at'].toString()),
      attachmentPath: map['attachment_path']?.toString(),
      attachmentName: map['attachment_name']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
      attachmentSize: map['attachment_size'] is int
          ? map['attachment_size'] as int
          : int.tryParse(map['attachment_size']?.toString() ?? ''),
    );
  }
}

/// Messagerie privée enseignant/élève
class TeacherStudentMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole; // 'teacher' ou 'student'
  final String recipientId;
  final String recipientName;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;

  const TeacherStudentMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.recipientId,
    required this.recipientName,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
  });

  factory TeacherStudentMessage.fromMap(Map<String, dynamic> map) {
    return TeacherStudentMessage(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      senderName: (map['sender_name'] ?? '').toString(),
      senderRole: (map['sender_role'] ?? 'student').toString(),
      recipientId: map['recipient_id'] as String,
      recipientName: (map['recipient_name'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      createdAt: DateTime.parse(map['created_at'].toString()),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'].toString()),
      attachmentPath: map['attachment_path']?.toString(),
      attachmentName: map['attachment_name']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
    );
  }
}
