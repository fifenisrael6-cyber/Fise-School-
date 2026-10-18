import 'package:flutter/material.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/timetable_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/timetable_entry.dart';
import '../../../models/user_profile.dart';

/// Emploi du temps de l'élève : l'onglet « Ma salle » est fourni par l'école
/// (lecture seule), l'onglet « Mon planning » est construit par l'élève.
class TimetablePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TimetablePage({super.key, required this.locale, required this.profile});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final TimetableService _service = TimetableService();
  late Future<List<TimetableEntry>> _classFuture;
  late Future<List<TimetableEntry>> _personalFuture;
  List<ClassSubjectEntry> _subjects = const [];

  bool get fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
    _loadSubjects();
  }

  void _reload() {
    _classFuture = _service.listClassTimetableForStudent(widget.profile.id);
    _personalFuture = _service.listPersonal(widget.profile.id);
  }

  Future<void> _loadSubjects() async {
    try {
      final list = await CourseService().listClassSubjects(widget.profile);
      if (mounted) {
        setState(() => _subjects = list);
      }
    } catch (_) {
      // Le choix libre d'une matière reste possible.
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  String _dayName(int day) {
    const frNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    const enNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final names = fr ? frNames : enNames;
    return day >= 1 && day <= 7 ? names[day - 1] : '';
  }

  int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) {
      return 0;
    }
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  Future<void> _editSlot({TimetableEntry? entry, int? day}) async {
    String? subjectId = entry?.subjectId;
    final customController = TextEditingController(
      text: entry != null && entry.subjectId == null ? entry.subject : '',
    );
    final roomController = TextEditingController(text: entry?.room ?? '');
    final notesController = TextEditingController(text: entry?.notes ?? '');
    var dayOfWeek = entry?.dayOfWeek ?? day ?? 1;
    var start = entry != null ? _parse(entry.startTime) : const TimeOfDay(hour: 8, minute: 0);
    var end = entry != null ? _parse(entry.endTime) : const TimeOfDay(hour: 9, minute: 0);
    var useCustom = (entry != null && entry.subjectId == null) || _subjects.isEmpty;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  entry == null ? (fr ? 'Ajouter un créneau' : 'Add a slot') : (fr ? 'Modifier le créneau' : 'Edit the slot'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (!useCustom)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _subjects.any((e) => e.subject.id == subjectId) ? subjectId : null,
                    decoration: InputDecoration(
                      labelText: fr ? 'Matière' : 'Subject',
                      border: const OutlineInputBorder(),
                    ),
                    items: _subjects
                        .map((e) => DropdownMenuItem<String>(
                              value: e.subject.id,
                              child: Text(e.subject.labelFor(widget.locale.languageCode), overflow: TextOverflow.ellipsis),
                            ))
                        .toList(growable: false),
                    onChanged: (value) => setSheet(() => subjectId = value),
                  )
                else
                  TextField(
                    controller: customController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: fr ? 'Activité ou matière' : 'Activity or subject',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (_subjects.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setSheet(() {
                        useCustom = !useCustom;
                        if (useCustom) {
                          subjectId = null;
                        }
                      }),
                      child: Text(useCustom
                          ? (fr ? 'Choisir dans les matières de ma salle' : 'Pick from my classroom subjects')
                          : (fr ? 'Autre activité (révision, sport…)' : 'Other activity (revision, sport…)')),
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: dayOfWeek,
                  decoration: InputDecoration(
                    labelText: fr ? 'Jour' : 'Day',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(_dayName(d))),
                  ],
                  onChanged: (value) => setSheet(() => dayOfWeek = value ?? dayOfWeek),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text('${fr ? 'Début' : 'Start'} ${_fmt(start)}'),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: start);
                          if (picked != null) {
                            setSheet(() => start = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text('${fr ? 'Fin' : 'End'} ${_fmt(end)}'),
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: end);
                          if (picked != null) {
                            setSheet(() => end = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roomController,
                  decoration: InputDecoration(
                    labelText: fr ? 'Lieu (facultatif)' : 'Place (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: fr ? 'Note (facultatif)' : 'Note (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final hasSubject = useCustom ? customController.text.trim().isNotEmpty : subjectId != null;
                    if (!hasSubject) {
                      _snack(fr ? 'Choisissez une matière.' : 'Choose a subject.');
                      return;
                    }
                    if (_minutes(_fmt(end)) <= _minutes(_fmt(start))) {
                      _snack(fr ? 'L’heure de fin doit être après le début.' : 'The end time must be after the start.');
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  child: Text(fr ? 'Enregistrer' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final customName = customController.text.trim();
    final room = roomController.text;
    final notes = notesController.text;
    customController.dispose();
    roomController.dispose();
    notesController.dispose();
    if (saved != true) {
      return;
    }

    String subjectFr = customName;
    String? subjectEn;
    final String? chosenId = useCustom ? null : subjectId;
    if (chosenId != null) {
      final match = _subjects.where((e) => e.subject.id == chosenId).toList();
      if (match.isNotEmpty) {
        subjectFr = match.first.subject.nameFr;
        subjectEn = match.first.subject.nameEn;
      }
    }

    final startText = _fmt(start);
    final endText = _fmt(end);

    // Pas de chevauchement avec un autre créneau du même jour.
    final current = await _personalFuture.catchError((_) => const <TimetableEntry>[]);
    final overlap = current.any((other) =>
        other.id != entry?.id &&
        other.dayOfWeek == dayOfWeek &&
        _minutes(startText) < _minutes(other.endTime) &&
        _minutes(endText) > _minutes(other.startTime));
    if (overlap) {
      _snack(fr ? 'Ce créneau chevauche un autre créneau du même jour.' : 'This slot overlaps another slot on the same day.');
      return;
    }

    try {
      await _service.savePersonal(
        id: entry?.id,
        studentId: widget.profile.id,
        subjectId: chosenId,
        subjectFr: subjectFr,
        subjectEn: subjectEn,
        dayOfWeek: dayOfWeek,
        startTime: startText,
        endTime: endText,
        room: room,
        notes: notes,
      );
      if (mounted) {
        setState(_reload);
      }
    } catch (_) {
      _snack(fr ? 'Enregistrement impossible.' : 'Unable to save.');
    }
  }

  Future<void> _delete(TimetableEntry entry) async {
    try {
      await _service.deletePersonal(entry.id, widget.profile.id);
      if (mounted) {
        setState(_reload);
      }
    } catch (_) {
      _snack(fr ? 'Suppression impossible.' : 'Unable to delete.');
    }
  }

  Future<void> _importClass() async {
    try {
      final added = await _service.importClassTimetable(widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(_reload);
      _snack(added == 0
          ? (fr ? 'Rien à importer.' : 'Nothing to import.')
          : (fr ? '$added créneau(x) importé(s).' : '$added slot(s) imported.'));
    } catch (_) {
      _snack(fr ? 'Import impossible.' : 'Import failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(fr ? 'Emploi du temps' : 'Timetable'),
          actions: [
            IconButton(
              tooltip: fr ? 'Actualiser' : 'Refresh',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: fr ? 'Mon planning' : 'My plan'),
              Tab(text: fr ? 'Ma salle' : 'My classroom'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPersonal(),
            _buildClass(),
          ],
        ),
      ),
    );
  }

  Widget _centered(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Map<int, List<TimetableEntry>> _byDay(List<TimetableEntry> entries) {
    final byDay = <int, List<TimetableEntry>>{};
    for (final entry in entries) {
      byDay.putIfAbsent(entry.dayOfWeek, () => []).add(entry);
    }
    return byDay;
  }

  Widget _dayTitle(int day) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(_dayName(day), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      );

  Widget _buildClass() {
    return FutureBuilder<List<TimetableEntry>>(
      future: _classFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _centered(fr ? 'Impossible de charger l’emploi du temps.' : 'Unable to load the timetable.');
        }
        final entries = snapshot.data ?? const <TimetableEntry>[];
        if (entries.isEmpty) {
          return _centered(fr ? 'Aucun cours planifié pour votre salle.' : 'No classes are scheduled for your classroom.');
        }
        final byDay = _byDay(entries);
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              for (final day in byDay.keys.toList()..sort()) ...[
                _dayTitle(day),
                ...byDay[day]!.map((entry) => _SlotCard(entry: entry, french: fr)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPersonal() {
    return Stack(
      children: [
        FutureBuilder<List<TimetableEntry>>(
          future: _personalFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _centered(fr ? 'Impossible de charger votre planning.' : 'Unable to load your plan.');
            }
            final entries = snapshot.data ?? const <TimetableEntry>[];
            if (entries.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.edit_calendar_rounded, size: 56, color: Color(0xFF166534)),
                  const SizedBox(height: 12),
                  Text(
                    fr
                        ? 'Construisez votre propre emploi du temps : choisissez une matière, un jour et une heure.'
                        : 'Build your own timetable: pick a subject, a day and a time.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _importClass,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(fr ? 'Partir de l’emploi du temps de ma salle' : 'Start from my classroom timetable'),
                    ),
                  ),
                ],
              );
            }
            final byDay = _byDay(entries);
            return RefreshIndicator(
              onRefresh: () async => setState(_reload),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  for (final day in byDay.keys.toList()..sort()) ...[
                    _dayTitle(day),
                    ...byDay[day]!.map(
                      (entry) => Dismissible(
                        key: ValueKey('personal_${entry.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete(entry),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _editSlot(entry: entry),
                          child: _SlotCard(entry: entry, french: fr),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _editSlot(),
            icon: const Icon(Icons.add_rounded),
            label: Text(fr ? 'Ajouter' : 'Add'),
          ),
        ),
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  final TimetableEntry entry;
  final bool french;

  const _SlotCard({required this.entry, required this.french});

  @override
  Widget build(BuildContext context) {
    final subject = french ? entry.subject : (entry.subjectEn?.trim().isNotEmpty == true ? entry.subjectEn! : entry.subject);
    final details = <String>[];
    if (entry.teacherName?.trim().isNotEmpty == true) {
      details.add(entry.teacherName!);
    }
    if (entry.room?.trim().isNotEmpty == true) {
      details.add(entry.room!);
    }
    if (entry.notes?.trim().isNotEmpty == true) {
      details.add(entry.notes!);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5EC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            entry.startTime,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF166534)),
          ),
        ),
        title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${entry.startTime} – ${entry.endTime}${details.isEmpty ? '' : '\n${details.join(' · ')}'}'),
      ),
    );
  }
}
