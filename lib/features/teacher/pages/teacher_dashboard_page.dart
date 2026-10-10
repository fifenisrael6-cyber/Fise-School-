import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../settings/pages/settings_page.dart';
import 'teacher_qcm_hub_page.dart';
import 'teacher_courses_page.dart';
import 'teacher_payment_code_page.dart';
import 'teacher_smart_progress_page.dart';
import 'qcm_builder_page.dart';

class TeacherDashboardPage extends StatelessWidget {
  final Locale locale;
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const TeacherDashboardPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(texts.teacherSpace),
        actions: [
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
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${texts.hello}, ${profile.firstName}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Chip(
                      label: Text(
                        '${texts.subsystem}: '
                        '${profile.subsystem ?? (locale.languageCode == 'fr' ? 'Non renseigné' : 'Not set')}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        '${texts.examLevel}: '
                        '${profile.examLevel ?? (locale.languageCode == 'fr' ? 'Non renseigné' : 'Not set')}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        '${texts.exam}: '
                        '${profile.exam ?? (locale.languageCode == 'fr' ? 'Non renseigné' : 'Not set')}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.7,
                  children: [
                    _Tile(
                      Icons.groups_rounded,
                      texts.taughtClasses,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _TeacherClassesPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.category_rounded,
                      texts.subjects,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _TeacherSubjectsPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.menu_book_rounded,
                      locale.languageCode == 'fr' ? 'Cours et contenus' : 'Courses and content',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherCoursesPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.assignment_rounded,
                      locale.languageCode == 'fr' ? 'QCM et exercices' : 'Quizzes and exercises',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherQcmHubPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.insights_rounded,
                      locale.languageCode == 'fr' ? 'Progression de la salle' : 'Class progress',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherSmartProgressPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.notifications_rounded,
                      texts.notifications,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NotificationsPage(
                            locale: locale,
                            userId: profile.id,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.history_edu_rounded,
                      locale.languageCode == 'fr' ? 'Annales des examens' : 'Exam papers',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QcmBuilderPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.mail_outline_rounded,
                      texts.messages,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MessagesHubPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.payments_rounded,
                      locale.languageCode == 'fr' ? 'Code paiement' : 'Payment code',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherPaymentCodePage(locale: locale, profile: profile),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsPage(locale: locale, profile: profile),
                    ),
                  ),
                  icon: const Icon(Icons.settings),
                  label: Text(texts.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _Tile(this.icon, this.title, [this.onTap]);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF166534), size: 28),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TeacherClassesPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const _TeacherClassesPage({required this.locale, required this.profile});

  @override
  State<_TeacherClassesPage> createState() => _TeacherClassesPageState();
}

class _TeacherClassesPageState extends State<_TeacherClassesPage> {
  final CourseService _service = CourseService();

  bool _loading = true;
  String? _error;
  List<SchoolClass> _classes = [];

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final classes = await _service.listTeacherClasses(widget.profile.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger vos classes.'
            : 'Unable to load your classes.';
      });
    }
  }

  Future<void> _manageFollowedClasses() async {
    List<SchoolClass> all;
    Set<String> existing;
    try {
      all = await _service.listTeacherCompatibleClasses();
      existing = await _service.listTeacherFollowedClassIds();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isFrench ? 'Impossible de charger les salles' : 'Unable to load classrooms'}: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final availableIds = all.map((c) => c.id).toSet();
    final draft = existing.isEmpty ? <String>{...availableIds} : existing.intersection(availableIds);
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: Text(_isFrench ? 'Salles à suivre' : 'Classrooms to follow'),
          content: SizedBox(
            width: 480,
            height: MediaQuery.of(context).size.height * 0.55,
            child: ListView(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_isFrench ? 'Tout sélectionner' : 'Select all'),
                  value: all.isNotEmpty && all.every((room) => draft.contains(room.id)),
                  onChanged: (value) => refreshDialog(() {
                    if (value == true) {
                      draft.addAll(availableIds);
                    } else {
                      draft.clear();
                    }
                  }),
                ),
                const Divider(),
                ...all.map((room) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(room.displayName),
                  subtitle: Text(room.name),
                  value: draft.contains(room.id),
                  onChanged: (value) => refreshDialog(() {
                    if (value == true) {
                      draft.add(room.id);
                    } else {
                      draft.remove(room.id);
                    }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: draft.isEmpty ? null : () => Navigator.pop(dialogContext, draft),
              child: Text(_isFrench ? 'Enregistrer' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await _service.saveTeacherFollowedClasses(selected.toList(growable: false));
      await _loadClasses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFrench ? 'Salles suivies enregistrées.' : 'Followed classrooms saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isFrench ? 'Enregistrement impossible' : 'Unable to save'}: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Mes classes' : 'My classes',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton.icon(
            onPressed: _manageFollowedClasses,
            icon: const Icon(Icons.tune_rounded),
            label: Text(_isFrench ? 'Salles suivies' : 'Followed rooms'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadClasses,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.error_outline_rounded, size: 56),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _loadClasses,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_isFrench ? 'Réessayer' : 'Try again'),
                    ),
                  ),
                ],
              )
            : _classes.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.groups_outlined,
                    size: 68,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isFrench ? 'Aucune classe affectée' : 'No assigned class',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _classes.length,
                itemBuilder: (context, index) {
                  final schoolClass = _classes[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Icon(
                          Icons.groups_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        schoolClass.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(schoolClass.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _TeacherSubjectsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const _TeacherSubjectsPage({required this.locale, required this.profile});

  @override
  State<_TeacherSubjectsPage> createState() => _TeacherSubjectsPageState();
}

class _TeacherSubjectsPageState extends State<_TeacherSubjectsPage> {
  final CourseService _service = CourseService();

  bool _loading = true;
  String? _error;
  List<Subject> _subjects = [];

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final subjects = await _service.listSubjects(widget.profile);

      if (!mounted) {
        return;
      }

      setState(() {
        _subjects = subjects;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger les matières.'
            : 'Unable to load subjects.';
      });
    }
  }

  String _subjectName(Subject subject) {
    if (_isFrench) {
      return subject.nameFr.trim().isNotEmpty ? subject.nameFr : subject.nameEn;
    }

    return subject.nameEn.trim().isNotEmpty ? subject.nameEn : subject.nameFr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Mes matières' : 'My subjects',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubjects,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.error_outline_rounded, size: 56),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _loadSubjects,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_isFrench ? 'Réessayer' : 'Try again'),
                    ),
                  ),
                ],
              )
            : _subjects.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    Icons.category_outlined,
                    size: 68,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _isFrench
                        ? 'Aucune matière disponible'
                        : 'No subjects available',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _subjects.length,
                itemBuilder: (context, index) {
                  final subject = _subjects[index];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Icon(
                          Icons.category_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        _subjectName(subject),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
