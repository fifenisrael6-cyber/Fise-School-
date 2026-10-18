import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/admin_school_service.dart';
import '../../../models/user_profile.dart';

class AdminPeoplePage extends StatefulWidget {
  final Locale locale;
  final String role;
  final AdminSchoolService? schoolService;

  const AdminPeoplePage({
    super.key,
    required this.locale,
    required this.role,
    this.schoolService,
  });

  @override
  State<AdminPeoplePage> createState() => _AdminPeoplePageState();
}

class _AdminPeoplePageState extends State<AdminPeoplePage> {
  late final AdminSchoolService _service =
      widget.schoolService ?? AdminSchoolService();

  final _search = TextEditingController();

  late Future<List<UserProfile>> _future = _load();

  Future<List<UserProfile>> _load() =>
      _service.listPeople(role: widget.role, query: _search.text);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);
    final title = widget.role == 'student' ? texts.students : texts.teachers;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              onSubmitted: (_) {
                setState(() => _future = _load());
              },
              decoration: InputDecoration(
                labelText: texts.search,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _future = _load());
                  },
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<UserProfile>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text(texts.adminLoadError));
                }

                final people = snapshot.data ?? const <UserProfile>[];

                if (people.isEmpty) {
                  return Center(child: Text(texts.noPeople));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: people.length,
                  itemBuilder: (context, index) =>
                      _personTile(context, texts, people[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _personTile(
    BuildContext context,
    AppTexts texts,
    UserProfile person,
  ) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text('${person.firstName} ${person.lastName}'),
      subtitle: Text(
        '${person.email ?? ''}\n'
        '${person.subsystem ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')} • '
        '${person.sector ?? (texts.isEnglish ? 'Not set' : 'Non renseigné')}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.arrow_forward_ios),
      onTap: () => _showDetails(context, texts, person),
    ),
  );

  Future<void> _showDetails(
    BuildContext context,
    AppTexts texts,
    UserProfile person,
  ) async {
    final classes = widget.role == 'student'
        ? await _service.classesForStudent(person.id)
        : await _service.classesForTeacher(person.id);

    if (!context.mounted) {
      return;
    }

    String? stream;
    if (widget.role == 'teacher') {
      try {
        final row = await Supabase.instance.client
            .from('profiles').select('teaching_stream').eq('id', person.id).maybeSingle();
        stream = row?['teaching_stream'] as String?;
      } catch (_) {}
      if (!context.mounted) return;
    }

    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('${person.firstName} ${person.lastName}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.email ?? ''),
              const SizedBox(height: 12),
              Text(
                texts.classes,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              ...classes.map((item) => Text(item.displayName)),
              if (widget.role == 'teacher') ...[
                const SizedBox(height: 12),
                const Text('Filière de l’enseignant (commission Premium)',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Wrap(spacing: 8, children: [
                  for (final option in const {'scientific': 'Scientifique', 'literary': 'Littéraire'}.entries)
                    ChoiceChip(
                      label: Text(option.value),
                      selected: stream == option.key,
                      onSelected: (_) async {
                        try {
                          await Supabase.instance.client.rpc('admin_set_teacher_stream',
                              params: {'p_teacher_id': person.id, 'p_stream': option.key});
                          setDialogState(() => stream = option.key);
                        } catch (_) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Enregistrement impossible.')));
                          }
                        }
                      },
                    ),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(texts.back),
          ),
        ],
      )),
    );
  }
}
