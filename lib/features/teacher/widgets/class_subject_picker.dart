import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';

/// Permet à l'enseignant de choisir une ou plusieurs salles de classe, puis une
/// matière commune à ces salles. Les matières viennent de `class_subjects`
/// (matières de base du programme camerounais de la salle). L'enseignant peut
/// aussi ajouter une matière supplémentaire à ses salles.
class ClassSubjectPicker extends StatefulWidget {
  final Locale locale;
  final String teacherId;
  final bool includeCompatibleClasses;
  final void Function(List<SchoolClass> classes, Subject? subject) onChanged;

  const ClassSubjectPicker({
    super.key,
    required this.locale,
    required this.teacherId,
    this.includeCompatibleClasses = false,
    required this.onChanged,
  });

  @override
  State<ClassSubjectPicker> createState() => _ClassSubjectPickerState();
}

class _ClassSubjectPickerState extends State<ClassSubjectPicker> {
  final CourseService _service = CourseService();

  late Future<List<SchoolClass>> _classesFuture;
  final Set<String> _selectedIds = <String>{};
  List<SchoolClass> _allClasses = const [];
  List<Subject> _subjects = const [];
  Subject? _subject;
  bool _loadingSubjects = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  String? _teacherVocation;

  @override
  void initState() {
    super.initState();
    _loadTeacherVocation();
    _loadFollowedClasses();
  }

  Future<void> _loadTeacherVocation() async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('teacher_vocation')
          .eq('id', widget.teacherId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        final value = row?['teacher_vocation']?.toString().toLowerCase();
        _teacherVocation = value == 'scientific' || value == 'literary'
            ? value
            : null;
      });
      if (_selectedIds.isNotEmpty) await _reloadSubjects();
    } catch (_) {
      // If older teacher profiles have no vocation, preserve existing behaviour.
    }
  }

  bool _matchesTeacherVocation(Subject subject) {
    final vocation = _teacherVocation;
    if (vocation == null) return true;
    final code = subject.code.toLowerCase().replaceAll('-', '_');
    final label = '${subject.nameFr} ${subject.nameEn}'.toLowerCase();

    const scientificCodes = <String>{
      'mathematiques', 'mathematics_en', 'additional_mathematics',
      'further_mathematics', 'technical_math', 'technical_math_en',
      'physique', 'physics_en', 'chimie', 'chemistry_en',
      'fr_tech_physique_chimie', 'pct', 'svt', 'biology_en',
      'human_biology', 'geology', 'sciences', 'general_science',
      'technical_science', 'technical_science_en', 'informatique',
      'computer_science_en', 'fr_tech_informatique', 'en_tech_ict',
      'technologie', 'technical_science', 'technical_math',
    };
    const literaryCodes = <String>{
      'francais', 'french_language', 'english_language', 'anglais',
      'en_tech_english', 'allemand', 'espagnol', 'italien', 'arabe',
      'chinois', 'latin', 'grec', 'seconde_langue', 'langues_nationales',
      'histoire', 'history_en', 'geographie', 'geography_en',
      'fr_tech_histoire_geo', 'philosophie', 'philosophy_en',
      'litterature', 'literature_in_english', 'logic', 'economics',
      'commerce', 'commerce_fr', 'accounting', 'comptabilite_fr',
      'education_civique', 'citizenship_en', 'fr_tech_ecm',
      'en_tech_citizenship', 'religious_studies',
    };

    if (vocation == 'literary') {
      if (scientificCodes.contains(code)) return false;
      if (label.contains('mathemat') || label.contains('mathématique') ||
          label.contains('physics') || label.contains('physique') ||
          label.contains('chemistry') || label.contains('chimie') ||
          label.contains('biology') || label.contains('biologie') ||
          label.contains('science') || label.contains('sciences') ||
          label.contains('computer science') || label.contains('informatique') ||
          label.contains('geology') || label.contains('géologie')) {
        return false;
      }
      return true;
    }

    if (literaryCodes.contains(code)) return false;
    if (label.contains('philosoph') || label.contains('history') ||
        label.contains('histoire') || label.contains('geography') ||
        label.contains('géographie') || label.contains('literature') ||
        label.contains('littérature') || label.contains('language') ||
        label.contains('langue') || label.contains('french') ||
        label.contains('français') || label.contains('english') ||
        label.contains('anglais') || label.contains('economics') ||
        label.contains('économie') || label.contains('commerce') ||
        label.contains('accounting') || label.contains('comptabilité')) {
      return false;
    }
    return true;
  }

  Future<void> _loadFollowedClasses() async {
    _classesFuture = _service.listTeacherSelectedClasses().then((list) {
      _allClasses = list;
      return list;
    });
    if (mounted) setState(() {});
  }

  Future<void> _chooseFollowedClasses() async {
    List<SchoolClass> all;
    Set<String> existing;
    try {
      all = await _service.listTeacherCompatibleClasses();
      existing = await _service.listTeacherFollowedClassIds();
    } catch (error) {
      _snack('${_fr ? 'Impossible de charger les salles' : 'Unable to load classrooms'}: $error');
      return;
    }
    if (!mounted) return;
    final selected = existing.isEmpty
        ? all.map((c) => c.id).toSet()
        : existing.intersection(all.map((c) => c.id).toSet());
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final draft = <String>{...selected};
        return StatefulBuilder(
          builder: (context, refreshDialog) => AlertDialog(
            title: Text(_fr ? 'Salles à suivre' : 'Classrooms to follow'),
            content: SizedBox(
              width: 480,
              height: MediaQuery.of(context).size.height * 0.55,
              child: all.isEmpty
                  ? Text(_fr ? 'Aucune salle compatible.' : 'No compatible classrooms.')
                  : ListView(
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_fr ? 'Tout sélectionner' : 'Select all'),
                          value: all.isNotEmpty && all.every((c) => draft.contains(c.id)),
                          onChanged: (value) => refreshDialog(() {
                            if (value == true) {
                              draft.addAll(all.map((c) => c.id));
                            } else {
                              draft.clear();
                            }
                          }),
                        ),
                        const Divider(),
                        ...all.map((schoolClass) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${all.indexOf(schoolClass) + 1}. ${schoolClass.displayName}'),
                          subtitle: Text(schoolClass.name),
                          value: draft.contains(schoolClass.id),
                          onChanged: (value) => refreshDialog(() {
                            if (value == true) {
                              draft.add(schoolClass.id);
                            } else {
                              draft.remove(schoolClass.id);
                            }
                          }),
                        )),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_fr ? 'Annuler' : 'Cancel'),
              ),
              FilledButton(
                onPressed: draft.isEmpty ? null : () => Navigator.pop(dialogContext, draft),
                child: Text(_fr ? 'Enregistrer' : 'Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    try {
      await _service.saveTeacherFollowedClasses(result.toList(growable: false));
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _subject = null;
        _subjects = const [];
      });
      await _loadFollowedClasses();
      _notify();
      _snack(_fr ? 'Salles suivies enregistrées.' : 'Followed classrooms saved.');
    } catch (error) {
      _snack('${_fr ? 'Enregistrement impossible' : 'Unable to save'}: $error');
    }
  }

  List<SchoolClass> get _selectedClasses => _allClasses
      .where((c) => _selectedIds.contains(c.id))
      .toList(growable: false);

  void _notify() => widget.onChanged(_selectedClasses, _subject);

  Future<void> _toggleClass(SchoolClass schoolClass, bool selected) async {
    setState(() {
      if (selected) {
        _selectedIds.add(schoolClass.id);
      } else {
        _selectedIds.remove(schoolClass.id);
      }
    });
    await _reloadSubjects();
  }

  Future<void> _reloadSubjects() async {
    final selected = _selectedClasses;

    if (selected.isEmpty) {
      setState(() {
        _subjects = const [];
        _subject = null;
      });
      _notify();
      return;
    }

    setState(() => _loadingSubjects = true);

    try {
      // Only the classrooms explicitly selected in the form determine
      // which subjects are offered. Expanding to every compatible series here
      // incorrectly intersected hundreds of curricula and often produced an
      // empty subject list. Cohort expansion belongs to publication, where
      // each destination is filtered independently by its own class_subjects.
      Map<String, Subject>? common;
      for (final schoolClass in selected) {
        final list = await _service.listSubjectsForClass(schoolClass.id);
        final byId = {for (final subject in list) subject.id: subject};
        if (common == null) {
          common = byId;
        } else {
          common = {
            for (final entry in common.entries)
              if (byId.containsKey(entry.key)) entry.key: entry.value,
          };
        }
      }

      if (!mounted) return;
      final subjects = (common ?? <String, Subject>{}).values
          .where(_matchesTeacherVocation)
          .toList()
        ..sort((a, b) => a.labelFor(_fr ? 'fr' : 'en')
            .toLowerCase()
            .compareTo(b.labelFor(_fr ? 'fr' : 'en').toLowerCase()));
      setState(() {
        _subjects = subjects;
        if (_subject != null && !subjects.any((s) => s.id == _subject!.id)) {
          _subject = null;
        }
      });
      _notify();
    } catch (error) {
      if (!mounted) return;
      _snack('${_fr ? 'Chargement impossible' : 'Unable to load'}: $error');
    } finally {
      if (mounted) setState(() => _loadingSubjects = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addSubject() async {
    final classes = _selectedClasses;
    if (classes.isEmpty) {
      _snack(_fr ? 'Choisissez d’abord une salle.' : 'Select a classroom first.');
      return;
    }

    final addable = <String, Subject>{};
    try {
      for (final schoolClass in classes) {
        for (final subject in await _service.listAddableSubjects(schoolClass.id)) {
          addable[subject.id] = subject;
        }
      }
    } catch (error) {
      _snack('$error');
      return;
    }

    if (!mounted) {
      return;
    }

    if (addable.isEmpty) {
      _snack(_fr
          ? 'Aucune autre matière disponible pour ces salles.'
          : 'No other subject is available for these classrooms.');
      return;
    }

    final options = addable.values.toList()
      ..sort((a, b) => a
          .labelFor(widget.locale.languageCode)
          .compareTo(b.labelFor(widget.locale.languageCode)));

    final picked = await showModalBottomSheet<Subject>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _fr ? 'Ajouter une matière' : 'Add a subject',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: options
                      .map(
                        (subject) => ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: Text(subject.labelFor(widget.locale.languageCode)),
                          onTap: () => Navigator.pop(sheetContext, subject),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null) {
      return;
    }

    var failures = 0;
    for (final schoolClass in classes) {
      try {
        await _service.addSubjectToClass(schoolClass.id, picked.id);
      } catch (_) {
        failures++;
      }
    }

    if (!mounted) {
      return;
    }

    if (failures > 0) {
      _snack(_fr
          ? 'Matière non ajoutée dans $failures salle(s).'
          : 'Subject not added in $failures classroom(s).');
    }

    await _reloadSubjects();
    if (!mounted) {
      return;
    }
    final match = _subjects.where((s) => s.id == picked.id);
    if (match.isNotEmpty) {
      setState(() => _subject = match.first);
      _notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _fr ? 'Salles disponibles pour vos activités' : 'Classrooms available for your activities',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _chooseFollowedClasses,
              icon: const Icon(Icons.tune_rounded),
              label: Text(_fr ? 'Salles suivies' : 'Followed rooms'),
            ),
          ],
        ),
        Text(
          _fr ? 'Choisir la ou les classes où publier' : 'Choose the class(es) to publish in',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<SchoolClass>>(
          future: _classesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return Text('${snapshot.error}');
            }
            final classes = snapshot.data ?? const <SchoolClass>[];
            if (classes.isEmpty) {
              return Text(_fr
                  ? 'Aucune salle compatible avec votre sous-système et votre secteur. Vérifiez votre profil auprès de l’administration.'
                  : 'No classroom matches your subsystem and sector. Check your profile with the administrator.');
            }
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: classes
                  .map(
                    (schoolClass) => FilterChip(
                      label: Text(schoolClass.displayName),
                      selected: _selectedIds.contains(schoolClass.id),
                      onSelected: (value) => _toggleClass(schoolClass, value),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _fr ? 'Matière' : 'Subject',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _addSubject,
              icon: const Icon(Icons.add_rounded),
              label: Text(_fr ? 'Ajouter une matière' : 'Add a subject'),
            ),
          ],
        ),
        if (_loadingSubjects)
          const LinearProgressIndicator()
        else if (_selectedIds.isEmpty)
          Text(_fr ? 'Sélectionnez d’abord au moins une salle.' : 'Select at least one classroom first.')
        else if (_subjects.isEmpty)
          Text(_fr
              ? 'Aucune matière commune à ces salles. Choisissez des salles du même sous-système ou ajoutez une matière.'
              : 'No common subject for these classrooms. Pick classrooms of the same subsystem or add a subject.')
        else
          DropdownButtonFormField<String>(
            key: ValueKey('${_subject?.id}-${_subjects.length}'),
            initialValue: _subject?.id,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _subjects
                .map(
                  (subject) => DropdownMenuItem<String>(
                    value: subject.id,
                    child: Text(subject.labelFor(widget.locale.languageCode)),
                  ),
                )
                .toList(),
            onChanged: (id) {
              setState(() {
                _subject = _subjects.firstWhere((s) => s.id == id);
              });
              _notify();
            },
          ),
      ],
    );
  }
}
