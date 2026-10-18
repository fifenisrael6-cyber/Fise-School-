import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../auth/pages/auth_page.dart';

class PublicHomePage extends StatelessWidget {
  final Locale locale;
  final ValueChanged<Locale> onLanguageChanged;

  const PublicHomePage({
    super.key,
    required this.locale,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(locale);
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            return SingleChildScrollView(
              child: Column(
                children: [
                  _topBar(context, texts),
                  _hero(context, texts, isWide),
                  _authButtons(context, texts),
                  _features(texts, isWide),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, AppTexts texts) {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _logo(narrow ? 40 : 48),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            texts.appName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: narrow ? 19 : 21,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF14532D),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: narrow
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: brand),
                    _languageMenu(texts),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: brand),
                ),
                _languageMenu(texts),
              ],
            ),
    );
  }

  Widget _languageMenu(AppTexts texts) => Tooltip(
        message: texts.language,
        child: PopupMenuButton<Locale>(
          tooltip: texts.language,
          onSelected: onLanguageChanged,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: const Locale('fr'),
              child: Text('🇫🇷  ${texts.french}'),
            ),
            PopupMenuItem(
              value: const Locale('en'),
              child: Text('🇬🇧  ${texts.english}'),
            ),
          ],
          child: Semantics(
            label: '${texts.language}: ${locale.languageCode == 'fr' ? texts.french : texts.english}',
            button: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFD1E7D7)),
                color: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(locale.languageCode == 'fr' ? '🇫🇷' : '🇬🇧'),
                  const SizedBox(width: 6),
                  Text(
                    locale.languageCode == 'fr' ? 'FR' : 'EN',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 18),
                ],
              ),
            ),
          ),
        ),
      );

  void _openAuth(BuildContext context, {bool register = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthPage(locale: locale, startInRegisterMode: register),
      ),
    );
  }

  Widget _hero(BuildContext context, AppTexts texts, bool isWide) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      padding: EdgeInsets.all(isWide ? 48 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF166534), Color(0xFF15803D), Color(0xFF22C55E)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 25,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: isWide
          ? Row(
              children: [
                Expanded(child: _heroText(context, texts)),
                const SizedBox(width: 40),
                _heroLogo(),
              ],
            )
          : Column(
              children: [
                _heroLogo(),
                const SizedBox(height: 28),
                _heroText(context, texts),
              ],
            ),
    );
  }

  Widget _heroText(BuildContext context, AppTexts texts) {
    final isFrench = locale.languageCode == 'fr';

    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              isFrench ? 'Espace scolaire' : 'School portal',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isFrench ? 'Apprendre mieux, partout.' : 'Learn better, anywhere.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isFrench
                ? 'Cours, devoirs, leçons et suivi de performance dans une application simple, rapide et accessible.'
                : 'Courses, assignments, lessons and progress tracking in one simple, fast and accessible app.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 17,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.download_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isFrench ? 'Disponible hors ligne après téléchargement' : 'Available offline after download',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroLogo() => Container(
    width: 136,
    height: 136,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8)),
      ],
    ),
    child: _logo(136),
  );

  Widget _authButtons(BuildContext context, AppTexts texts) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openAuth(context, register: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF166534),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(texts.register),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openAuth(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF166534),
                    side: const BorderSide(color: Color(0xFF166534)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(texts.login),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _features(AppTexts texts, bool isWide) {
    final features = [
      (Icons.menu_book_rounded, texts.courses),
      (Icons.assignment_rounded, texts.assignments),
      (Icons.download_rounded, 'Téléchargement local'),
      (Icons.forum_rounded, texts.forum),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 42, 16, 32),
      child: Column(
        children: [
          Text(
            texts.cameroonSystem,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14532D),
            ),
          ),
          const SizedBox(height: 20),
          isWide
              ? Row(
                  children: features
                      .map(
                        (item) => Expanded(child: _feature(item.$1, item.$2)),
                      )
                      .toList(),
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: features
                      .map(
                        (item) => SizedBox(
                          width: 160,
                          child: _feature(item.$1, item.$2),
                        ),
                      )
                      .toList(),
                ),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title) => Container(
    margin: const EdgeInsets.all(6),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE0ECE3)),
    ),
    child: Column(
      children: [
        Icon(icon, color: const Color(0xFF166534), size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF244331),
          ),
        ),
      ],
    ),
  );


  Widget _logo(double size) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      'assets/icon/fise_school.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => Icon(
        Icons.menu_book_rounded,
        color: const Color(0xFF166534),
        size: size * .8,
      ),
    ),
  );
}
