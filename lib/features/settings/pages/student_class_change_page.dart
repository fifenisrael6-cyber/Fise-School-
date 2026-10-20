import 'package:flutter/material.dart';

import '../../../core/services/student_class_change_service.dart';
import '../../../models/user_profile.dart';

/// Changement de salle simple : l'élève voit d'abord la salle recommandée
/// (niveau suivant, même série), peut chercher une autre salle, puis confirme.
class StudentClassChangePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const StudentClassChangePage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<StudentClassChangePage> createState() => _StudentClassChangePageState();
}

class _StudentClassChangePageState extends State<StudentClassChangePage> {
  static const _green = Color(0xFF166534);

  final StudentClassChangeService _service = StudentClassChangeService();
  final TextEditingController _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _classesFuture;
  bool _saving = false;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _classesFuture = _service.listNextClasses();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _classesFuture = _service.listNextClasses());

  String _label(Map<String, dynamic> row) {
    final raw = (row['class_name'] ?? '').toString().trim();
    final track = (row['track_label'] ?? '').toString().trim()
        .replaceFirst(RegExp(r'^(série|serie)\s+', caseSensitive: false), '');
    // Show the actual series instead of the ambiguous generic Terminale label.
    if (RegExp(r'^terminale(?:\s+simple)?$', caseSensitive: false).hasMatch(raw) &&
        const {'D', 'C', 'TI'}.contains(track.toUpperCase())) {
      return 'Terminale ${track.toUpperCase()}';
    }
    return raw;
  }

  String _subsystemLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'francophone':
        return _fr ? 'Sous-système francophone' : 'Francophone subsystem';
      case 'anglophone':
        return _fr ? 'Sous-système anglophone' : 'Anglophone subsystem';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _sectorLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'general':
        return _fr ? 'Enseignement général' : 'General education';
      case 'technical':
        return _fr ? 'Enseignement technique' : 'Technical education';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _subtitle(Map<String, dynamic> room) {
    final subsystem = _subsystemLabel(room['subsystem']);
    final sector = _sectorLabel(room['sector']);
    final level = room['exam_level_label']?.toString() ?? '';
    final track = room['track_label']?.toString() ?? '';
    final language = room['language_option']?.toString() ?? '';
    return [
      if (subsystem.isNotEmpty) subsystem,
      if (sector.isNotEmpty) sector,
      if (level.isNotEmpty) level,
      if (track.trim().isNotEmpty) track,
      if (language.isNotEmpty) language.replaceAll('_', ' + '),
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: Text(_fr ? 'Changer de salle' : 'Change classroom'),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(
              _fr
                  ? 'Impossible de charger les salles. Vérifie ta connexion et réessaie.'
                  : 'Could not load classrooms. Check your connection and try again.',
              retry: true,
            );
          }
          final loaded = snapshot.data ?? const <Map<String, dynamic>>[];
          // Prefer the configured series-specific Terminale rooms; hide the
          // ambiguous generic room when C, D or TI alternatives exist.
          final hasTerminaleSeries = loaded.any((row) {
            final label = '${row['class_name'] ?? ''} ${row['track_label'] ?? ''}';
            return RegExp(r'terminale.*(?:\bC\b|\bD\b|\bTI\b)', caseSensitive: false)
                .hasMatch(label);
          });
          final all = hasTerminaleSeries
              ? loaded.where((row) => !RegExp(r'^terminale(?:\s+simple)?
        },
      ),
    );
  }

  Widget _content(List<Map<String, dynamic>> all) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all
              .where(
                (r) =>
                    '${_label(r)} ${_subtitle(r)}'.toLowerCase().contains(query),
              )
              .toList();

    final recommended = visible.where((r) => r['recommended'] == true).toList();
    final others = visible.where((r) => r['recommended'] != true).toList();
    final sameLevel = others.where((r) => r['relation'] == 'same').toList();
    final previous = others.where((r) => r['relation'] == 'previous').toList();
    final rest = others
        .where((r) => r['relation'] != 'same' && r['relation'] != 'previous')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentCard(),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _fr
                  ? 'Chercher une salle ou une filière (ex. 3ème, C, D, TI, F2…)'
                  : 'Search a classroom or pathway (e.g. Form 5, Arts, Science, F2…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          _emptyState()
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(_fr ? 'Aucune salle trouvée.' : 'No classroom found.'),
            ),
          )
        else ...[
          if (recommended.isNotEmpty)
            _section(
              _fr ? 'Recommandée pour toi' : 'Recommended for you',
              recommended,
              highlight: true,
            ),
          if (sameLevel.isNotEmpty)
            _section(_fr ? 'Même niveau' : 'Same level', sameLevel),
          if (rest.isNotEmpty)
            _section(
              recommended.isEmpty
                  ? (_fr ? 'Salles disponibles' : 'Available classrooms')
                  : (_fr ? 'Autres salles' : 'Other classrooms'),
              rest,
            ),
          if (previous.isNotEmpty)
            _section(_fr ? 'Niveaux précédents' : 'Previous levels', previous),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _fr
                ? 'Ton compte et ton e-mail restent les mêmes. Les cours téléchargés de l’ancienne salle seront retirés de cet appareil. Tes anciennes notes, paiements et messages sont conservés.'
                : 'Your account and email stay the same. Downloads from the previous classroom are removed from this device. Your previous grades, payments and messages are kept.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _currentCard() {
    final current = widget.profile.className?.trim() ?? '';
    final details = [
      _subsystemLabel(widget.profile.subsystem),
      _sectorLabel(widget.profile.sector),
      widget.profile.examLevel ?? '',
      widget.profile.track ?? '',
      if ((widget.profile.languageOption ?? '').trim().isNotEmpty)
        widget.profile.languageOption!.replaceAll('_', ' + '),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school_rounded, color: _green),
        title: Text(
          _fr ? 'Ma salle actuelle' : 'My current classroom',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.isNotEmpty
                  ? current
                  : (_fr ? 'Salle non renseignée' : 'Classroom not set'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(details.join(' • ')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rooms, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ...rooms.map(
          (room) => Card(
            color: highlight ? const Color(0xFFDCFCE7) : null,
            child: ListTile(
              enabled: !_saving,
              leading: Icon(
                highlight ? Icons.star_rounded : Icons.meeting_room_outlined,
                color: _green,
              ),
              title: Text(
                _label(room),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: _subtitle(room).isEmpty ? null : Text(_subtitle(room)),
              trailing: _saving
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _confirmChange(room),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.info_outline_rounded, size: 38, color: _green),
        const SizedBox(height: 10),
        Text(
          _fr
              ? 'Aucune autre salle n’est disponible pour le moment. Contacte ton enseignant ou l’administration de l’école.'
              : 'No other classroom is available right now. Contact your teacher or the school administration.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _message(String message, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _reload,
              child: Text(_fr ? 'Réessayer' : 'Retry'),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _confirmChange(Map<String, dynamic> room) async {
    final fromClass =
        widget.profile.className?.trim().isNotEmpty == true
        ? widget.profile.className!
        : (_fr ? 'ta salle actuelle' : 'your current classroom');
    final target = _label(room);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Changer de salle ?' : 'Change classroom?'),
        content: Text(
          _fr
              ? 'Tu passes de « $fromClass » à « $target ». Tes cours téléchargés de l’ancienne salle seront retirés de cet appareil.'
              : 'You are moving from “$fromClass” to “$target”. Downloads from the old classroom will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Confirmer' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await _service.changeClass(room['class_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr ? 'Ta salle a été mise à jour.' : 'Your classroom was updated.',
          ),
        ),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr
                ? 'Le changement a échoué. Vérifie ta connexion puis réessaie.'
                : 'The change failed. Check your connection and try again.',
          ),
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
, caseSensitive: false).hasMatch(raw) &&
        const {'D', 'C', 'TI'}.contains(track.toUpperCase())) {
      return 'Terminale ${track.toUpperCase()}';
    }
    return raw;
  }

  String _subsystemLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'francophone':
        return _fr ? 'Sous-système francophone' : 'Francophone subsystem';
      case 'anglophone':
        return _fr ? 'Sous-système anglophone' : 'Anglophone subsystem';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _sectorLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'general':
        return _fr ? 'Enseignement général' : 'General education';
      case 'technical':
        return _fr ? 'Enseignement technique' : 'Technical education';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _subtitle(Map<String, dynamic> room) {
    final subsystem = _subsystemLabel(room['subsystem']);
    final sector = _sectorLabel(room['sector']);
    final level = room['exam_level_label']?.toString() ?? '';
    final track = room['track_label']?.toString() ?? '';
    final language = room['language_option']?.toString() ?? '';
    return [
      if (subsystem.isNotEmpty) subsystem,
      if (sector.isNotEmpty) sector,
      if (level.isNotEmpty) level,
      if (track.trim().isNotEmpty) track,
      if (language.isNotEmpty) language.replaceAll('_', ' + '),
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: Text(_fr ? 'Changer de salle' : 'Change classroom'),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(
              _fr
                  ? 'Impossible de charger les salles. Vérifie ta connexion et réessaie.'
                  : 'Could not load classrooms. Check your connection and try again.',
              retry: true,
            );
          }
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          return _content(all);
        },
      ),
    );
  }

  Widget _content(List<Map<String, dynamic>> all) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all
              .where(
                (r) =>
                    '${_label(r)} ${_subtitle(r)}'.toLowerCase().contains(query),
              )
              .toList();

    final recommended = visible.where((r) => r['recommended'] == true).toList();
    final others = visible.where((r) => r['recommended'] != true).toList();
    final sameLevel = others.where((r) => r['relation'] == 'same').toList();
    final previous = others.where((r) => r['relation'] == 'previous').toList();
    final rest = others
        .where((r) => r['relation'] != 'same' && r['relation'] != 'previous')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentCard(),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _fr
                  ? 'Chercher une salle ou une filière (ex. 3ème, C, D, TI, F2…)'
                  : 'Search a classroom or pathway (e.g. Form 5, Arts, Science, F2…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          _emptyState()
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(_fr ? 'Aucune salle trouvée.' : 'No classroom found.'),
            ),
          )
        else ...[
          if (recommended.isNotEmpty)
            _section(
              _fr ? 'Recommandée pour toi' : 'Recommended for you',
              recommended,
              highlight: true,
            ),
          if (sameLevel.isNotEmpty)
            _section(_fr ? 'Même niveau' : 'Same level', sameLevel),
          if (rest.isNotEmpty)
            _section(
              recommended.isEmpty
                  ? (_fr ? 'Salles disponibles' : 'Available classrooms')
                  : (_fr ? 'Autres salles' : 'Other classrooms'),
              rest,
            ),
          if (previous.isNotEmpty)
            _section(_fr ? 'Niveaux précédents' : 'Previous levels', previous),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _fr
                ? 'Ton compte et ton e-mail restent les mêmes. Les cours téléchargés de l’ancienne salle seront retirés de cet appareil. Tes anciennes notes, paiements et messages sont conservés.'
                : 'Your account and email stay the same. Downloads from the previous classroom are removed from this device. Your previous grades, payments and messages are kept.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _currentCard() {
    final current = widget.profile.className?.trim() ?? '';
    final details = [
      _subsystemLabel(widget.profile.subsystem),
      _sectorLabel(widget.profile.sector),
      widget.profile.examLevel ?? '',
      widget.profile.track ?? '',
      if ((widget.profile.languageOption ?? '').trim().isNotEmpty)
        widget.profile.languageOption!.replaceAll('_', ' + '),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school_rounded, color: _green),
        title: Text(
          _fr ? 'Ma salle actuelle' : 'My current classroom',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.isNotEmpty
                  ? current
                  : (_fr ? 'Salle non renseignée' : 'Classroom not set'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(details.join(' • ')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rooms, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ...rooms.map(
          (room) => Card(
            color: highlight ? const Color(0xFFDCFCE7) : null,
            child: ListTile(
              enabled: !_saving,
              leading: Icon(
                highlight ? Icons.star_rounded : Icons.meeting_room_outlined,
                color: _green,
              ),
              title: Text(
                _label(room),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: _subtitle(room).isEmpty ? null : Text(_subtitle(room)),
              trailing: _saving
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _confirmChange(room),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.info_outline_rounded, size: 38, color: _green),
        const SizedBox(height: 10),
        Text(
          _fr
              ? 'Aucune autre salle n’est disponible pour le moment. Contacte ton enseignant ou l’administration de l’école.'
              : 'No other classroom is available right now. Contact your teacher or the school administration.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _message(String message, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _reload,
              child: Text(_fr ? 'Réessayer' : 'Retry'),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _confirmChange(Map<String, dynamic> room) async {
    final fromClass =
        widget.profile.className?.trim().isNotEmpty == true
        ? widget.profile.className!
        : (_fr ? 'ta salle actuelle' : 'your current classroom');
    final target = _label(room);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Changer de salle ?' : 'Change classroom?'),
        content: Text(
          _fr
              ? 'Tu passes de « $fromClass » à « $target ». Tes cours téléchargés de l’ancienne salle seront retirés de cet appareil.'
              : 'You are moving from “$fromClass” to “$target”. Downloads from the old classroom will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Confirmer' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await _service.changeClass(room['class_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr ? 'Ta salle a été mise à jour.' : 'Your classroom was updated.',
          ),
        ),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr
                ? 'Le changement a échoué. Vérifie ta connexion puis réessaie.'
                : 'The change failed. Check your connection and try again.',
          ),
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
, caseSensitive: false)
                  .hasMatch((row['class_name'] ?? '').toString().trim())).toList()
              : loaded;
          return _content(all);
        },
      ),
    );
  }

  Widget _content(List<Map<String, dynamic>> all) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all
              .where(
                (r) =>
                    '${_label(r)} ${_subtitle(r)}'.toLowerCase().contains(query),
              )
              .toList();

    final recommended = visible.where((r) => r['recommended'] == true).toList();
    final others = visible.where((r) => r['recommended'] != true).toList();
    final sameLevel = others.where((r) => r['relation'] == 'same').toList();
    final previous = others.where((r) => r['relation'] == 'previous').toList();
    final rest = others
        .where((r) => r['relation'] != 'same' && r['relation'] != 'previous')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentCard(),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _fr
                  ? 'Chercher une salle ou une filière (ex. 3ème, C, D, TI, F2…)'
                  : 'Search a classroom or pathway (e.g. Form 5, Arts, Science, F2…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          _emptyState()
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(_fr ? 'Aucune salle trouvée.' : 'No classroom found.'),
            ),
          )
        else ...[
          if (recommended.isNotEmpty)
            _section(
              _fr ? 'Recommandée pour toi' : 'Recommended for you',
              recommended,
              highlight: true,
            ),
          if (sameLevel.isNotEmpty)
            _section(_fr ? 'Même niveau' : 'Same level', sameLevel),
          if (rest.isNotEmpty)
            _section(
              recommended.isEmpty
                  ? (_fr ? 'Salles disponibles' : 'Available classrooms')
                  : (_fr ? 'Autres salles' : 'Other classrooms'),
              rest,
            ),
          if (previous.isNotEmpty)
            _section(_fr ? 'Niveaux précédents' : 'Previous levels', previous),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _fr
                ? 'Ton compte et ton e-mail restent les mêmes. Les cours téléchargés de l’ancienne salle seront retirés de cet appareil. Tes anciennes notes, paiements et messages sont conservés.'
                : 'Your account and email stay the same. Downloads from the previous classroom are removed from this device. Your previous grades, payments and messages are kept.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _currentCard() {
    final current = widget.profile.className?.trim() ?? '';
    final details = [
      _subsystemLabel(widget.profile.subsystem),
      _sectorLabel(widget.profile.sector),
      widget.profile.examLevel ?? '',
      widget.profile.track ?? '',
      if ((widget.profile.languageOption ?? '').trim().isNotEmpty)
        widget.profile.languageOption!.replaceAll('_', ' + '),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school_rounded, color: _green),
        title: Text(
          _fr ? 'Ma salle actuelle' : 'My current classroom',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.isNotEmpty
                  ? current
                  : (_fr ? 'Salle non renseignée' : 'Classroom not set'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(details.join(' • ')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rooms, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ...rooms.map(
          (room) => Card(
            color: highlight ? const Color(0xFFDCFCE7) : null,
            child: ListTile(
              enabled: !_saving,
              leading: Icon(
                highlight ? Icons.star_rounded : Icons.meeting_room_outlined,
                color: _green,
              ),
              title: Text(
                _label(room),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: _subtitle(room).isEmpty ? null : Text(_subtitle(room)),
              trailing: _saving
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _confirmChange(room),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.info_outline_rounded, size: 38, color: _green),
        const SizedBox(height: 10),
        Text(
          _fr
              ? 'Aucune autre salle n’est disponible pour le moment. Contacte ton enseignant ou l’administration de l’école.'
              : 'No other classroom is available right now. Contact your teacher or the school administration.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _message(String message, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _reload,
              child: Text(_fr ? 'Réessayer' : 'Retry'),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _confirmChange(Map<String, dynamic> room) async {
    final fromClass =
        widget.profile.className?.trim().isNotEmpty == true
        ? widget.profile.className!
        : (_fr ? 'ta salle actuelle' : 'your current classroom');
    final target = _label(room);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Changer de salle ?' : 'Change classroom?'),
        content: Text(
          _fr
              ? 'Tu passes de « $fromClass » à « $target ». Tes cours téléchargés de l’ancienne salle seront retirés de cet appareil.'
              : 'You are moving from “$fromClass” to “$target”. Downloads from the old classroom will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Confirmer' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await _service.changeClass(room['class_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr ? 'Ta salle a été mise à jour.' : 'Your classroom was updated.',
          ),
        ),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr
                ? 'Le changement a échoué. Vérifie ta connexion puis réessaie.'
                : 'The change failed. Check your connection and try again.',
          ),
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
, caseSensitive: false).hasMatch(raw) &&
        const {'D', 'C', 'TI'}.contains(track.toUpperCase())) {
      return 'Terminale ${track.toUpperCase()}';
    }
    return raw;
  }

  String _subsystemLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'francophone':
        return _fr ? 'Sous-système francophone' : 'Francophone subsystem';
      case 'anglophone':
        return _fr ? 'Sous-système anglophone' : 'Anglophone subsystem';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _sectorLabel(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'general':
        return _fr ? 'Enseignement général' : 'General education';
      case 'technical':
        return _fr ? 'Enseignement technique' : 'Technical education';
      default:
        return raw?.toString() ?? '';
    }
  }

  String _subtitle(Map<String, dynamic> room) {
    final subsystem = _subsystemLabel(room['subsystem']);
    final sector = _sectorLabel(room['sector']);
    final level = room['exam_level_label']?.toString() ?? '';
    final track = room['track_label']?.toString() ?? '';
    final language = room['language_option']?.toString() ?? '';
    return [
      if (subsystem.isNotEmpty) subsystem,
      if (sector.isNotEmpty) sector,
      if (level.isNotEmpty) level,
      if (track.trim().isNotEmpty) track,
      if (language.isNotEmpty) language.replaceAll('_', ' + '),
    ].join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: Text(_fr ? 'Changer de salle' : 'Change classroom'),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message(
              _fr
                  ? 'Impossible de charger les salles. Vérifie ta connexion et réessaie.'
                  : 'Could not load classrooms. Check your connection and try again.',
              retry: true,
            );
          }
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          return _content(all);
        },
      ),
    );
  }

  Widget _content(List<Map<String, dynamic>> all) {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? all
        : all
              .where(
                (r) =>
                    '${_label(r)} ${_subtitle(r)}'.toLowerCase().contains(query),
              )
              .toList();

    final recommended = visible.where((r) => r['recommended'] == true).toList();
    final others = visible.where((r) => r['recommended'] != true).toList();
    final sameLevel = others.where((r) => r['relation'] == 'same').toList();
    final previous = others.where((r) => r['relation'] == 'previous').toList();
    final rest = others
        .where((r) => r['relation'] != 'same' && r['relation'] != 'previous')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _currentCard(),
        const SizedBox(height: 14),
        if (all.isNotEmpty)
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _fr
                  ? 'Chercher une salle ou une filière (ex. 3ème, C, D, TI, F2…)'
                  : 'Search a classroom or pathway (e.g. Form 5, Arts, Science, F2…)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          _emptyState()
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(_fr ? 'Aucune salle trouvée.' : 'No classroom found.'),
            ),
          )
        else ...[
          if (recommended.isNotEmpty)
            _section(
              _fr ? 'Recommandée pour toi' : 'Recommended for you',
              recommended,
              highlight: true,
            ),
          if (sameLevel.isNotEmpty)
            _section(_fr ? 'Même niveau' : 'Same level', sameLevel),
          if (rest.isNotEmpty)
            _section(
              recommended.isEmpty
                  ? (_fr ? 'Salles disponibles' : 'Available classrooms')
                  : (_fr ? 'Autres salles' : 'Other classrooms'),
              rest,
            ),
          if (previous.isNotEmpty)
            _section(_fr ? 'Niveaux précédents' : 'Previous levels', previous),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _fr
                ? 'Ton compte et ton e-mail restent les mêmes. Les cours téléchargés de l’ancienne salle seront retirés de cet appareil. Tes anciennes notes, paiements et messages sont conservés.'
                : 'Your account and email stay the same. Downloads from the previous classroom are removed from this device. Your previous grades, payments and messages are kept.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _currentCard() {
    final current = widget.profile.className?.trim() ?? '';
    final details = [
      _subsystemLabel(widget.profile.subsystem),
      _sectorLabel(widget.profile.sector),
      widget.profile.examLevel ?? '',
      widget.profile.track ?? '',
      if ((widget.profile.languageOption ?? '').trim().isNotEmpty)
        widget.profile.languageOption!.replaceAll('_', ' + '),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school_rounded, color: _green),
        title: Text(
          _fr ? 'Ma salle actuelle' : 'My current classroom',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.isNotEmpty
                  ? current
                  : (_fr ? 'Salle non renseignée' : 'Classroom not set'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(details.join(' • ')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> rooms, {
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ...rooms.map(
          (room) => Card(
            color: highlight ? const Color(0xFFDCFCE7) : null,
            child: ListTile(
              enabled: !_saving,
              leading: Icon(
                highlight ? Icons.star_rounded : Icons.meeting_room_outlined,
                color: _green,
              ),
              title: Text(
                _label(room),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: _subtitle(room).isEmpty ? null : Text(_subtitle(room)),
              trailing: _saving
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _confirmChange(room),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.info_outline_rounded, size: 38, color: _green),
        const SizedBox(height: 10),
        Text(
          _fr
              ? 'Aucune autre salle n’est disponible pour le moment. Contacte ton enseignant ou l’administration de l’école.'
              : 'No other classroom is available right now. Contact your teacher or the school administration.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _message(String message, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _reload,
              child: Text(_fr ? 'Réessayer' : 'Retry'),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _confirmChange(Map<String, dynamic> room) async {
    final fromClass =
        widget.profile.className?.trim().isNotEmpty == true
        ? widget.profile.className!
        : (_fr ? 'ta salle actuelle' : 'your current classroom');
    final target = _label(room);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_fr ? 'Changer de salle ?' : 'Change classroom?'),
        content: Text(
          _fr
              ? 'Tu passes de « $fromClass » à « $target ». Tes cours téléchargés de l’ancienne salle seront retirés de cet appareil.'
              : 'You are moving from “$fromClass” to “$target”. Downloads from the old classroom will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_fr ? 'Annuler' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_fr ? 'Confirmer' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await _service.changeClass(room['class_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr ? 'Ta salle a été mise à jour.' : 'Your classroom was updated.',
          ),
        ),
      );
      Navigator.pop(context, updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fr
                ? 'Le changement a échoué. Vérifie ta connexion puis réessaie.'
                : 'The change failed. Check your connection and try again.',
          ),
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
