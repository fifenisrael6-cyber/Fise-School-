import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';
import '../../notifications/pages/notifications_page.dart';
import '../../messages/pages/messages_hub_page.dart';
import '../../settings/pages/settings_page.dart';
import 'create_assignment_page.dart';
import 'teacher_courses_page.dart';
import 'publish_directed_study_page.dart';
import 'teacher_payment_code_page.dart';
import 'teacher_smart_progress_page.dart';

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
                        Text(texts.welcomeBack),
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
                          builder: (_) => CreateAssignmentPage(
                            locale: locale,
                            profile: profile,
                          ),
                        ),
                      ),
                    ),
                    _Tile(
                      Icons.picture_as_pdf_rounded,
                      locale.languageCode == 'fr' ? 'Travaux dirigés' : 'Directed studies',
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublishDirectedStudyPage(
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
  bool _saving = false;
  String? _error;
  List<SchoolClass> _classes = [];
  final Set<String> _selectedIds = <String>{};

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
      // This screen manages the rooms available in teacher forms and to students.
      final classes = await _service.listTeacherCompatibleClasses();
      final selectedIds = await _service.listTeacherFollowedClassIds();

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _selectedIds
          ..clear()
          ..addAll(selectedIds.where((id) => classes.any((room) => room.id == id)));
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

  Future<void> _saveSelection() async {
    if (widget.profile.role != 'teacher') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Seuls les comptes enseignants peuvent enregistrer les salles.'
            : 'Only teacher accounts can save classroom selections.')),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Choisissez au moins une salle.'
            : 'Select at least one classroom.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveTeacherFollowedClasses(_selectedIds.toList(growable: false));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFrench
            ? 'Salles enregistrées. Seules ces salles seront proposées aux élèves et dans vos formulaires.'
            : 'Classrooms saved. Only these rooms will be offered to students and in your forms.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isFrench ? 'Enregistrement impossible' : 'Could not save'}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                itemCount: _classes.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _isFrench
                              ? 'Cochez les salles que vous enseignez, puis enregistrez. Seules les salles choisies seront proposées aux élèves pour changer de classe et dans vos formulaires de publication.'
                              : 'Select the classrooms you teach, then save. Only selected rooms will be offered to students when changing class and in your publishing forms.',
                        ),
                      ),
                    );
                  }
                  if (index == _classes.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveSelection,
                        icon: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_saving
                            ? (_isFrench ? 'Enregistrement…' : 'Saving…')
                            : (_isFrench ? 'Enregistrer les salles choisies' : 'Save selected classrooms')),
                      ),
                    );
                  }
                  final schoolClass = _classes[index - 1];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _selectedIds.contains(schoolClass.id),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selectedIds.add(schoolClass.id);
                        } else {
                          _selectedIds.remove(schoolClass.id);
                        }
                      }),
                      secondary: CircleAvatar(
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
                      controlAffinity: ListTileControlAffinity.trailing,
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
