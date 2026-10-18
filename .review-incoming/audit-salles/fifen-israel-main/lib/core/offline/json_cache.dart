import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cache hors ligne générique : une réponse serveur = un fichier JSON.
///
/// Utilisé pour tout ce qui n'a pas sa propre table Drift (profil, emploi du
/// temps, notifications, annales, bulletins, devoirs, progression...).
/// Aucun changement de schéma Drift n'est nécessaire.
class JsonCache {
  JsonCache._();

  static final JsonCache instance = JsonCache._();

  /// Délai maximal d'une requête réseau avant de basculer sur le cache.
  /// Sur une connexion 2G/3G instable, une requête peut rester bloquée
  /// très longtemps : on préfère afficher les données locales.
  static const Duration networkTimeout = Duration(seconds: 12);

  Directory? _dir;

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'fise_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  String _fileName(String key) =>
      '${key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.json';

  Future<File> _file(String key) async {
    final dir = await _directory();
    return File(p.join(dir.path, _fileName(key)));
  }

  Future<void> write(String key, Object? value) async {
    final file = await _file(key);
    await file.writeAsString(jsonEncode(value), flush: true);
  }

  /// Retourne la valeur décodée, ou null si absente / illisible.
  Future<Object?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Supprime tout le cache (déconnexion : un autre compte peut utiliser
  /// le même téléphone).
  Future<void> clearAll() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _dir = null;
    } catch (_) {}
  }

  /// Lit depuis le serveur et met le résultat en cache. Si le serveur est
  /// injoignable (ou trop lent), renvoie la dernière copie locale.
  /// Relance l'erreur d'origine s'il n'existe aucune copie locale.
  Future<T> cachedRead<T>({
    required String key,
    required Future<Object?> Function() fetch,
    required T Function(Object? raw) decode,
  }) async {
    try {
      final raw = await fetch().timeout(networkTimeout);
      try {
        await write(key, raw);
      } catch (_) {
        // Un cache impossible à écrire ne doit jamais casser l'écran.
      }
      return decode(raw);
    } catch (_) {
      final cached = await read(key);
      if (cached == null) rethrow;
      return decode(cached);
    }
  }
}
