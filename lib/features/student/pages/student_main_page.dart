import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../models/user_profile.dart';
import '../../ai/pages/ai_page.dart';
import '../../settings/pages/profile_page.dart';
import '../../settings/pages/settings_page.dart';
import '../pages/courses_page.dart';
import '../pages/assignments_page.dart';
import '../pages/progress_page.dart';
import '../pages/timetable_page.dart';
import '../pages/past_papers_page.dart';
import '../pages/bulletin_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../notifications/pages/notifications_page.dart';

class StudentMainPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const StudentMainPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.onSignOut,
  });

  @override
  State<StudentMainPage> createState() => _StudentMainPageState();
}

class _StudentMainPageState extends State<StudentMainPage> {
  int _index = 0;

  List<Widget> get _pages => [
        _StudentHome(
          locale: widget.locale,
          profile: widget.profile,
          onOpenTab: (index) => setState(() => _index = index),
          onSignOut: widget.onSignOut,
        ),
        CoursesPage(locale: widget.locale, profile: widget.profile),
        MessagesHubPage(locale: widget.locale, profile: widget.profile),
        AiPage(locale: widget.locale, profile: widget.profile),
        ProfilePage(locale: widget.locale, profile: widget.profile),
      ];

  @override
  Widget build(BuildContext context) {
    final fr = widget.locale.languageCode == 'fr';
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: fr ? 'Accueil' : 'Home'),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: fr ? 'Cours' : 'Courses'),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline), selectedIcon: const Icon(Icons.chat_bubble), label: fr ? 'Messagerie' : 'Messages'),
          NavigationDestination(icon: const Icon(Icons.auto_awesome_outlined), selectedIcon: const Icon(Icons.auto_awesome), label: 'IA'),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: fr ? 'Profil' : 'Profile'),
        ],
      ),
    );
  }
}

class _StudentHome extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;
  final ValueChanged<int> onOpenTab;
  final Future<void> Function() onSignOut;

  const _StudentHome({required this.locale, required this.profile, required this.onOpenTab, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final fr = locale.languageCode == 'fr';
    final texts = AppTexts(locale);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fise School', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage(locale: locale, profile: profile)))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('${texts.hello}, ${profile.firstName}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(fr ? 'Tout ton apprentissage au même endroit.' : 'Everything you need to learn in one place.'),
          const SizedBox(height: 16),
          _RoomCard(profile: profile, locale: locale),
          const SizedBox(height: 14),
          _QuickCard(
            icon: Icons.insights_outlined,
            title: fr ? 'Progression' : 'Progress',
            subtitle: fr ? 'Consulte ta progression scolaire.' : 'View your learning progress.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgressPage(locale: locale, profile: profile))),
          ),
          _QuickCard(
            icon: Icons.history_edu_rounded,
            title: fr ? 'Annales d\'examens' : 'Past exam papers',
            subtitle: fr ? 'Sujets et corrigés des années précédentes.' : 'Papers and corrected exams from previous years.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastPapersPage(locale: locale))),
          ),
          _QuickCard(
            icon: Icons.grading_rounded,
            title: fr ? 'Notes et bulletin' : 'Marks and report card',
            subtitle: fr ? 'Consulte tes notes, ton rang et exporte ton bulletin en PDF.' : 'See your marks, rank and export your report card.',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BulletinPage(locale: locale, studentId: profile.id, studentName: profile.firstName))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SmallAction(icon: Icons.notifications_outlined, label: fr ? 'Notifications' : 'Notifications', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(locale: locale, userId: profile.id))))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _SmallAction(icon: Icons.assignment_outlined, label: fr ? 'QCM' : 'Quizzes', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentsPage(locale: locale, profile: profile))))),
            const SizedBox(width: 10),
            Expanded(child: _SmallAction(icon: Icons.calendar_month_outlined, label: fr ? 'Emploi du temps' : 'Schedule', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimetablePage(locale: locale, profile: profile))))),
          ]),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final UserProfile profile;
  final Locale locale;
  const _RoomCard({required this.profile, required this.locale});

  @override
  Widget build(BuildContext context) {
    final fr = locale.languageCode == 'fr';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.school_rounded, color: Color(0xFF166534)), const SizedBox(width: 10), Text(fr ? 'Ma salle' : 'My classroom', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
          const SizedBox(height: 10),
          Text(
            profile.className?.trim().isNotEmpty == true
                ? profile.className!
                : (fr ? 'Salle non affectée.' : 'No classroom assigned yet.'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (profile.examLevel != null || profile.subsystem != null) ...[const SizedBox(height: 8), Text([profile.examLevel, profile.subsystem, profile.sector].whereType<String>().where((v) => v.trim().isNotEmpty).join(' • '))],
        ]),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: const Color(0xFF166534), size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    ),
  );
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFF166534), size: 24), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]),
      ),
    ),
  );
}
