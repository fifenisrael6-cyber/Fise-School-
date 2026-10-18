import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'json_cache.dart';

/// File d'attente des progressions de leçons faites sans connexion.
/// Elles sont envoyées au serveur au retour du réseau.
class PendingProgress {
  PendingProgress._();

  static final PendingProgress instance = PendingProgress._();

  static const String _key = 'pending_progress';

  bool _flushing = false;

  String _id(Map<String, dynamic> item) =>
      '${item['student_id']}:${item['lesson_id']}';

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await JsonCache.instance.read(_key);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int> count() async => (await _load()).length;

  /// Ajoute (ou remplace) l'état en attente d'une leçon.
  /// Une leçon terminée n'est jamais « rétrogradée » par une simple ouverture.
  Future<void> enqueue(Map<String, dynamic> values) async {
    final items = await _load();
    final id = _id(values);
    final index = items.indexWhere((e) => _id(e) == id);
    if (index >= 0) {
      final previous = items[index];
      if (previous['status'] == 'completed' &&
          values['status'] != 'completed') {
        return;
      }
      items[index] = values;
    } else {
      items.add(values);
    }
    await JsonCache.instance.write(_key, items);
  }

  /// Envoie les progressions en attente. Retourne le nombre envoyé.
  Future<int> flush(SupabaseClient client) async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      final snapshot = await _load();
      if (snapshot.isEmpty) return 0;

      final sent = <String>[];
      for (final item in snapshot) {
        try {
          final existing = await client
              .from('lesson_progress')
              .select('status')
              .eq('student_id', item['student_id'] as String)
              .eq('lesson_id', item['lesson_id'] as String)
              .maybeSingle()
              .timeout(JsonCache.networkTimeout);
          final alreadyDone = existing != null &&
              existing['status'] == 'completed' &&
              item['status'] != 'completed';
          if (!alreadyDone) {
            await client
                .from('lesson_progress')
                .upsert(item, onConflict: 'student_id,lesson_id')
                .timeout(JsonCache.networkTimeout);
          }
          sent.add(jsonEncode(item));
        } catch (_) {
          // Réseau coupé ou refus du serveur : on garde l'élément et on
          // réessaiera plus tard.
        }
      }

      // Recharge pour ne pas perdre ce qui a été ajouté pendant l'envoi.
      final current = await _load();
      final remaining =
          current.where((e) => !sent.contains(jsonEncode(e))).toList();
      await JsonCache.instance.write(_key, remaining);
      return sent.length;
    } finally {
      _flushing = false;
    }
  }

  Future<void> clear() => JsonCache.instance.remove(_key);
}
