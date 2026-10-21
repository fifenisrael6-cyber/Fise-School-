import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../settings/pages/profile_page.dart';
import 'teacher_courses_page.dart';

class TeacherMainPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Future<void> Function() onSignOut;
  const TeacherMainPage({super.key, required this.locale, required this.profile, required this.onSignOut});
  @override State<TeacherMainPage> createState() => _TeacherMainPageState();
}

class _TeacherMainPageState extends State<TeacherMainPage> {
  int _index = 0;
  @override Widget build(BuildContext context) {
    final fr = widget.locale.languageCode == 'fr';
    final pages = [
      _TeacherHome(locale: widget.locale, profile: widget.profile),
      TeacherCoursesPage(locale: widget.locale, profile: widget.profile),
      MessagesHubPage(locale: widget.locale, profile: widget.profile),
      ProfilePage(locale: widget.locale, profile: widget.profile),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: fr ? 'Accueil' : 'Home'),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: fr ? 'Cours' : 'Courses'),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: fr ? 'Messages' : 'Messages'),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: fr ? 'Profil' : 'Profile'),
        ],
      ),
    );
  }
}

class _TeacherHome extends StatelessWidget {
  final Locale locale; final UserProfile profile;
  const _TeacherHome({required this.locale, required this.profile});
  @override Widget build(BuildContext context) {
    final fr = locale.languageCode == 'fr';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fise School', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('${fr ? 'Bonjour' : 'Hello'}, ${profile.firstName}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(fr
              ? 'Accédez aux cours, aux messages et à votre profil depuis la navigation.'
              : 'Open courses, messages and your profile from the navigation bar.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.school_rounded, color: Color(0xFF166534)),
                    const SizedBox(width: 10),
                    Text(fr ? 'Mes salles' : 'My classrooms',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Text(fr
                      ? 'Les cours et médias de vos salles sont accessibles dans l’onglet Cours. Les conversations sont dans Messages.'
                      : 'Class courses and media are available under Courses. Conversations are under Messages.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

