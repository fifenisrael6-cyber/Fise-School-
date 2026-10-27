import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/services/photo_service.dart';
import '../../../models/user_profile.dart';

/// Avatar persistant : la copie locale est prioritaire pour un affichage rapide
/// et reste disponible hors connexion après le premier chargement.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.path, required this.name, this.radius = 18});

  final String? path;
  final String name;
  final double radius;

  static final PhotoService _photos = PhotoService();
  static final Map<String, Future<String?>> _avatarFiles = {};

  Future<String?> _localAvatar(String value) => _avatarFiles.putIfAbsent(value, () async {
        final result = await _photos.cachedAvatarFile(value);
        if (result == null) _avatarFiles.remove(value);
        return result;
      });

  Widget _initials() {
    final trimmed = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFDCFCE7),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase(),
        style: TextStyle(color: const Color(0xFF166534), fontWeight: FontWeight.w800, fontSize: radius * 0.9),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = path;
    if (avatarPath == null || avatarPath.isEmpty) return _initials();
    return FutureBuilder<String?>(
      future: _localAvatar(avatarPath),
      builder: (context, snapshot) {
        final local = snapshot.data;
        if (local == null || !File(local).existsSync()) return _initials();
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFDCFCE7),
          backgroundImage: FileImage(File(local)),
          onBackgroundImageError: (_, __) {},
        );
      },
    );
  }
}

/// Photo de l'utilisateur connecté : se met à jour dès qu'il change sa photo.
class OwnAvatar extends StatelessWidget {
  const OwnAvatar({super.key, required this.profile, this.radius = 18});

  final UserProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({String userId, String? path})?>(
      valueListenable: PhotoService.ownAvatar,
      builder: (_, latest, _) {
        final path = latest != null && latest.userId == profile.id
            ? latest.path
            : profile.avatarPath;
        return UserAvatar(
          path: path,
          name: '${profile.firstName} ${profile.lastName}',
          radius: radius,
        );
      },
    );
  }
}
