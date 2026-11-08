import 'package:flutter/material.dart';

import 'admin_assignments_page.dart';
import 'admin_courses_page.dart';
import 'admin_chapter_content_page.dart';
import 'admin_directed_studies_page.dart';
import 'admin_grades_page.dart';
import 'admin_ai_courses_page.dart';
import 'admin_past_papers_page.dart';
import 'admin_evaluation_schedule_page.dart';
import 'admin_pedagogy_page.dart';
import 'admin_people_page.dart';
import 'admin_promotion_page.dart';
import 'admin_school_page.dart';
import 'admin_timetable_page.dart';
import 'school_classes_page.dart';

class AdminDashboardPage extends StatelessWidget {
  final Locale locale;
  final Future<void> Function() onSignOut;
  const AdminDashboardPage({super.key, required this.locale, required this.onSignOut});
  bool get _isFrench => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    final entries = <_AdminEntry>[
      _AdminEntry(Icons.school_rounded, _isFrench ? 'Gestion de l’école' : 'School management', (_) => AdminSchoolPage(locale: locale)),
      _AdminEntry(Icons.meeting_room_rounded, _isFrench ? 'Salles de classe' : 'Classrooms', (_) => SchoolClassesPage(locale: locale)),
      _AdminEntry(Icons.groups_rounded, _isFrench ? 'Élèves' : 'Students', (_) => AdminPeoplePage(locale: locale, role: 'student')),
      _AdminEntry(Icons.person_pin_rounded, _isFrench ? 'Enseignants' : 'Teachers', (_) => AdminPeoplePage(locale: locale, role: 'teacher')),
      _AdminEntry(Icons.trending_up_rounded, _isFrench ? 'Passage de classe' : 'Promotions', (_) => AdminPromotionPage(locale: locale)),
      _AdminEntry(Icons.menu_book_rounded, _isFrench ? 'Pédagogie' : 'Pedagogy', (_) => AdminPedagogyPage(locale: locale)),
      _AdminEntry(Icons.account_tree_rounded, _isFrench ? 'Chapitres et contenus' : 'Chapters and content', (_) => AdminChapterContentPage(locale: locale)),
      _AdminEntry(Icons.library_books_rounded, _isFrench ? 'Cours' : 'Courses', (_) => AdminCoursesPage(locale: locale)),
      _AdminEntry(Icons.picture_as_pdf_rounded, _isFrench ? 'TD PDF' : 'TD PDFs', (_) => AdminDirectedStudiesPage(locale: locale)),
      _AdminEntry(Icons.auto_awesome_rounded, _isFrench ? 'IA pédagogique — créer les cours' : 'Teaching AI — create courses', (_) => AdminAiCoursesPage(locale: locale)),
      _AdminEntry(Icons.assignment_rounded, _isFrench ? 'Devoirs' : 'Assignments', (_) => AdminAssignmentsPage(locale: locale)),
      _AdminEntry(Icons.event_available_rounded, _isFrench ? 'Calendrier des évaluations officielles' : 'Official exam schedule', (_) => AdminEvaluationSchedulePage(locale: locale)),
      _AdminEntry(Icons.calendar_month_rounded, _isFrench ? 'Emploi du temps' : 'Timetable', (_) => AdminTimetablePage(locale: locale)),
      _AdminEntry(Icons.grading_rounded, _isFrench ? 'Notes et bulletins' : 'Marks and report cards', (_) => AdminGradesPage(locale: locale)),
      _AdminEntry(Icons.history_edu_rounded, _isFrench ? 'Annales d’examens' : 'Past exam papers', (_) => AdminPastPapersPage(locale: locale)),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_isFrench ? 'Espace administrateur' : 'Administrator space', style: const TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(tooltip: _isFrench ? 'Déconnexion' : 'Sign out', onPressed: onSignOut, icon: const Icon(Icons.logout_rounded))]),
      body: SafeArea(child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: entries.length, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (context, index) {
        final entry = entries[index];
        return Card(margin: EdgeInsets.zero, child: ListTile(leading: Icon(entry.icon), title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.push(context, MaterialPageRoute(builder: entry.builder))));
      })),
    );
  }
}

class _AdminEntry {
  final IconData icon;
  final String title;
  final WidgetBuilder builder;
  const _AdminEntry(this.icon, this.title, this.builder);
}
