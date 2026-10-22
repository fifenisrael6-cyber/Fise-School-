class MessageContact {
  final String id;
  final String firstName;
  final String lastName;
  final String role;
  final String? className;
  final String? avatarPath;

  const MessageContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.className,
    this.avatarPath,
  });

  factory MessageContact.fromMap(Map<String, dynamic> map) {
    return MessageContact(
      id: map['id'] as String,
      firstName: map['first_name'] as String? ?? '',
      lastName: map['last_name'] as String? ?? '',
      role: map['role'] as String? ?? '',
      className: map['class_name'] as String?,
      avatarPath: map['avatar_path'] as String?,
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}

class PrivateMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentType;
  final String? localAttachmentPath;
  final String? replyToId;
  final bool isPending;

  const PrivateMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
    this.localAttachmentPath,
    this.replyToId,
    this.isPending = false,
  });

  factory PrivateMessage.fromMap(Map<String, dynamic> map) {
    return PrivateMessage(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      recipientId: map['recipient_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      deliveredAt: map['delivered_at'] == null
          ? null
          : DateTime.parse(map['delivered_at'] as String),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String),
      attachmentPath: map['attachment_path'] as String?,
      attachmentName: map['attachment_name'] as String?,
      attachmentType: map['attachment_type'] as String?,
      localAttachmentPath: map['local_attachment_path'] as String?,
      replyToId: map['reply_to_id'] as String?,
      isPending: map['is_pending'] as bool? ?? false,
    );
  }
}
