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
  final bool showAllCompatibleClasses;
  final void Function(List<SchoolClass> classes, Subject? subject) onChanged;

  const ClassSubjectPicker({
    super.key,
    required this.locale,
    required this.teacherId,
    this.showAllCompatibleClasses = false,
    required this.onChanged,
  });

  @override
  State<ClassSubjectPicker> createState() => _ClassSubjectPickerState();
}

class _ClassSubjectPickerState extends State<ClassSubjectPicker> {
  final CourseService _service = CourseService();

  late Future<List<SchoolClass>> _classesFuture;
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _classSearch = TextEditingController();
  final TextEditingController _subjectSearch = TextEditingController();
  List<SchoolClass> _allClasses = const [];
  List<Subject> _subjects = const [];
  Subject? _subject;
  bool _loadingSubjects = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _classSearch.dispose();
    _subjectSearch.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _classesFuture = _loadCompatibleClasses().then((list) {
      final available = list.where((schoolClass) => !_isCombinedLanguageRoom(schoolClass.displayName)).toList(growable: false);
      _allClasses = available;
      return available;
    });
  }

  Future<List<SchoolClass>> _loadCompatibleClasses() async {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('subsystem, sector, teaching_stream')
        .eq('id', widget.teacherId)
        .maybeSingle();
    final subsystem = profile?['subsystem']?.toString();
    final sector = profile?['sector']?.toString();
    final stream = profile?['teaching_stream']?.toString();
    final all = await _service.listTeacherCompatibleClasses();
    return all.where((room) =>
      (subsystem != null && subsystem.isNotEmpty && room.subsystem.name == subsystem) &&
      (sector != null && sector.isNotEmpty && room.sector.name == sector)
    ).toList(growable: false);
  }

  bool _isCombinedLanguageRoom(String label) {
    const languageNames = <String>[
      'anglais', 'english', 'allemand', 'german',
      'espagnol', 'espaniol', 'espanol', 'spanish',
      'italien', 'italian', 'arabe', 'arabic',
      'chinois', 'chinese', 'portugais', 'portuguese',
      'russe', 'russian', 'latin',
    ];
    return languageNames.where(label.toLowerCase().contains).length >= 2;
  }

  List<SchoolClass> get _selectedClasses => _allClasses
      .where((c) => _selectedIds.contains(c.id))
      .toList(growable: false);

  void _notify() => widget.onChanged(_selectedClasses, _subject);

  Future<void> _toggleClass(SchoolClass schoolClass, bool selected) async {
    setState(() {
      // Publish to one classroom at a time so its programme/chapter mapping is
      // unambiguous. Teachers can repeat the operation for another classroom.
      _selectedIds.clear();
      if (selected) _selectedIds.add(schoolClass.id);
    });
    await _reloadSubjects();
  }

  Future<void> _reloadSubjects() async {
    final classes = _selectedClasses;

    if (classes.isEmpty) {
      setState(() {
        _subjects = const [];
        _subject = null;
      });
      _notify();
      return;
    }

    setState(() => _loadingSubjects = true);

    try {
      Map<String, Subject>? common;
      for (final schoolClass in classes) {
        final list = await _service.listSubjectsForClass(schoolClass.id);
        final byId = {for (final s in list) s.id: s};
        if (common == null) {
          common = byId;
        } else {
          common = {
            for (final entry in common.entries)
              if (byId.containsKey(entry.key)) entry.key: entry.value,
          };
        }
      }

      if (!mounted) {
        return;
      }

      final selectedClass = classes.first;
      final subjects = (common ?? <String, Subject>{}).values
          .where((subject) => subject.subsystem == selectedClass.subsystem && subject.sector == selectedClass.sector && (stream == null || stream.isEmpty || stream == 'general' || subject.teachingStream == stream || subject.teachingStream == 'general'))
          .toList();
      setState(() {
        _subjects = subjects;
        if (_subject != null && !subjects.any((s) => s.id == _subject!.id)) {
          _subject = null;
        }
      });
      _notify();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _snack('${_fr ? 'Chargement impossible' : 'Unable to load'}: $error');
    } finally {
      if (mounted) {
        setState(() => _loadingSubjects = false);
      }
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
    final subjectQuery = _subjectSearch.text.trim().toLowerCase();
    final visibleSubjects = _subjects.where((subject) => subject.labelFor(widget.locale.languageCode).toLowerCase().contains(subjectQuery)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fr ? 'Choisir la salle où publier' : 'Choose the classroom to publish in',
          style: const TextStyle(fontWeight: FontWeight.w800),
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
                  ? 'Aucune salle ne vous est affectée. Contactez l’administration.'
                  : 'No classroom is assigned to you. Contact the administration.');
            }
            final query = _classSearch.text.trim().toLowerCase();
            final visibleClasses = classes
                .where((schoolClass) => schoolClass.displayName.toLowerCase().contains(query))
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _classSearch,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: _fr ? 'Rechercher une salle…' : 'Search classrooms…',
                    suffixIcon: _classSearch.text.isEmpty ? null : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_classSearch.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                if (visibleClasses.isEmpty)
                  Text(_fr ? 'Aucune salle trouvée.' : 'No classroom found.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: visibleClasses.map((schoolClass) => FilterChip(
                      label: Text(schoolClass.displayName),
                      selected: _selectedIds.contains(schoolClass.id),
                      onSelected: (value) => _toggleClass(schoolClass, value),
                    )).toList(),
                  ),
              ],
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
              ? 'Aucune matière n’est affectée à cette salle. Ajoutez une matière ou contactez l’administration.'
              : 'No subject is assigned to this classroom. Add a subject or contact the administration.')
        else ...[
          TextField(
            controller: _subjectSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _fr ? 'Rechercher une matière…' : 'Search subjects…',
              suffixIcon: _subjectSearch.text.isEmpty ? null : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(_subjectSearch.clear),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (visibleSubjects.isEmpty)
            Text(_fr ? 'Aucune matière trouvée.' : 'No subject found.')
          else
            DropdownButtonFormField<String>(
              key: ValueKey('${_subject?.id}-${_subjects.length}-${visibleSubjects.length}'),
              initialValue: visibleSubjects.any((s) => s.id == _subject?.id) ? _subject?.id : null,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: visibleSubjects.map((subject) => DropdownMenuItem<String>(
                value: subject.id,
                child: Text(subject.labelFor(widget.locale.languageCode)),
              )).toList(growable: false),
              onChanged: (id) {
                if (id == null) return;
                setState(() => _subject = _subjects.firstWhere((s) => s.id == id));
                _notify();
              },
            ),
        ],
      ],
    );
  }
}
