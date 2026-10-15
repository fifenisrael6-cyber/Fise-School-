import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/offline/offline_banner.dart';
import '../core/services/push_service.dart';
import '../core/services/session_service.dart';
import '../features/auth/widgets/auth_gate.dart';
import '../supabase_config.dart';
import 'routes.dart';
import 'theme.dart';

bool _supabaseInitialized = false;

Future<void> initializeFiseSchool() async {
  if (!SupabaseConfig.isConfigured) {
    debugPrint(
      'Supabase is not configured. Run with SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY.',
    );
    return;
  }

  if (!_supabaseInitialized) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      _supabaseInitialized = true;
    } catch (error) {
      debugPrint('Supabase initialization failed: $error');
    }
  }
}

class FiseSchoolApp extends StatefulWidget {
  final SessionService? sessionService;

  const FiseSchoolApp({super.key, this.sessionService});

  @override
  State<FiseSchoolApp> createState() => _FiseSchoolAppState();
}

class _FiseSchoolAppState extends State<FiseSchoolApp> {
  Locale _locale = const Locale('fr');
  late final SessionService _sessionService =
      widget.sessionService ??
      (_supabaseInitialized
          ? SupabaseSessionService()
          : const UnavailableSessionService());

  void _changeLanguage(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: fiseMessengerKey,
      title: 'Fise School',
      locale: _locale,
      // Bandeau « mode hors ligne » au-dessus de toute l'application.
      builder: (context, child) => OfflineAwareShell(
        languageCode: _locale.languageCode,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: FiseSchoolTheme.light(),
      routes: FiseSchoolRoutes.publicRoutes(
        locale: _locale,
        onLanguageChanged: _changeLanguage,
      ),
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => AuthGate(
          locale: _locale,
          onLanguageChanged: _changeLanguage,
          sessionService: _sessionService,
        ),
      ),
      home: AuthGate(
        locale: _locale,
        onLanguageChanged: _changeLanguage,
        sessionService: _sessionService,
      ),
    );
  }
}
