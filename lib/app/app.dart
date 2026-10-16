import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/offline/offline_banner.dart';
import '../core/services/push_service.dart';
import '../core/services/session_service.dart';
import '../features/auth/widgets/auth_gate.dart';
import '../features/auth/pages/reset_password_page.dart';
import '../features/public/pages/language_selection_page.dart';
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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<dynamic>? _authStateSubscription;
  Locale _locale = const Locale('fr');
  bool _languageChosen = false;
  bool _languageReady = false;
  SessionService get _sessionService =>
      widget.sessionService ??
      (_supabaseInitialized
          ? SupabaseSessionService()
          : const UnavailableSessionService());

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSavedLanguage());
    if (widget.sessionService == null) {
      unawaited(_initializeServicesInBackground());
    }
  }

  Future<void> _initializeServicesInBackground() async {
    // Afficher l'interface même si le réseau/Supabase est lent ou absent.
    try {
      await initializeFiseSchool();
    } catch (error) {
      debugPrint('Background Supabase initialization failed: $error');
    }
    if (!mounted) return;
    setState(() {});
    if (!_supabaseInitialized) return;
    _authStateSubscription ??= Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _navigatorKey.currentState?.pushNamed(FiseSchoolRoutes.resetPassword);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Password recovery link handling failed: $error');
      },
    );
    try {
      await PushService.initialize().timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('Push initialization skipped: $error');
    }
  }

  Future<void> _restoreSavedLanguage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('fise_school_language');
      if (saved == 'fr' || saved == 'en') {
        _locale = Locale(saved!);
        _languageChosen = true;
      }
    } catch (error) {
      debugPrint('Saved language could not be restored: $error');
    } finally {
      if (mounted) setState(() => _languageReady = true);
    }
  }

  Future<void> _selectInitialLanguage(Locale locale) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('fise_school_language', locale.languageCode);
    } catch (error) {
      debugPrint('Selected language could not be saved: $error');
    }
    if (!mounted) return;
    setState(() {
      _locale = locale;
      _languageChosen = true;
      _languageReady = true;
    });
  }

  Future<void> _saveLanguage(Locale locale) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('fise_school_language', locale.languageCode);
    } catch (error) {
      debugPrint('Changed language could not be saved: $error');
    }
  }

  void _changeLanguage(Locale locale) {
    setState(() => _locale = locale);
    unawaited(_saveLanguage(locale));
  }

  @override
  void dispose() {
    unawaited(_authStateSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
      home: !_languageReady
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_languageChosen
              ? LanguageSelectionPage(onLanguageSelected: _selectInitialLanguage)
              : AuthGate(
        key: ValueKey<String>(
          widget.sessionService != null
              ? 'injected-session'
              : (_supabaseInitialized ? 'supabase-ready' : 'supabase-pending'),
        ),
        locale: _locale,
        onLanguageChanged: _changeLanguage,
        sessionService: _sessionService,
      ),
    );
  }
}
