import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../models/user_profile.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../search/pages/search_page.dart';
import '../../settings/pages/profile_page.dart';
import '../../settings/pages/settings_page.dart';
import 'assignments_page.dart';
import 'courses_page.dart';
import 'progress_page.dart';
import 'timetable_page.dart';

class StudentDashboardPage extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const StudentDashboardPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(locale);

    return _DashboardScaffold(
      title: texts.studentSpace,
      locale: locale,
      profile: profile,
      texts: texts,
      onSignOut: onSignOut,
      children: [
        _Welcome(profile: profile, texts: texts),
        const SizedBox(height: 18),
        _DashboardGrid(
          items: [
            _DashboardItem(
              Icons.menu_book_rounded,
              texts.courses,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CoursesPage(locale: locale, profile: profile),
                ),
              ),
            ),
            _DashboardItem(
              Icons.assignment_rounded,
              texts.assignments,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssignmentsPage(locale: locale, profile: profile),
                ),
              ),
            ),
            _DashboardItem(
              Icons.mail_outline_rounded,
              texts.messages,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MessagesHubPage(locale: locale, profile: profile),
                ),
              ),
            ),
            _DashboardItem(
              Icons.notifications_rounded,
              texts.notifications,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationsPage(locale: locale, userId: profile.id),
                ),
              ),
            ),
            _DashboardItem(
              Icons.insights_rounded,
              texts.progress,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProgressPage(locale: locale, profile: profile),
                ),
              ),
            ),
            _DashboardItem(
              Icons.calendar_month_rounded,
              texts.timetable,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TimetablePage(locale: locale, profile: profile),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _DashboardScaffold extends StatelessWidget {
  final String title;
  final Locale locale;
  final UserProfile profile;
  final AppTexts texts;
  final Future<void> Function() onSignOut;
  final List<Widget> children;

  const _DashboardScaffold({
    required this.title,
    required this.locale,
    required this.profile,
    required this.texts,
    required this.onSignOut,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: texts.notifications,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsPage(locale: locale, userId: profile.id),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: texts.search,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SearchPage(locale: locale)),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: texts.settings,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(locale: locale, profile: profile),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: texts.profile,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(locale: locale, profile: profile),
              ),
            ),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 1000,
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final UserProfile profile;
  final AppTexts texts;

  const _Welcome({required this.profile, required this.texts});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${texts.hello}, ${profile.firstName}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(texts.welcomeBack),
          ],
        ),
      ),
    );
  }
}

class _DashboardGrid extends StatelessWidget {
  final List<_DashboardItem> items;

  const _DashboardGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 130,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: item.onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: const Color(0xFF166534), size: 30),
                const SizedBox(height: 10),
                Text(item.title, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardItem {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _DashboardItem(this.icon, this.title, [this.onTap]);
}
