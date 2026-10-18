import 'package:flutter/material.dart';

import '../../../core/services/school_class_service.dart';
import '../../../core/services/timetable_service.dart';
import '../../../models/timetable_entry.dart';

class AdminTimetablePage extends StatefulWidget {
  final Locale locale;
  const AdminTimetablePage({super.key, required this.locale});
  @override State<AdminTimetablePage> createState() => _AdminTimetablePageState();
}

class _AdminTimetablePageState extends State<AdminTimetablePage> {
  final _school = SchoolClassService();
  final _timetable = TimetableService();
  late Future<List<Map<String, dynamic>>> _classes;
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _teachers = [];
  String? _classId;
  String? _subjectId;
  String? _teacherId;
  int _day = 1;
  TimeOfDay _start = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 30);
  final _room = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  List<TimetableEntry> _entries = [];

  bool get fr => widget.locale.languageCode == 'fr';
  @override void initState() { super.initState(); _classes = _school.listClasses(activeOnly: true); }
  @override void dispose() { _room.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _loadClass(String id) async {
    setState(() { _classId = id; _subjectId = null; _teacherId = null; });
    final subjects = await _school.listClassSubjects(id);
    final teachers = await _school.listClassTeachers(id);
    final entries = await _timetable.listForClass(id);
    if (!mounted) {
      return;
    }
    setState(() { _subjects = subjects.map((r) => Map<String,dynamic>.from(r['subjects'] as Map? ?? r)).toList(); _teachers = teachers.map((r) => Map<String,dynamic>.from(r['profiles'] as Map? ?? r)).toList(); _entries = entries; });
  }

  String _time(TimeOfDay t) => '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:00';
  String _dayName(int d) => (fr ? const ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi'] : const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'])[d-1];

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked != null && mounted) {
      setState(() { if (start) {
        _start = picked;
      } else {
        _end = picked;
      } });
    }
  }

  Future<void> _save() async {
    if (_classId == null || _subjectId == null) {
      return;
    }
    final subject = _subjects.firstWhere((s) => s['id'].toString() == _subjectId);
    final teacher = _teacherId == null ? null : _teachers.firstWhere((t) => t['id'].toString() == _teacherId);
    if ((_end.hour * 60 + _end.minute) <= (_start.hour * 60 + _start.minute)) { _show(fr ? 'L’heure de fin doit être après le début.' : 'End time must be after start time.'); return; }
    setState(() => _saving = true);
    try {
      await _timetable.create(classId: _classId!, subjectId: _subjectId, subjectFr: subject['name_fr']?.toString() ?? '', subjectEn: subject['name_en']?.toString() ?? '', teacherId: _teacherId, teacherName: teacher == null ? null : '${teacher['first_name'] ?? ''} ${teacher['last_name'] ?? ''}'.trim(), dayOfWeek: _day, startTime: _time(_start), endTime: _time(_end), room: _room.text, notes: _notes.text);
      _room.clear(); _notes.clear();
      await _loadClass(_classId!);
      if (mounted) {
        _show(fr ? 'Créneau enregistré.' : 'Timetable slot saved.');
      }
    } catch (e) { if (mounted) _show(e.toString()); } finally { if (mounted) setState(() => _saving = false); }
  }

  void _show(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(fr ? 'Emploi du temps' : 'Timetable')),
    body: FutureBuilder<List<Map<String,dynamic>>>(future: _classes, builder: (context, snap) {
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final classes = snap.data!;
      return ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(initialValue: _classId, decoration: InputDecoration(labelText: fr ? 'Salle' : 'Class'), items: classes.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['display_name']?.toString() ?? ''))).toList(), onChanged: (v) { if (v != null) _loadClass(v); }),
        if (_classId != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _subjectId, decoration: InputDecoration(labelText: fr ? 'Matière' : 'Subject'), items: _subjects.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['name_fr']?.toString() ?? s['name_en']?.toString() ?? ''))).toList(), onChanged: (v) => setState(() => _subjectId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _teacherId, decoration: InputDecoration(labelText: fr ? 'Enseignant' : 'Teacher'), items: [DropdownMenuItem<String>(value: null, child: Text(fr ? 'Aucun' : 'None')), ..._teachers.map((t) => DropdownMenuItem(value: t['id'].toString(), child: Text('${t['first_name'] ?? ''} ${t['last_name'] ?? ''}'.trim())))], onChanged: (v) => setState(() => _teacherId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(initialValue: _day, decoration: InputDecoration(labelText: fr ? 'Jour' : 'Day'), items: List.generate(6, (i) => DropdownMenuItem(value: i+1, child: Text(_dayName(i+1)))), onChanged: (v) => setState(() => _day = v ?? 1)),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: OutlinedButton(onPressed: () => _pickTime(true), child: Text('${fr ? 'Début' : 'Start'} ${_start.format(context)}'))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => _pickTime(false), child: Text('${fr ? 'Fin' : 'End'} ${_end.format(context)}')))]),
          const SizedBox(height: 12),
          TextField(controller: _room, decoration: InputDecoration(labelText: fr ? 'Salle physique (optionnel)' : 'Physical room (optional)')),
          const SizedBox(height: 12), TextField(controller: _notes, decoration: InputDecoration(labelText: fr ? 'Notes (optionnel)' : 'Notes (optional)')),
          const SizedBox(height: 14), FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.add), label: Text(fr ? 'Ajouter le créneau' : 'Add slot')),
          const SizedBox(height: 20),
          Text(fr ? 'Créneaux de la salle' : 'Class timetable', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_entries.isEmpty) Text(fr ? 'Aucun créneau.' : 'No timetable slots.'),
          ..._entries.map((e) => Card(child: ListTile(title: Text('${_dayName(e.dayOfWeek)} · ${e.startTime}–${e.endTime}'), subtitle: Text('${e.subject}${e.teacherName == null ? '' : ' · ${e.teacherName}'}${e.room == null || e.room!.isEmpty ? '' : ' · ${e.room}'}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await _timetable.delete(e.id); if (_classId != null) _loadClass(_classId!); })))),
        ],
      ]);
    }),
  );
}
