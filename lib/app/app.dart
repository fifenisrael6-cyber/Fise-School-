import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/push_service.dart';
import '../core/services/session_service.dart';
import '../features/auth/widgets/auth_gate.dart';
import '../features/auth/pages/password_reset_page.dart';
import '../features/messages/pages/messages_hub_page.dart';
import '../features/notifications/pages/notifications_page.dart';
import '../models/user_profile.dart';
import '../supabase_config.dart';
import 'routes.dart';
import 'theme.dart';

bool _supabaseInitialized = false;
const _languagePreferenceKey = 'fise_school_language_code';
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
  StreamSubscription<AuthState>? _authStateSubscription;
  bool _pendingPasswordRecovery = false;
  bool _passwordResetPageOpen = false;
  Locale _locale = const Locale('fr');
  bool _languagePreferenceLoaded = false;
  bool _languageSelected = false;

  late final SessionService _sessionService =
      widget.sessionService ??
      (_supabaseInitialized
          ? SupabaseSessionService()
          : const UnavailableSessionService());

  @override
  void initState() {
    super.initState();
    PushService.setNotificationTapHandler(_openFromPushNotification);
    _loadSavedLanguage();
    if (_supabaseInitialized) {
      _authStateSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event != AuthChangeEvent.passwordRecovery) return;
        _pendingPasswordRecovery = true;
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openPasswordResetIfPending();
        });
      });
    }
  }

  void _openPasswordResetIfPending() {
    if (!_pendingPasswordRecovery || _passwordResetPageOpen) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _pendingPasswordRecovery = false;
    _passwordResetPageOpen = true;
    navigator
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => PasswordResetPage(locale: _locale),
          ),
        )
        .whenComplete(() {
          _passwordResetPageOpen = false;
        });
  }

  Future<void> _openFromPushNotification(Map<String, String> data) async {
    // Wait until login/profile loading has completed before navigating.
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await client.from('profiles').select().eq('id', user.id).single();
      final profile = UserProfile.fromMap(Map<String, dynamic>.from(row));
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      final type = (data['type'] ?? 'info').toLowerCase();
      if (type == 'message' || type == 'group_message' || type == 'private_message') {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MessagesHubPage(locale: _locale, profile: profile),
          ),
        );
      } else {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => NotificationsPage(
              locale: _locale,
              userId: profile.id,
              profile: profile,
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Ouverture de la notification impossible: $error');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage = preferences.getString(_languagePreferenceKey);
      if (!mounted) return;
      setState(() {
        if (savedLanguage == 'fr' || savedLanguage == 'en') {
          _locale = Locale(savedLanguage!);
          _languageSelected = true;
        }
        _languagePreferenceLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _languagePreferenceLoaded = true);
      }
    }
  }

  Future<void> _changeLanguage(Locale locale) async {
    setState(() {
      _locale = locale;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_languagePreferenceKey, locale.languageCode);
    } catch (error) {
      debugPrint('Could not save language preference: $error');
    }
  }

  Future<void> _confirmLanguage(Locale locale) async {
    await _changeLanguage(locale);
    if (!mounted) return;
    setState(() => _languageSelected = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingPasswordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPasswordResetIfPending();
      });
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      scaffoldMessengerKey: fiseMessengerKey,
      title: 'Fise School',
      locale: _locale,
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
      home: !_languagePreferenceLoaded
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : !_languageSelected
          ? LanguageSelectionPage(onContinue: _confirmLanguage)
          : AuthGate(
              locale: _locale,
              onLanguageChanged: _changeLanguage,
              sessionService: _sessionService,
            ),
    );
  }
}

class LanguageSelectionPage extends StatefulWidget {
  final ValueChanged<Locale> onContinue;

  const LanguageSelectionPage({super.key, required this.onContinue});

  @override
  State<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage> {
  Locale? _selectedLocale;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedLocale;
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.language_rounded,
                    size: 62,
                    color: Color(0xFF166534),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Fise School',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF14532D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choisissez votre langue / Choose your language',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 30),
                  _LanguageOption(
                    title: 'Français',
                    subtitle: 'Continuer en français',
                    flag: '🇫🇷',
                    selected: selected?.languageCode == 'fr',
                    onTap: () => setState(
                      () => _selectedLocale = const Locale('fr'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LanguageOption(
                    title: 'English',
                    subtitle: 'Continue in English',
                    flag: '🇬🇧',
                    selected: selected?.languageCode == 'en',
                    onTap: () => setState(
                      () => _selectedLocale = const Locale('en'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: selected == null
                        ? null
                        : () => widget.onContinue(selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF166534),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      selected?.languageCode == 'en'
                          ? 'Continue'
                          : 'Continuer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vous devez choisir une langue pour continuer. / Select a language to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.subtitle,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE3F5E8) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF166534)
                  : const Color(0xFFD1E7D7),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? const Color(0xFF166534)
                    : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
