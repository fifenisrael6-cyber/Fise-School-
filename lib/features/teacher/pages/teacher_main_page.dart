import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import '../../settings/pages/profile_page.dart';
import '../../settings/pages/settings_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import 'teacher_courses_page.dart';
import 'qcm_builder_page.dart';
import 'teacher_timetable_page.dart';
import 'grades_entry_page.dart';

class TeacherMainPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const TeacherMainPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.onSignOut,
  });

  @override
  State<TeacherMainPage> createState() => _TeacherMainPageState();
}

class _TeacherMainPageState extends State<TeacherMainPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final fr = widget.locale.languageCode == 'fr';
    final pages = [
      _TeacherHome(
        locale: widget.locale,
        profile: widget.profile,
        onCourses: () => setState(() => _index = 1),
        onMessages: () => setState(() => _index = 2),
        onAnnales: () => setState(() => _index = 3),
      ),
      TeacherCoursesPage(locale: widget.locale, profile: widget.profile),
      MessagesHubPage(locale: widget.locale, profile: widget.profile),
      QcmBuilderPage(locale: widget.locale, profile: widget.profile, examMode: true),
      ProfilePage(locale: widget.locale, profile: widget.profile),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: fr ? 'Accueil' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: fr ? 'Cours' : 'Courses',
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: fr ? 'Messagerie' : 'Messages',
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_edu_outlined),
            selectedIcon: const Icon(Icons.history_edu),
            label: fr ? 'Annales' : 'Exam papers',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: fr ? 'Profil' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _TeacherHome extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;
  final VoidCallback onCourses;
  final VoidCallback onMessages;
  final VoidCallback onAnnales;

  const _TeacherHome({
    required this.locale,
    required this.profile,
    required this.onCourses,
    required this.onMessages,
    required this.onAnnales,
  });

  @override
  Widget build(BuildContext context) {
    final fr = locale.languageCode == 'fr';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fise School',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: fr ? 'Paramètres' : 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(locale: locale, profile: profile),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '${fr ? 'Bonjour' : 'Hello'}, ${profile.firstName}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _TeacherAction(
            icon: Icons.menu_book_rounded,
            title: fr ? 'Cours et contenus' : 'Courses and content',
            subtitle: fr
                ? 'Publier des cours et des documents dans vos salles.'
                : 'Publish lessons and documents to your classrooms.',
            onTap: onCourses,
          ),
          _TeacherAction(
            icon: Icons.history_edu_rounded,
            title: fr ? 'Annales des examens' : 'Exam papers',
            subtitle: fr
                ? 'Créer une évaluation et la diffuser aux salles et séries autorisées.'
                : 'Create an assessment and publish it to assigned classes and streams.',
            onTap: onAnnales,
          ),
          _TeacherAction(
            icon: Icons.grading_rounded,
            title: fr ? 'Notes' : 'Marks',
            subtitle: fr
                ? 'Saisir les notes de vos élèves par matière et période.'
                : 'Enter students’ marks by subject and period.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GradesEntryPage(locale: locale, profile: profile),
              ),
            ),
          ),
          _TeacherAction(
            icon: Icons.calendar_month_rounded,
            title: fr ? 'Emploi du temps' : 'Timetable',
            subtitle: fr
                ? 'Consulter vos créneaux de cours.'
                : 'View your teaching schedule.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeacherTimetablePage(locale: locale, profile: profile),
              ),
            ),
          ),
          _TeacherAction(
            icon: Icons.chat_bubble_outline_rounded,
            title: fr ? 'Messagerie' : 'Messages',
            subtitle: fr
                ? 'Échanger avec les élèves autorisés de vos salles.'
                : 'Chat with authorized students in your classrooms.',
            onTap: onMessages,
          ),
        ],
      ),
    );
  }
}

class _TeacherAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TeacherAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFDCFCE7),
            child: Icon(icon, color: const Color(0xFF166534)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}
