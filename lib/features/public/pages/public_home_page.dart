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
                  _profiles(context, texts, isWide),
                  _features(texts, isWide),
                  _footer(texts),
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

    final actions = Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        Semantics(
          label: '${texts.login} dans ${texts.appName}',
          button: true,
          child: TextButton(
            onPressed: () => _openAuth(context),
            child: Text(texts.login),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _openAuth(
            context,
            register: true,
            role: 'teacher',
          ),
          icon: const Icon(Icons.co_present_rounded, size: 18),
          label: Text(
            locale.languageCode == 'fr'
                ? 'Continuer avec enseignant'
                : 'Continue as teacher',
          ),
        ),
        FilledButton.icon(
          onPressed: () => _openAuth(
            context,
            register: true,
            role: 'student',
          ),
          icon: const Icon(Icons.school_rounded, size: 18),
          label: Text(
            locale.languageCode == 'fr'
                ? 'Continuer avec élève'
                : 'Continue as student',
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
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: brand),
                ),
                actions,
                const SizedBox(width: 8),
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

  void _openAuth(
    BuildContext context, {
    bool register = false,
    String role = 'student',
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthPage(
          locale: locale,
          startInRegisterMode: register,
          initialRole: role,
        ),
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
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Semantics(
                label: '${texts.login} to ${texts.appName}',
                button: true,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF166534),
                    minimumSize: const Size(160, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _openAuth(context),
                  child: Text(texts.login),
                ),
              ),
              Semantics(
                label: locale.languageCode == 'fr'
                    ? 'Continuer avec enseignant'
                    : 'Continue as teacher',
                button: true,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F3D1F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(190, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _openAuth(
                    context,
                    register: true,
                    role: 'teacher',
                  ),
                  icon: const Icon(Icons.co_present_rounded, size: 19),
                  label: Text(
                    locale.languageCode == 'fr'
                        ? 'Continuer avec enseignant'
                        : 'Continue as teacher',
                  ),
                ),
              ),
              Semantics(
                label: locale.languageCode == 'fr'
                    ? 'Continuer avec élève'
                    : 'Continue as student',
                button: true,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF166534),
                    minimumSize: const Size(180, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _openAuth(
                    context,
                    register: true,
                    role: 'student',
                  ),
                  icon: const Icon(Icons.school_rounded, size: 19),
                  label: Text(
                    locale.languageCode == 'fr'
                        ? 'Continuer avec élève'
                        : 'Continue as student',
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

  Widget _profiles(BuildContext context, AppTexts texts, bool isWide) {
    final cards = [
      _profileCard(context, texts, true),
      _profileCard(context, texts, false),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            texts.chooseProfile,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w900,
              color: Color(0xFF123524),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isWide
                ? 'Choisissez votre parcours pour accéder à votre espace.'
                : 'Choisissez votre parcours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),
          const SizedBox(height: 24),
          isWide
              ? Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 18),
                    Expanded(child: cards[1]),
                  ],
                )
              : Column(
                  children: [cards[0], const SizedBox(height: 16), cards[1]],
                ),
        ],
      ),
    );
  }

  Widget _profileCard(BuildContext context, AppTexts texts, bool isStudent) {
    final title = isStudent ? texts.student : texts.teacher;
    final description = isStudent
        ? texts.studentDescription
        : texts.teacherDescription;
    final routeDescription = isStudent
        ? 'Accéder à l’espace étudiant'
        : 'Accéder à l’espace enseignant';

    return Semantics(
      button: true,
      label: routeDescription,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openAuth(
          context,
          register: true,
          role: isStudent ? 'student' : 'teacher',
        ),
        child: Ink(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDCEBE0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5EC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isStudent ? Icons.school_rounded : Icons.co_present_rounded,
                  color: const Color(0xFF166534),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF123524),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      description,
                      style: TextStyle(color: Colors.grey.shade600, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _openAuth(
                            context,
                            role: isStudent ? 'student' : 'teacher',
                          ),
                          child: Text(texts.login),
                        ),
                        FilledButton(
                          onPressed: () => _openAuth(
                            context,
                            register: true,
                            role: isStudent ? 'student' : 'teacher',
                          ),
                          child: Text(texts.register),
                        ),
                      ],
                    ),
                  ],
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

  Widget _footer(AppTexts texts) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    color: const Color(0xFFEAF5ED),
    child: Column(
      children: [
        _logo(45),
        const SizedBox(height: 10),
        Text(
          texts.appName,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF14532D),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          texts.cameroonSystem,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
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
