import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
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
    ownAvatar.value = (userId: userId, path: path);
    return path;
  }

  Future<void> deleteProfilePhoto(String userId, String? path) async {
    if (path != null && path.isNotEmpty) {
      await _client.storage.from('profile-photos').remove([path]);
    }
    await _client.from('profiles').update({'avatar_path': null}).eq('id', userId);
    ownAvatar.value = (userId: userId, path: null);
  }

  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    return _client.storage.from('profile-photos').createSignedUrl(path, 3600);
  }
}
