import 'package:flutter/material.dart';

import '../../../core/services/grade_service.dart';
import '../../../models/grades.dart';
import '../../student/pages/bulletin_page.dart';
import '../../teacher/pages/grades_entry_page.dart';

/// Administration des notes : périodes (publication), coefficients, bulletins, saisie.
class AdminGradesPage extends StatelessWidget {
  final Locale locale;
  const AdminGradesPage({super.key, required this.locale});

  @override
  Widget build(BuildContext context) {
    final fr = locale.languageCode == 'fr';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(fr ? 'Notes et bulletins' : 'Marks and report cards'),
          actions: [
            IconButton(
              tooltip: fr ? 'Saisir des notes' : 'Enter marks',
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GradesEntryPage(locale: locale, asAdmin: true)),
              ),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: fr ? 'Périodes' : 'Periods'),
            Tab(text: 'Coef.'),
            Tab(text: fr ? 'Bulletins' : 'Reports'),
          ]),
        ),
        body: TabBarView(children: [
          _PeriodsTab(locale: locale),
          _CoefficientsTab(locale: locale),
          _BulletinsTab(locale: locale),
        ]),
      ),
    );
  }
}

class _PeriodsTab extends StatefulWidget {
  final Locale locale;
  const _PeriodsTab({required this.locale});
  @override
  State<_PeriodsTab> createState() => _PeriodsTabState();
}

class _PeriodsTabState extends State<_PeriodsTab> {
  final _service = GradeService();
  bool _loading = true;
  String? _error;
  List<GradePeriod> _periods = const [];
  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _service.listPeriods();
      if (!mounted) {
        return;
      }
      setState(() {
        _periods = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Chargement impossible : $e' : 'Unable to load: $e';
      });
    }
  }

  Future<void> _toggle(GradePeriod p, bool value) async {
    try {
      await _service.setPeriodPublished(p.id, value);
      if (!mounted) {
        return;
      }
      _snack(value
          ? (_fr ? 'Bulletins publiés : les élèves sont notifiés.' : 'Report cards published: students notified.')
          : (_fr ? 'Bulletins masqués.' : 'Report cards hidden.'));
      await _load();
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Modification impossible : $e' : 'Update failed: $e');
      }
    }
  }

  Future<void> _add() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fr ? 'Nouvelle période' : 'New period'),
        content: TextField(controller: ctl, decoration: InputDecoration(labelText: _fr ? 'Nom (ex. Séquence 7)' : 'Name (e.g. Sequence 7)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Créer' : 'Create')),
        ],
      ),
    );
    final label = ctl.text.trim();
    ctl.dispose();
    if (ok != true || label.isEmpty) {
      return;
    }
    try {
      final next = _periods.isEmpty ? 1 : _periods.map((p) => p.position).reduce((a, b) => a > b ? a : b) + 1;
      await _service.createPeriod(label, next);
      if (mounted) {
        await _load();
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Création impossible : $e' : 'Create failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(_fr ? 'Période' : 'Period'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    Text(_fr
                        ? 'Les élèves ne voient leurs notes et leur bulletin qu’une fois la période publiée.'
                        : 'Students only see their marks and report card once the period is published.'),
                    const SizedBox(height: 8),
                    ..._periods.map(
                      (p) => Card(
                        child: SwitchListTile(
                          title: Text(p.labelFor(widget.locale.languageCode), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(p.isPublished ? (_fr ? 'Publiée' : 'Published') : (_fr ? 'Non publiée' : 'Not published')),
                          value: p.isPublished,
                          onChanged: (v) => _toggle(p, v),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CoefficientsTab extends StatefulWidget {
  final Locale locale;
  const _CoefficientsTab({required this.locale});
  @override
  State<_CoefficientsTab> createState() => _CoefficientsTabState();
}

class _CoefficientsTabState extends State<_CoefficientsTab> {
  final _service = GradeService();
  List<GradeClassOption> _classes = const [];
  List<GradeSubject> _subjects = const [];
  String? _classId;
  bool _loading = true;
  String? _error;
  bool get _fr => widget.locale.languageCode == 'fr';
  String get _lang => widget.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _init() async {
    try {
      final c = await _service.listAllClasses();
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Chargement impossible : $e' : 'Unable to load: $e';
      });
    }
  }

  Future<void> _pick(String? id) async {
    setState(() {
      _classId = id;
      _subjects = const [];
    });
    if (id == null) {
      return;
    }
    try {
      final s = await _service.listClassSubjects(id);
      if (mounted) {
        setState(() => _subjects = s);
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Matières indisponibles.' : 'Subjects unavailable.');
      }
    }
  }

  Future<void> _edit(GradeSubject s) async {
    final ctl = TextEditingController(text: s.coefficient.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.nameFor(_lang)),
        content: TextField(
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: _fr ? 'Coefficient' : 'Coefficient'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_fr ? 'Enregistrer' : 'Save')),
        ],
      ),
    );
    final value = double.tryParse(ctl.text.trim().replaceAll(',', '.'));
    ctl.dispose();
    if (ok != true) {
      return;
    }
    if (value == null || value <= 0 || value > 99) {
      _snack(_fr ? 'Coefficient invalide.' : 'Invalid coefficient.');
      return;
    }
    try {
      await _service.updateCoefficient(s.classSubjectId, value);
      if (_classId != null) {
        await _pick(_classId);
      }
    } catch (e) {
      if (mounted) {
        _snack(_fr ? 'Modification impossible : $e' : 'Update failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _classId,
          decoration: InputDecoration(labelText: _fr ? 'Salle' : 'Class', border: const OutlineInputBorder()),
          items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
          onChanged: _pick,
        ),
        const SizedBox(height: 12),
        ..._subjects.map(
          (s) => Card(
            child: ListTile(
              title: Text(s.nameFor(_lang)),
              subtitle: Text('Coef. ${s.coefficient}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(s),
            ),
          ),
        ),
      ],
    );
  }
}

class _BulletinsTab extends StatefulWidget {
  final Locale locale;
  const _BulletinsTab({required this.locale});
  @override
  State<_BulletinsTab> createState() => _BulletinsTabState();
}

class _BulletinsTabState extends State<_BulletinsTab> {
  final _service = GradeService();
  List<GradeClassOption> _classes = const [];
  List<RosterStudent> _roster = const [];
  String? _classId;
  bool _loading = true;
  String? _error;
  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = await _service.listAllClasses();
      if (!mounted) {
        return;
      }
      setState(() {
        _classes = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _fr ? 'Chargement impossible : $e' : 'Unable to load: $e';
      });
    }
  }

  Future<void> _pick(String? id) async {
    setState(() {
      _classId = id;
      _roster = const [];
    });
    if (id == null) {
      return;
    }
    try {
      final r = await _service.roster(id);
      if (mounted) {
        setState(() => _roster = r);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_fr ? 'Liste des élèves indisponible.' : 'Student list unavailable.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final className = _classes.where((c) => c.id == _classId).map((c) => c.displayName).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _classId,
          decoration: InputDecoration(labelText: _fr ? 'Salle' : 'Class', border: const OutlineInputBorder()),
          items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
          onChanged: _pick,
        ),
        const SizedBox(height: 12),
        ..._roster.map(
          (s) => Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.fullName),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BulletinPage(
                    locale: widget.locale,
                    studentId: s.id,
                    studentName: s.fullName,
                    className: className,
                    onlyPublished: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
