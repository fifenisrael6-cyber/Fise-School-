import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/forum.dart';
import '../../models/user_profile.dart';

class ForumService {
  final SupabaseClient _client;

  ForumService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<ForumClass>> listClasses(UserProfile profile) async {
    if (profile.role == 'student') {
      final rows = await _client
          .from('class_students')
          .select('class_id, school_classes(id, name, display_name)')
          .eq('student_id', profile.id)
          .eq('is_active', true);

      return rows
          .map((row) {
            final data = Map<String, dynamic>.from(
              row['school_classes'] as Map,
            );

            return ForumClass.fromMap(data);
          })
          .toList(growable: false);
    }

    if (profile.role == 'teacher') {
      final rows = await _client
          .from('class_teachers')
          .select('class_id, school_classes(id, name, display_name)')
          .eq('teacher_id', profile.id)
          .eq('is_active', true);

      return rows
          .map((row) {
            final data = Map<String, dynamic>.from(
              row['school_classes'] as Map,
            );

            return ForumClass.fromMap(data);
          })
          .toList(growable: false);
    }

    return const [];
  }

  /// Salles que l'enseignant peut choisir de suivre, avec l'état de sélection.
  Future<List<TeacherClassChoice>> listTeacherClassChoices() async {
    final rows = await _client.rpc('list_classes_for_teacher_choice');
    return (rows as List)
        .map((row) => TeacherClassChoice.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  }

  /// Remplace l'ensemble des salles suivies par l'enseignant connecté.
  Future<void> setTeacherClasses(List<String> classIds) async {
    await _client.rpc('teacher_set_my_classes', params: {'p_class_ids': classIds});
  }

  Future<List<ForumTopic>> listTopics(String classId) async {
    final rows = await _client
        .from('forum_topics')
        .select()
        .eq('class_id', classId)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);

    return rows
        .map((row) => ForumTopic.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ForumPost>> listPosts(String topicId) async {
    final rows = await _client
        .from('forum_posts')
        .select()
        .eq('topic_id', topicId)
        .order('created_at', ascending: true);

    return rows
        .map((row) => ForumPost.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<ForumTopic> createTopic({
    required String classId,
    required String authorId,
    required String authorName,
    required String title,
    String? description,
  }) async {
    final row = await _client
        .from('forum_topics')
        .insert({
          'class_id': classId,
          'creator_id': authorId,
          'creator_name': authorName.trim(),
          'title': title.trim(),
          'description': description?.trim().isEmpty == true
              ? null
              : description?.trim(),
        })
        .select()
        .single();

    return ForumTopic.fromMap(Map<String, dynamic>.from(row));
  }

  Future<ForumPost> createPost({
    required String topicId,
    required String authorId,
    required String authorName,
    String? body,
    PlatformFile? attachment,
    required String classId,
  }) async {
    final cleanBody = body?.trim();

    if ((cleanBody == null || cleanBody.isEmpty) && attachment == null) {
      throw Exception('Post cannot be empty.');
    }

    final postRow = await _client
        .from('forum_posts')
        .insert({
          'topic_id': topicId,
          'author_id': authorId,
          'author_name': authorName.trim(),
          'content': cleanBody ?? '',
        })
        .select()
        .single();

    var post = ForumPost.fromMap(Map<String, dynamic>.from(postRow));

    if (attachment != null) {
      final bytes = attachment.bytes;

      if (bytes == null || bytes.isEmpty) {
        await _client.from('forum_posts').delete().eq('id', post.id);
        throw Exception('Unable to read the selected file.');
      }

      final safeName = _sanitizeFileName(attachment.name);
      final path =
          '$classId/${post.id}/${DateTime.now().microsecondsSinceEpoch}_$safeName';

      try {
        await _client.storage
            .from('forum-attachments')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: attachment.extension != null
                    ? _contentTypeFromExtension(attachment.extension!)
                    : 'application/octet-stream',
                upsert: false,
              ),
            );

        final updatedRow = await _client
            .from('forum_posts')
            .update({
              'attachment_path': path,
              'attachment_name': attachment.name,
              'attachment_type': attachment.extension != null
                  ? _contentTypeFromExtension(attachment.extension!)
                  : 'application/octet-stream',
              'attachment_size': attachment.size,
            })
            .eq('id', post.id)
            .select()
            .single();

        post = ForumPost.fromMap(Map<String, dynamic>.from(updatedRow));
      } catch (_) {
        try {
          await _client.storage.from('forum-attachments').remove([path]);
        } catch (e) {
          debugPrint('Nettoyage pièce jointe forum impossible: $e');
        }
        try {
          await _client.from('forum_posts').delete().eq('id', post.id);
        } catch (e) {
          debugPrint('Nettoyage message forum impossible: $e');
        }
        rethrow;
      }
    }

    return post;
  }

  Future<String> createAttachmentSignedUrl(String path) async {
    return _client.storage
        .from('forum-attachments')
        .createSignedUrl(path, 60 * 60);
  }

  Future<void> deletePost(ForumPost post) async {
    if (post.attachmentPath != null && post.attachmentPath!.isNotEmpty) {
      await _client.storage.from('forum-attachments').remove([
        post.attachmentPath!,
      ]);
    }

    await _client.from('forum_posts').delete().eq('id', post.id);
  }

  Future<void> updateTopicLock(String topicId, bool value) async {
    await _client
        .from('forum_topics')
        .update({'is_locked': value})
        .eq('id', topicId);
  }

  Future<void> updateTopicPin(String topicId, bool value) async {
    await _client
        .from('forum_topics')
        .update({'is_pinned': value})
        .eq('id', topicId);
  }

  Future<void> deleteTopic(String topicId) async {
    await _client.from('forum_topics').delete().eq('id', topicId);
  }

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _contentTypeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';

      case 'png':
        return 'image/png';

      case 'webp':
        return 'image/webp';

      case 'gif':
        return 'image/gif';

      case 'pdf':
        return 'application/pdf';

      case 'mp4':
        return 'video/mp4';

      case 'mov':
        return 'video/quicktime';

      case 'webm':
        return 'video/webm';

      case 'mp3':
        return 'audio/mpeg';

      case 'wav':
        return 'audio/wav';

      case 'm4a':
        return 'audio/mp4';

      default:
        return 'application/octet-stream';
    }
  }
}
