import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import '../../settings/pages/profile_page.dart';
import '../../settings/pages/settings_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import 'teacher_courses_page.dart';
import 'teacher_smart_progress_page.dart';
import 'grades_entry_page.dart';
import 'teacher_past_papers_page.dart';
import 'teacher_access_code_page.dart';

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
      ),
      TeacherCoursesPage(locale: widget.locale, profile: widget.profile),
      MessagesHubPage(locale: widget.locale, profile: widget.profile),
      TeacherSmartProgressPage(locale: widget.locale, profile: widget.profile),
      TeacherPastPapersPage(locale: widget.locale, profile: widget.profile),
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
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: fr ? 'Progression' : 'Progress',
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
  const _TeacherHome({
    required this.locale,
    required this.profile,
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
            icon: Icons.quiz_outlined,
            title: 'QCM',
            subtitle: fr
                ? 'Les QCM sont générés automatiquement à partir des cours publiés. Vous n’avez pas à les créer manuellement.'
                : 'Quizzes are generated automatically from published courses. You do not need to create them manually.',
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('QCM'),
                content: Text(fr
                    ? 'Les élèves génèrent leurs QCM depuis les cours accessibles dans leur classe. Publiez vos cours et ressources dans l’onglet Cours.'
                    : 'Students generate quizzes from courses available to their classroom. Publish your lessons and resources in the Courses tab.'),
                actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(fr ? 'Compris' : 'Got it'))],
              ),
            ),
          ),
          _TeacherAction(
            icon: Icons.vpn_key_rounded,
            title: fr ? 'Code FISE' : 'FISE access code',
            subtitle: fr
                ? 'Créer et partager le même code pour les groupes et la messagerie privée.'
                : 'Create and share the same code for groups and private messages.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeacherAccessCodePage(
                  locale: locale,
                  profile: profile,
                ),
              ),
            ),
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
