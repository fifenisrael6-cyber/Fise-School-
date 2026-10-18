class ForumClass {
  final String id;
  final String name;
  final String displayName;

  const ForumClass({
    required this.id,
    required this.name,
    required this.displayName,
  });

  factory ForumClass.fromMap(Map<String, dynamic> map) {
    return ForumClass(
      id: map['id'] as String,
      name: (map['name'] ?? '').toString(),
      displayName: (map['display_name'] ?? map['name'] ?? '').toString(),
    );
  }
}

class TeacherClassChoice {
  final String id;
  final String displayName;
  final bool isSelected;

  const TeacherClassChoice({
    required this.id,
    required this.displayName,
    required this.isSelected,
  });

  factory TeacherClassChoice.fromMap(Map<String, dynamic> map) {
    return TeacherClassChoice(
      id: map['id'] as String,
      displayName: (map['display_name'] ?? map['name'] ?? '').toString(),
      isSelected: map['is_selected'] as bool? ?? false,
    );
  }
}

class ForumTopic {
  final String id;
  final String classId;
  final String authorId;
  final String title;
  final String? description;
  final bool isPinned;
  final bool isLocked;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ForumTopic({
    required this.id,
    required this.classId,
    required this.authorId,
    required this.title,
    required this.description,
    required this.isPinned,
    required this.isLocked,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ForumTopic.fromMap(Map<String, dynamic> map) {
    return ForumTopic(
      id: map['id'] as String,
      classId: map['class_id'] as String,
      authorId: map['creator_id'] as String,
      title: (map['title'] ?? '').toString(),
      description: map['description']?.toString(),
      isPinned: map['is_pinned'] as bool? ?? false,
      isLocked: map['is_locked'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'].toString()),
      updatedAt: DateTime.parse(map['updated_at'].toString()),
    );
  }
}

class ForumPost {
  final String id;
  final String topicId;
  final String authorId;
  final String? body;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final int? attachmentSize;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ForumPost({
    required this.id,
    required this.topicId,
    required this.authorId,
    required this.body,
    required this.attachmentPath,
    required this.attachmentName,
    required this.attachmentType,
    required this.attachmentSize,
    required this.createdAt,
    required this.updatedAt,
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

  factory ForumPost.fromMap(Map<String, dynamic> map) {
    return ForumPost(
      id: map['id'] as String,
      topicId: map['topic_id'] as String,
      authorId: map['author_id'] as String,
      body: map['content']?.toString(),
      attachmentPath: map['attachment_path']?.toString(),
      attachmentName: map['attachment_name']?.toString(),
      attachmentType: map['attachment_type']?.toString(),
      attachmentSize: map['attachment_size'] is int
          ? map['attachment_size'] as int
          : int.tryParse(map['attachment_size']?.toString() ?? ''),
      createdAt: DateTime.parse(map['created_at'].toString()),
      updatedAt: DateTime.parse(map['updated_at'].toString()),
    );
  }
}
