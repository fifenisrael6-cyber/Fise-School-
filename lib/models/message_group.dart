class MessageGroup {
  final String id;
  final String name;
  final String? classId;
  final String? className;
  final String ownerId;
  final String? inviteCode;
  final int memberCount;
  final String? lastBody;
  final DateTime? lastAt;

  const MessageGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    this.classId,
    this.className,
    this.inviteCode,
    this.memberCount = 0,
    this.lastBody,
    this.lastAt,
  });

  factory MessageGroup.fromMap(Map<String, dynamic> map) {
    final last = map['last_at'];
    return MessageGroup(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      classId: map['class_id'] as String?,
      className: map['class_name'] as String?,
      ownerId: map['owner_id'] as String,
      inviteCode: map['invite_code'] as String?,
      memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
      lastBody: map['last_body'] as String?,
      lastAt: last is String ? DateTime.tryParse(last) : null,
    );
  }
}

class GroupMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String body;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final DateTime createdAt;

  const GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
  });

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    return GroupMessage(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String? ?? '',
      senderRole: map['sender_role'] as String? ?? '',
      body: map['body'] as String? ?? '',
      attachmentPath: map['attachment_path'] as String?,
      attachmentName: map['attachment_name'] as String?,
      attachmentType: map['attachment_type'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class GroupMember {
  final String userId;
  final String fullName;
  final String role;

  const GroupMember({
    required this.userId,
    required this.fullName,
    required this.role,
  });

  factory GroupMember.fromMap(Map<String, dynamic> map) {
    return GroupMember(
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String? ?? '',
      role: map['role'] as String? ?? 'student',
    );
  }
}

class GroupMessageReceipt {
  final int deliveredCount;
  final int readCount;
  final int recipientCount;

  const GroupMessageReceipt({
    required this.deliveredCount,
    required this.readCount,
    required this.recipientCount,
  });

  factory GroupMessageReceipt.fromMap(Map<String, dynamic> map) {
    return GroupMessageReceipt(
      deliveredCount: (map['delivered_count'] as num?)?.toInt() ?? 0,
      readCount: (map['read_count'] as num?)?.toInt() ?? 0,
      recipientCount: (map['recipient_count'] as num?)?.toInt() ?? 0,
    );
  }
}
