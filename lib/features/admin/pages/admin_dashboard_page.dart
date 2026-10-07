import 'package:flutter/material.dart';

import '../../../models/user_profile.dart';
import 'admin_ai_page.dart';
import 'admin_assignments_page.dart';
import 'admin_courses_page.dart';
import 'admin_grades_page.dart';
import 'admin_past_papers_page.dart';
import 'admin_pedagogy_page.dart';
import 'admin_people_page.dart';
import 'admin_promotion_page.dart';
import 'admin_school_page.dart';
import 'admin_timetable_page.dart';
import 'school_classes_page.dart';

class AdminDashboardPage extends StatelessWidget {
  final Locale locale;
  final Future<void> Function() onSignOut;
  final UserProfile? profile;

  const AdminDashboardPage({
    super.key,
    required this.locale,
    required this.onSignOut,
    this.profile,
  });

  bool get _isFrench => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    final adminProfile = profile ?? _createDefaultAdminProfile();
    
    final entries = <_AdminEntry>[
      _AdminEntry(
        icon: Icons.auto_awesome_rounded,
        title: _isFrench ? 'Assistant IA Admin' : 'Admin AI Assistant',
        builder: (_) => AdminAiPage(locale: locale, profile: adminProfile),
      ),
      _AdminEntry(
        icon: Icons.school_rounded,
        title: _isFrench ? 'Gestion de l\'école' : 'School management',
        builder: (_) => AdminSchoolPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.meeting_room_rounded,
        title: _isFrench ? 'Salles de classe' : 'Classrooms',
        builder: (_) => SchoolClassesPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.groups_rounded,
        title: _isFrench ? 'Élèves' : 'Students',
        builder: (_) => AdminPeoplePage(locale: locale, role: 'student'),
      ),
      _AdminEntry(
        icon: Icons.person_pin_rounded,
        title: _isFrench ? 'Enseignants' : 'Teachers',
        builder: (_) => AdminPeoplePage(locale: locale, role: 'teacher'),
      ),
      _AdminEntry(
        icon: Icons.trending_up_rounded,
        title: _isFrench ? 'Passage de classe' : 'Promotions',
        builder: (_) => AdminPromotionPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.menu_book_rounded,
        title: _isFrench ? 'Pédagogie' : 'Pedagogy',
        builder: (_) => AdminPedagogyPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.library_books_rounded,
        title: _isFrench ? 'Cours' : 'Courses',
        builder: (_) => AdminCoursesPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.assignment_rounded,
        title: _isFrench ? 'Devoirs' : 'Assignments',
        builder: (_) => AdminAssignmentsPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.calendar_month_rounded,
        title: _isFrench ? 'Emploi du temps' : 'Timetable',
        builder: (_) => AdminTimetablePage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.grading_rounded,
        title: _isFrench ? 'Notes et bulletins' : 'Marks and report cards',
        builder: (_) => AdminGradesPage(locale: locale),
      ),
      _AdminEntry(
        icon: Icons.history_edu_rounded,
        title: _isFrench ? 'Annales d\'examens' : 'Past exam papers',
        builder: (_) => AdminPastPapersPage(locale: locale),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Espace administrateur' : 'Administrator space',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: _isFrench ? 'Déconnexion' : 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(entry.icon),
                title: Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: entry.builder),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  UserProfile _createDefaultAdminProfile() {
    return UserProfile(
      id: 'admin-ai-context',
      firstName: 'Admin',
      lastName: 'Fise School',
      role: 'admin',
      preferredLanguage: _isFrench ? 'fr' : 'en',
      subsystem: 'francophone',
      sector: 'general',
      className: 'Administration',
      examLevel: 'Administration',
      exam: 'Fise School',
    );
  }
}

class _AdminEntry {
  final IconData icon;
  final String title;
  final WidgetBuilder builder;

  const _AdminEntry({
    required this.icon,
    required this.title,
    required this.builder,
  });
}
