import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'json_cache.dart';
import 'offline_repository.dart';
import 'pending_progress.dart';

/// À appeler AVANT `auth.signOut()` : envoie ce qui a été fait hors ligne
/// (si le réseau est là), puis efface toutes les données locales pour qu'un
/// autre compte utilisant le même téléphone ne voie rien du précédent.
Future<void> clearLocalUserData() async {
  try {
    if (await ConnectivityService().isOnline()) {
      await PendingProgress.instance.flush(Supabase.instance.client);
    }
  } catch (e) {
    debugPrint('Envoi de la progression en attente impossible : $e');
  }

  try {
    final offline = OfflineRepository();
    await offline.clearCourses();
    await offline.clearLessons();
    await offline.clearProgress();
    await JsonCache.instance.clearAll();
  } catch (e) {
    debugPrint('Nettoyage du cache hors ligne impossible : $e');
  }
}
