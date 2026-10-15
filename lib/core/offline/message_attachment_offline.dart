import '../../models/pedagogy.dart';
import 'course_offline_service.dart';

class CachedMessageAttachment {
  final String localPath;
  final CourseResource resource;

  const CachedMessageAttachment({
    required this.localPath,
    required this.resource,
  });
}

/// Télécharge les pièces jointes ordinaires à leur première ouverture et les
/// réutilise ensuite hors ligne. Les pièces jointes à vue unique n'utilisent
/// volontairement pas ce service.
class MessageAttachmentOfflineService {
  Future<CachedMessageAttachment> open({
    required String userId,
    required String conversationId,
    required String messageId,
    required String fileName,
    required String mimeType,
    required String signedUrl,
  }) async {
    final name = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
    final normalizedMime = _mimeFor(name, mimeType);
    final resourceId = 'message-$conversationId-$messageId';
    final safeConversation = conversationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final courseId = 'messages-$safeConversation';
    final localPath = await CourseOfflineService().openExternalFile(
      userId: userId,
      resourceId: resourceId,
      courseId: courseId,
      fileName: name,
      mimeType: normalizedMime,
      signedUrlProvider: () async {
        if (signedUrl.trim().isEmpty) {
          throw StateError('attachment-url-unavailable');
        }
        return signedUrl;
      },
    );
    final resource = CourseResource(
      id: resourceId,
      courseId: courseId,
      resourceType: _resourceType(name, normalizedMime),
      storagePath: '',
      fileName: name,
      titleFr: name,
      titleEn: name,
      mimeType: normalizedMime,
    );
    return CachedMessageAttachment(localPath: localPath, resource: resource);
  }

  String _mimeFor(String name, String supplied) {
    final mime = supplied.trim().toLowerCase();
    if (mime.isNotEmpty && mime != 'application/octet-stream') return mime;
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' || 'oga' => 'audio/ogg',
      'm4a' => 'audio/mp4',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'txt' || 'csv' || 'json' || 'xml' || 'md' || 'rtf' => 'text/plain',
      _ => mime.isEmpty ? 'application/octet-stream' : mime,
    };
  }

  String _resourceType(String name, String mime) {
    final lower = name.toLowerCase();
    if (mime == 'application/pdf' || lower.endsWith('.pdf')) return 'pdf';
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('text/') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.json') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.md') ||
        lower.endsWith('.rtf')) {
      return 'text';
    }
    return 'document';
  }
}
