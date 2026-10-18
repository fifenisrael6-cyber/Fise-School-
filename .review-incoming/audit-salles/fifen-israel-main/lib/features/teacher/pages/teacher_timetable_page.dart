import 'package:flutter/material.dart';

import '../../../core/services/timetable_service.dart';
import '../../../models/timetable_entry.dart';
import '../../../models/user_profile.dart';

class TeacherTimetablePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  const TeacherTimetablePage({super.key, required this.locale, required this.profile});

  @override
  State<TeacherTimetablePage> createState() => _TeacherTimetablePageState();
}

class _TeacherTimetablePageState extends State<TeacherTimetablePage> {
  late Future<List<TimetableEntry>> _future;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _future = TimetableService().listForTeacher(widget.profile.id);
  }

  Future<void> _reload() async {
    final next = TimetableService().listForTeacher(widget.profile.id);
    setState(() => _future = next);
    await next.catchError((_) => <TimetableEntry>[]);
  }

  String _day(int d) {
    final days = _fr
        ? const ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche']
        : const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[(d - 1).clamp(0, 6)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Mon emploi du temps' : 'My timetable')),
      body: FutureBuilder<List<TimetableEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fr ? 'Impossible de charger l’emploi du temps.' : 'Unable to load the timetable.', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: Text(_fr ? 'Réessayer' : 'Retry')),
                ]),
              ),
            );
          }
          final items = snap.data ?? const <TimetableEntry>[];
          if (items.isEmpty) {
            return Center(child: Text(_fr ? 'Aucun créneau ne vous est affecté.' : 'No timetable slots assigned to you.'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final room = (e.room == null || e.room!.isEmpty) ? '' : ' · ${e.room}';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text('${_day(e.dayOfWeek)} · ${e.startTime}–${e.endTime}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${e.subject}$room'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
