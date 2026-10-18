import 'package:flutter/material.dart';

import '../../../core/services/school_class_service.dart';
import 'school_class_detail_page.dart';

class SchoolClassesPage extends StatefulWidget {
  final Locale locale;

  const SchoolClassesPage({super.key, required this.locale});

  @override
  State<SchoolClassesPage> createState() => _SchoolClassesPageState();
}

class _SchoolClassesPageState extends State<SchoolClassesPage> {
  final SchoolClassService _service = SchoolClassService();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _years = const [];
  List<Map<String, dynamic>> _classes = const [];

  String? _selectedYearId;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final years = await _service.listAcademicYears();

      String? yearId = _selectedYearId;

      if (yearId == null && years.isNotEmpty) {
        final current = years.cast<Map<String, dynamic>>().firstWhere(
          (year) => year['is_current'] == true,
          orElse: () => years.first,
        );

        yearId = current['id']?.toString();
      }

      final classes = await _service.listClasses(academicYearId: yearId);

      if (!mounted) {
        return;
      }

      setState(() {
        _years = years;
        _selectedYearId = yearId;
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadClassesForYear(String? yearId) async {
    setState(() {
      _loading = true;
      _selectedYearId = yearId;
      _error = null;
    });

    try {
      final classes = await _service.listClasses(academicYearId: yearId);

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createAcademicYear() async {
    final labelController = TextEditingController();

    DateTime? startDate;
    DateTime? endDate;
    bool isCurrent = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _isFrench ? 'Nouvelle année scolaire' : 'New academic year',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Libellé' : 'Label',
                        hintText: '2026-2027',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month),
                      title: Text(
                        startDate == null
                            ? (_isFrench ? 'Date de début' : 'Start date')
                            : _formatDate(startDate!),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: startDate ?? DateTime.now(),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            startDate = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available),
                      title: Text(
                        endDate == null
                            ? (_isFrench ? 'Date de fin' : 'End date')
                            : _formatDate(endDate!),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: startDate ?? DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: endDate ?? startDate ?? DateTime.now(),
                        );

                        if (picked != null) {
                          setDialogState(() {
                            endDate = picked;
                          });
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isCurrent,
                      title: Text(
                        _isFrench ? 'Année courante' : 'Current year',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          isCurrent = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: Text(_isFrench ? 'Annuler' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (labelController.text.trim().isEmpty) {
                      return;
                    }

                    try {
                      await _service.createAcademicYear(
                        label: labelController.text,
                        startDate: startDate,
                        endDate: endDate,
                        isCurrent: isCurrent,
                      );

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  child: Text(_isFrench ? 'Créer' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    labelController.dispose();

    if (created == true) {
      await _load();
    }
  }

  Future<void> _createClass() async {
    if (_years.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Créez d’abord une année scolaire.'
                : 'Create an academic year first.',
          ),
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final displayController = TextEditingController();

    String subsystem = 'francophone';
    String sector = 'general';

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _isFrench ? 'Nouvelle salle de classe' : 'New classroom',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Nom interne' : 'Internal name',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayController,
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Nom affiché' : 'Display name',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: subsystem,
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Sous-système' : 'Subsystem',
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'francophone',
                          child: Text('Francophone'),
                        ),
                        DropdownMenuItem(
                          value: 'anglophone',
                          child: Text('Anglophone'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          subsystem = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: sector,
                      decoration: InputDecoration(
                        labelText: _isFrench ? 'Secteur' : 'Sector',
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'general',
                          child: Text('Général / General'),
                        ),
                        DropdownMenuItem(
                          value: 'technical',
                          child: Text('Technique / Technical'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          sector = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, false);
                  },
                  child: Text(_isFrench ? 'Annuler' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (_selectedYearId == null) {
                      return;
                    }

                    if (nameController.text.trim().isEmpty ||
                        displayController.text.trim().isEmpty) {
                      return;
                    }

                    try {
                      await _service.createClass(
                        name: nameController.text,
                        displayName: displayController.text,
                        subsystem: subsystem,
                        sector: sector,
                        academicYearId: _selectedYearId!,
                      );

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  },
                  child: Text(_isFrench ? 'Créer' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    displayController.dispose();

    if (created == true) {
      await _load();
    }
  }

  Future<void> _toggleClass(Map<String, dynamic> schoolClass) async {
    final id = schoolClass['id']?.toString();

    if (id == null) {
      return;
    }

    final current = schoolClass['is_active'] == true;

    try {
      await _service.setClassActive(id, !current);

      await _load();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openClass(Map<String, dynamic> schoolClass) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SchoolClassDetailPage(
          locale: widget.locale,
          schoolClass: schoolClass,
        ),
      ),
    );

    if (result == true && mounted) {
      await _load();
    }
  }

  String _yearLabel(Map<String, dynamic> year) {
    final label = year['label']?.toString() ?? '';

    if (year['is_current'] == true) {
      return '$label • ${_isFrench ? 'courante' : 'current'}';
    }

    return label;
  }

  String _subsystemLabel(String? value) {
    switch (value) {
      case 'francophone':
        return 'Francophone';
      case 'anglophone':
        return 'Anglophone';
      default:
        return value ?? '';
    }
  }

  String _sectorLabel(String? value) {
    switch (value) {
      case 'general':
        return _isFrench ? 'Général' : 'General';
      case 'technical':
        return _isFrench ? 'Technique' : 'Technical';
      default:
        return value ?? '';
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Salles de classe' : 'Classrooms',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: _isFrench ? 'Nouvelle année' : 'New academic year',
            onPressed: _createAcademicYear,
            icon: const Icon(Icons.event_note_rounded),
          ),
          IconButton(
            tooltip: _isFrench ? 'Nouvelle salle' : 'New classroom',
            onPressed: _createClass,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_years.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedYearId,
                  decoration: InputDecoration(
                    labelText: _isFrench ? 'Année scolaire' : 'Academic year',
                    border: const OutlineInputBorder(),
                  ),
                  items: _years.map((year) {
                    final id = year['id']?.toString();

                    if (id == null) {
                      return const DropdownMenuItem<String>(
                        value: '',
                        child: Text(''),
                      );
                    }

                    return DropdownMenuItem<String>(
                      value: id,
                      child: Text(_yearLabel(year)),
                    );
                  }).toList(),
                  onChanged: _loadClassesForYear,
                ),
              ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 56),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_isFrench ? 'Réessayer' : 'Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_classes.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isFrench
                              ? 'Aucune salle de classe pour cette année.'
                              : 'No classroom for this year.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final item = _classes[index];

                      final name = item['display_name']?.toString().trim();

                      final active = item['is_active'] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap: () => _openClass(item),
                          leading: CircleAvatar(
                            backgroundColor: active
                                ? const Color(0xFFDCFCE7)
                                : Colors.grey.shade200,
                            child: Icon(
                              Icons.meeting_room_rounded,
                              color: active
                                  ? const Color(0xFF166534)
                                  : Colors.grey,
                            ),
                          ),
                          title: Text(
                            name?.isNotEmpty == true
                                ? name!
                                : (item['name']?.toString() ?? ''),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Chip(
                                  label: Text(
                                    _subsystemLabel(
                                      item['subsystem']?.toString(),
                                    ),
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    _sectorLabel(item['sector']?.toString()),
                                  ),
                                ),
                                Chip(
                                  label: Text(active ? 'Active' : 'Inactive'),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch.adaptive(
                                value: active,
                                onChanged: (_) => _toggleClass(item),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
