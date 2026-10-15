import 'package:flutter/material.dart';

/// Première page affichée à chaque lancement de Fise School.
/// L'utilisateur doit choisir la langue avant d'accéder à l'accueil.
class LanguageSelectionPage extends StatelessWidget {
  final ValueChanged<Locale> onLanguageSelected;

  const LanguageSelectionPage({
    super.key,
    required this.onLanguageSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/fise_school.png',
                    width: 112,
                    height: 112,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.menu_book_rounded,
                      size: 96,
                      color: Color(0xFF166534),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Fise School',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF14532D),
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choisissez votre langue / Choose your language',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF244331),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => onLanguageSelected(const Locale('fr')),
                      icon: const Text('🇫🇷'),
                      label: const Text(
                        'Français',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF166534),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => onLanguageSelected(const Locale('en')),
                      icon: const Text('🇬🇧'),
                      label: const Text(
                        'English',
                        style: TextStyle(fontSize: 18),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF166534),
                        side: const BorderSide(color: Color(0xFF166534)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
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
