import 'package:flutter/material.dart';

import '../../../core/services/photo_service.dart';
import '../../../models/user_profile.dart';

/// Photo de profil ronde (comme WhatsApp) ; initiales si aucune photo ou hors ligne.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.path, required this.name, this.radius = 18});

  final String? path;
  final String name;
  final double radius;

  static final PhotoService _photos = PhotoService();
  static final Map<String, Future<String?>> _urls = {};

  Future<String?> _url(String p) => _urls.putIfAbsent(p, () async {
        try {
          return await _photos.signedUrl(p);
        } catch (_) {
          _urls.remove(p);
          return null;
        }
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
    final p = path;
    if (p == null || p.isEmpty) return _initials();
    return FutureBuilder<String?>(
      future: _url(p),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return _initials();
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFDCFCE7),
          backgroundImage: NetworkImage(url),
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
