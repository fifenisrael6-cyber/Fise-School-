class ClassRoom {
  final String id;
  final String name;
  final String displayName;

  const ClassRoom({
    required this.id,
    required this.name,
    required this.displayName,
  });

  factory ClassRoom.fromMap(Map<String, dynamic> map) {
    return ClassRoom(
      id: map['id'] as String,
      name: map['name'] as String,
      displayName: map['display_name'] as String? ?? map['name'] as String,
    );
  }
}
