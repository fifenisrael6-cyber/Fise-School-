import 'package:flutter/material.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/smart_course_service.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';

class TeacherSmartProgressPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherSmartProgressPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherSmartProgressPage> createState() => _TeacherSmartProgressPageState();
}

class _TeacherSmartProgressPageState extends State<TeacherSmartProgressPage> {
  final CourseService _courses = CourseService();
  final SmartCourseService _smart = SmartCourseService();

  List<SchoolClass> _classes = const [];
  String? _classId;
  List<Map<String, dynamic>> _students = const [];
  List<Map<String, dynamic>> _subjects = const [];
  bool _loading = true;
  String? _error;

  bool get _fr => widget.locale.languageCode != 'en';

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
      final classes = await _courses.listTeacherCompatibleClasses();
      if (!mounted) {
        return;
      }
      _classes = classes;
      _classId = classes.isNotEmpty ? classes.first.id : null;
      if (_classId != null) {
        await _loadClassData(_classId!, showLoader: false);
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Impossible de charger les classes.' : 'Unable to load classes.';
      });
    }
  }

  Future<void> _loadClassData(String classId, {bool showLoader = true}) async {
    if (showLoader) {
      setState(() => _loading = true);
    }
    try {
      // The teacher may select any room in their own subsystem/sector. Activate
      // this one room before reading its roster and progress, not every room.
      await _courses.authorizeTeacherClasses([classId]);
      final results = await Future.wait([
        _smart.getTeacherClassDetail(classId),
        _smart.getTeacherSubjectDetail(classId),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _students = results[0];
        _subjects = results[1];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Impossible de charger la progression.' : 'Unable to load progress.';
      });
    }
  }

  String _num(Object? value) => (value as num?)?.toStringAsFixed(1) ?? '0.0';

  String _initial(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '?' : text.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    SchoolClass? selected;
    for (final item in _classes) {
      if (item.id == _classId) {
        selected = item;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Progression de la salle' : 'Class progress'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Actualiser' : 'Refresh',
            onPressed: _classId == null ? null : () => _loadClassData(_classId!),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _classes.isEmpty
                  ? Center(child: Text(_fr ? 'Aucune salle compatible avec votre sous-système et votre secteur.' : 'No classroom matches your subsystem and sector.'))
                  : RefreshIndicator(
                      onRefresh: () => _loadClassData(_classId!),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _classId,
                            decoration: InputDecoration(
                              labelText: _fr ? 'Salle' : 'Class',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              for (final item in _classes)
                                DropdownMenuItem(value: item.id, child: Text(item.displayName)),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() => _classId = value);
                              _loadClassData(value);
                            },
                          ),
                          if (selected != null) ...[
                            const SizedBox(height: 16),
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                                title: Text(selected.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Text(selected.name),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Text(_fr ? 'Élèves à accompagner' : 'Students to support', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          if (_students.isEmpty)
                            Text(_fr ? 'Aucune donnée de progression pour le moment.' : 'No progress data yet.')
                          else
                            ..._students.map((row) {
                              final late = row['late'] == true;
                              final done = (row['completed_lessons'] as num?)?.toInt() ?? 0;
                              final available = (row['available_lessons'] as num?)?.toInt() ?? 0;
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(child: Text(_initial(row['student_name']))),
                                  title: Text(row['student_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${_num(row['average_score'])}% • $done / $available ${_fr ? 'leçons' : 'lessons'}'),
                                  trailing: late
                                      ? Chip(
                                          label: Text(_fr ? 'En retard' : 'Behind'),
                                          avatar: const Icon(Icons.schedule_rounded, size: 16),
                                        )
                                      : const Icon(Icons.check_circle_outline_rounded),
                                ),
                              );
                            }),
                          const SizedBox(height: 18),
                          Text(_fr ? 'Matières difficiles' : 'Difficult subjects', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          if (_subjects.isEmpty)
                            Text(_fr ? 'Aucune matière indexée pour le moment.' : 'No indexed subject yet.')
                          else
                            ..._subjects.map((row) {
                              final difficult = row['difficult'] == true;
                              final done = (row['completed_lessons'] as num?)?.toInt() ?? 0;
                              final available = (row['available_lessons'] as num?)?.toInt() ?? 0;
                              return Card(
                                child: ListTile(
                                  leading: Icon(difficult ? Icons.warning_amber_rounded : Icons.menu_book_rounded),
                                  title: Text(row['subject_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${_num(row['average_score'])}% • $done / $available ${_fr ? 'leçons' : 'lessons'}'),
                                  trailing: difficult
                                      ? Chip(label: Text(_fr ? 'À renforcer' : 'Needs support'))
                                      : Text(_fr ? 'Suivi normal' : 'On track'),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
    );
  }
}
