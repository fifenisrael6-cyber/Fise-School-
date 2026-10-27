import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PickedAttachment {
  final Uint8List bytes;
  final String name;
  final String mimeType;

  const PickedAttachment({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });
}

class PhotoService {
  final ImagePicker _picker = ImagePicker();
  final SupabaseClient _client;

  PhotoService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Dernière photo de profil connue de l'utilisateur connecté. Les écrans de
  /// messagerie l'écoutent pour afficher la nouvelle photo tout de suite,
  /// sans attendre un redémarrage de l'application.
  static final ValueNotifier<({String userId, String? path})?> ownAvatar =
      ValueNotifier(null);
  static final Map<String, Future<String?>> _avatarLoads = {};

  Future<File> _avatarCacheFile(String path) async {
    final directory = await getApplicationSupportDirectory();
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return File('${directory.path}/profile_avatar_cache/${hash.toRadixString(16)}.jpg');
  }

  Future<String?> cachedAvatarPath(String? path) {
    if (path == null || path.isEmpty) return Future.value(null);
    return _avatarLoads.putIfAbsent(path, () async {
      try {
        final file = await _avatarCacheFile(path);
        if (await file.exists() && await file.length() > 0) return file.path;
        final url = await signedUrl(path);
        if (url == null || url.isEmpty) return null;
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
          return null;
        }
        await file.parent.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file.path;
      } catch (_) {
        _avatarLoads.remove(path);
        return null;
      }
    });
  }

  Future<void> _cacheAvatarBytes(String path, List<int> bytes) async {
    final file = await _avatarCacheFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    _avatarLoads[path] = Future.value(file.path);
  }

  Future<XFile?> takePhoto({double? maxWidth}) {
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: maxWidth,
    );
  }

  Future<XFile?> pickFromGallery({double? maxWidth}) => _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 85,
    maxWidth: maxWidth,
  );

  Future<PickedAttachment?> pickFile({
    List<String>? allowedExtensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return null;
    }
    return PickedAttachment(
      bytes: bytes,
      name: file.name,
      mimeType: _mimeType(file.extension),
    );
  }

  String _mimeType(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
      case 'm4a':
      case 'aac':
        return 'audio/aac';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      case 'csv':
        return 'text/csv';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String> uploadProfilePhoto(String userId, XFile file) async {
    final path = '$userId/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final bytes = await file.readAsBytes();
    await _client.storage.from('profile-photos').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(
        upsert: false,
        contentType: 'image/jpeg',
      ),
    );
    await _client.from('profiles').update({'avatar_path': path}).eq('id', userId);
    await _saveAvatarBytes(path, bytes);
    ownAvatar.value = (userId: userId, path: path);
    return path;
  }

  Future<void> deleteProfilePhoto(String userId, String? path) async {
    if (path != null && path.isNotEmpty) {
      await _client.storage.from('profile-photos').remove([path]);
      try {
        final cached = await _avatarFile(path);
        if (await cached.exists()) await cached.delete();
      } catch (_) {}
    }
    await _client.from('profiles').update({'avatar_path': null}).eq('id', userId);
    ownAvatar.value = (userId: userId, path: null);
  }

  /// Renvoie d'abord la copie locale d'un avatar. Si elle n'existe pas encore,
  /// télécharge l'image et la conserve pour les prochains affichages hors ligne.
  Future<String?> cachedAvatarFile(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = await _avatarFile(path);
      if (await file.exists() && await file.length() > 0) return file.path;
    } catch (_) {}
    try {
      final url = await signedUrl(path);
      if (url == null || url.isEmpty) return null;
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        return null;
      }
      return await _saveAvatarBytes(path, response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _client.storage.from('profile-photos').createSignedUrl(path, 3600);
  }

  Future<File> _avatarFile(String path) async {
    final base = await getApplicationSupportDirectory();
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return File(p.join(base.path, 'avatar_cache', '${hash.toRadixString(16)}.avatar'));
  }

  Future<String> _saveAvatarBytes(String path, List<int> bytes) async {
    final file = await _avatarFile(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
