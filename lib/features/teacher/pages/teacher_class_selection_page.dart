import 'package:flutter/material.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../models/school_class.dart';
import '../../../models/user_profile.dart';

/// Permet à l'enseignant de choisir durablement les salles visibles dans ses
/// formulaires de cours, QCM et activités pédagogiques.
class TeacherClassSelectionPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const TeacherClassSelectionPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<TeacherClassSelectionPage> createState() => _TeacherClassSelectionPageState();
}

class _TeacherClassSelectionPageState extends State<TeacherClassSelectionPage> {
  final CourseService _service = CourseService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<SchoolClass> _classes = const [];
  final Set<String> _selectedIds = <String>{};

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.listTeacherCompatibleClasses(),
        _service.listTeacherFollowedClassIds(),
      ]);
      if (!mounted) return;
      final classes = results[0] as List<SchoolClass>;
      final selected = results[1] as Set<String>;
      setState(() {
        _classes = classes;
        _selectedIds
          ..clear()
          ..addAll(selected.where((id) => classes.any((room) => room.id == id)));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty) {
      _message(_fr
          ? 'Sélectionnez au moins une salle pour continuer.'
          : 'Select at least one classroom to continue.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveTeacherFollowedClasses(_selectedIds.toList(growable: false));
      if (!mounted) return;
      _message(_fr
          ? 'Vos salles ont été enregistrées. Les formulaires de cours et de QCM utiliseront cette sélection.'
          : 'Your classrooms have been saved. Course and quiz forms will use this selection.');
    } catch (error) {
      if (mounted) _message('${_fr ? 'Enregistrement impossible' : 'Could not save'}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _classes.where((room) => room.displayName.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Mes cours et mes salles' : 'My courses and classrooms'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Actualiser' : 'Refresh',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_fr ? 'Impossible de charger les salles.' : 'Could not load classrooms.'),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(_fr ? 'Réessayer' : 'Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _classes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_fr
                            ? 'Aucune salle active compatible avec votre profil n’est disponible.'
                            : 'No active classroom compatible with your profile is available.'),
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fr ? 'Choisissez les salles de votre espace de travail' : 'Choose classrooms for your workspace',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(_fr
                                      ? 'Cochez les salles à conserver. Les salles décochées seront retirées de votre sélection après enregistrement. Cette sélection est conservée dans Supabase.'
                                      : 'Select the classrooms to keep. Unchecked classrooms will be removed from your selection when saved. This selection is stored in Supabase.'),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_selectedIds.length} ${_fr ? 'salle(s) sélectionnée(s)' : 'classroom(s) selected'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: _fr ? 'Rechercher une salle…' : 'Search classrooms…',
                              border: const OutlineInputBorder(),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () => setState(_search.clear),
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final room = visible[index];
                              final selected = _selectedIds.contains(room.id);
                              return Card(
                                child: CheckboxListTile(
                                  value: selected,
                                  onChanged: _saving
                                      ? null
                                      : (value) => setState(() {
                                            if (value == true) {
                                              _selectedIds.add(room.id);
                                            } else {
                                              _selectedIds.remove(room.id);
                                            }
                                          }),
                                  secondary: Icon(
                                    selected ? Icons.meeting_room_rounded : Icons.door_front_door_outlined,
                                  ),
                                  title: Text(room.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text('${room.subsystem.name} · ${room.sector.name}'),
                                  controlAffinity: ListTileControlAffinity.leading,
                                ),
                              );
                            },
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.save_rounded),
                                label: Text(_saving
                                    ? (_fr ? 'Enregistrement…' : 'Saving…')
                                    : (_fr ? 'Enregistrer mes salles' : 'Save my classrooms')),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
