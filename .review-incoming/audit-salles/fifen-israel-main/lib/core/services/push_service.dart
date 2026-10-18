import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Clé globale pour afficher un bandeau quand une notification arrive application ouverte.
final GlobalKey<ScaffoldMessengerState> fiseMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> fiseBackgroundMessageHandler(RemoteMessage message) async {
  // Le système affiche lui-même la notification quand l'application est fermée.
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

/// Notifications push (FCM). Sans google-services.json, tout reste inactif et
/// l'application continue de fonctionner normalement.
class PushService {
  PushService._();

  static bool _ready = false;
  static bool _listening = false;
  static String? _token;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(fiseBackgroundMessageHandler);
      _ready = true;
    } catch (e) {
      debugPrint('Firebase non configuré, notifications push désactivées : $e');
    }
  }

  static Future<void> registerForUser(String userId) async {
    if (!_ready) {
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null) {
        return;
      }
      _token = token;
      await _save(token);

      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((fresh) async {
          _token = fresh;
          await _save(fresh);
        });
        FirebaseMessaging.onMessage.listen(_showForegroundBanner);
      }
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  static Future<void> _save(String token) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      return;
    }
    await client.rpc(
      'register_device_token',
      params: {'p_token': token, 'p_platform': 'android'},
    );
  }

  /// À appeler AVANT la déconnexion : l'appareil ne doit plus recevoir les
  /// notifications de l'ancien compte.
  static Future<void> unregister() async {
    final token = _token;
    if (!_ready || token == null) {
      return;
    }
    try {
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('token', token);
    } catch (e) {
      debugPrint('Suppression du jeton push impossible : $e');
    }
  }

  static void _showForegroundBanner(RemoteMessage message) {
    final title = message.notification?.title ?? 'Fise School';
    final body = message.notification?.body ?? '';
    fiseMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title\n$body'),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
