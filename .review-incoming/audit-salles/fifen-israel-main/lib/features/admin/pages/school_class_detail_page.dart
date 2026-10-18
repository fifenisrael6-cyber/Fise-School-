import 'package:flutter/material.dart';

import '../../../core/services/school_class_service.dart';

class SchoolClassDetailPage extends StatefulWidget {
  final Locale locale;
  final Map<String, dynamic> schoolClass;

  const SchoolClassDetailPage({
    super.key,
    required this.locale,
    required this.schoolClass,
  });

  @override
  State<SchoolClassDetailPage> createState() => _SchoolClassDetailPageState();
}

class _SchoolClassDetailPageState extends State<SchoolClassDetailPage>
    with SingleTickerProviderStateMixin {
  final SchoolClassService _service = SchoolClassService();

  late TabController _tabController;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _availableStudents = [];
  List<Map<String, dynamic>> _availableTeachers = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _availableSubjects = [];

  bool get isFrench => widget.locale.languageCode == 'fr';

  String get classId => widget.schoolClass['id'] as String;

  String get classDisplayName =>
      (widget.schoolClass['display_name'] ?? '') as String;

  String get className => (widget.schoolClass['name'] ?? '') as String;

  String get subsystem => (widget.schoolClass['subsystem'] ?? '') as String;

  String get sector => (widget.schoolClass['sector'] ?? '') as String;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.listClassStudents(classId),
        _service.listClassTeachers(classId),
        _service.listStudents(),
        _service.listTeachers(),
        _service.listClassSubjects(classId),
        _service.listAvailableSubjectsForClass(
          classId: classId,
          subsystem: subsystem,
          sector: sector,
        ),
      ]);

      final students = List<Map<String, dynamic>>.from(results[0] as List);

      final teachers = List<Map<String, dynamic>>.from(results[1] as List);

      final allStudents = List<Map<String, dynamic>>.from(results[2] as List);

      final allTeachers = List<Map<String, dynamic>>.from(results[3] as List);
      final subjects = List<Map<String, dynamic>>.from(results[4] as List);
      final availableSubjects = List<Map<String, dynamic>>.from(results[5] as List);

      final assignedStudentIds = students
          .map((item) => item['student_id'] as String)
          .toSet();

      final assignedTeacherIds = teachers
          .map((item) => item['teacher_id'] as String)
          .toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _students = students;
        _teachers = teachers;

        _availableStudents = allStudents.where((student) {
          final id = student['id'] as String?;
          return id != null && !assignedStudentIds.contains(id);
        }).toList();

        _availableTeachers = allTeachers.where((teacher) {
          final id = teacher['id'] as String?;
          return id != null && !assignedTeacherIds.contains(id);
        }).toList();
        _subjects = subjects;
        _availableSubjects = availableSubjects;

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

  Future<void> _assignStudent(Map<String, dynamic> student) async {
    final studentId = student['id'] as String?;

    if (studentId == null) {
      return;
    }

    try {
      await _service.assignStudent(classId: classId, studentId: studentId);

      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFrench
                ? 'Élève ajouté à la classe.'
                : 'Student added to the class.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString());
    }
  }

  Future<void> _removeStudent(Map<String, dynamic> membership) async {
    final studentId = membership['student_id'] as String?;

    if (studentId == null) {
      return;
    }

    final profile = membership['profiles'] is Map
        ? Map<String, dynamic>.from(membership['profiles'] as Map)
        : <String, dynamic>{};

    final name = _fullName(profile);

    final confirmed = await _confirm(
      title: isFrench ? 'Retirer l’élève' : 'Remove student',
      message: isFrench
          ? 'Retirer $name de cette classe ?'
          : 'Remove $name from this class?',
    );

    if (!confirmed) {
      return;
    }

    try {
      await _service.removeStudent(classId: classId, studentId: studentId);

      await _loadData();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString());
    }
  }

  Future<void> _assignTeacher(Map<String, dynamic> teacher) async {
    final teacherId = teacher['id'] as String?;

    if (teacherId == null) {
      return;
    }

    try {
      await _service.assignTeacher(classId: classId, teacherId: teacherId);

      await _loadData();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFrench
                ? 'Enseignant affecté à la classe.'
                : 'Teacher assigned to the class.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString());
    }
  }

  Future<void> _removeTeacher(Map<String, dynamic> assignment) async {
    final teacherId = assignment['teacher_id'] as String?;

    if (teacherId == null) {
      return;
    }

    final profile = assignment['profiles'] is Map
        ? Map<String, dynamic>.from(assignment['profiles'] as Map)
        : <String, dynamic>{};

    final name = _fullName(profile);

    final confirmed = await _confirm(
      title: isFrench ? 'Retirer l’enseignant' : 'Remove teacher',
      message: isFrench
          ? 'Retirer $name de cette classe ?'
          : 'Remove $name from this class?',
    );

    if (!confirmed) {
      return;
    }

    try {
      await _service.removeTeacher(classId: classId, teacherId: teacherId);

      await _loadData();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString());
    }
  }

  String _subjectName(Map<String, dynamic> subject) {
    return isFrench
        ? (subject['name_fr'] ?? subject['name_en'] ?? '').toString()
        : (subject['name_en'] ?? subject['name_fr'] ?? '').toString();
  }

  Future<void> _assignSubject(Map<String, dynamic> subject) async {
    final subjectId = subject['id']?.toString();
    if (subjectId == null) {
      return;
    }
    try {
      await _service.assignSubjectToClass(
        classId: classId,
        subjectId: subjectId,
        position: _subjects.length,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    }
  }

  Future<void> _removeSubject(Map<String, dynamic> membership) async {
    final id = membership['id']?.toString();
    if (id == null) {
      return;
    }
    final confirmed = await _confirm(
      title: isFrench ? 'Retirer la matière' : 'Remove subject',
      message: isFrench
          ? 'Retirer ${_subjectName(Map<String, dynamic>.from(membership['subjects'] as Map))} de cette salle ?'
          : 'Remove ${_subjectName(Map<String, dynamic>.from(membership['subjects'] as Map))} from this classroom?',
    );
    if (!confirmed) {
      return;
    }
    try {
      await _service.removeSubjectFromClass(id);
      await _loadData();
    } catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    }
  }

  Future<void> _openAddSubjectDialog() async {
    if (_availableSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isFrench ? 'Toutes les matières compatibles sont déjà dans cette salle.' : 'All compatible subjects are already assigned to this classroom.'),
      ));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _availableSubjects.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final subject = _availableSubjects[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.menu_book_rounded)),
              title: Text(_subjectName(subject)),
              subtitle: Text(subject['code']?.toString() ?? ''),
              trailing: const Icon(Icons.add_circle_rounded, color: Color(0xFF166534)),
              onTap: () async {
                Navigator.pop(context);
                await _assignSubject(subject);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSubjectsTab() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _subjects.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 60),
                    const Icon(Icons.menu_book_outlined, size: 70, color: Colors.grey),
                    const SizedBox(height: 14),
                    Text(
                      isFrench ? 'Aucune matière n’est encore affectée à cette salle.' : 'No subject has been assigned to this classroom yet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 80),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _subjects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final membership = _subjects[index];
                    final subject = membership['subjects'] is Map
                        ? Map<String, dynamic>.from(membership['subjects'] as Map)
                        : <String, dynamic>{};
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFDCFCE7),
                          child: Icon(Icons.menu_book_rounded, color: Color(0xFF166534)),
                        ),
                        title: Text(_subjectName(subject), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(subject['code']?.toString() ?? ''),
                        trailing: IconButton(
                          tooltip: isFrench ? 'Retirer' : 'Remove',
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () => _removeSubject(membership),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _openAddSubjectDialog,
            backgroundColor: const Color(0xFF166534),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text(isFrench ? 'Ajouter une matière' : 'Add subject'),
          ),
        ),
      ],
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isFrench ? 'Confirmer' : 'Confirm'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _fullName(Map<String, dynamic> profile) {
    final firstName = (profile['first_name'] ?? '').toString().trim();

    final lastName = (profile['last_name'] ?? '').toString().trim();

    return '$firstName $lastName'.trim();
  }

  String _subsystemLabel(String value) {
    if (value == 'francophone') {
      return isFrench ? 'Francophone' : 'Francophone';
    }

    if (value == 'anglophone') {
      return isFrench ? 'Anglophone' : 'Anglophone';
    }

    return value;
  }

  String _sectorLabel(String value) {
    if (value == 'general') {
      return isFrench ? 'Général' : 'General';
    }

    if (value == 'technical') {
      return isFrench ? 'Technique' : 'Technical';
    }

    return value;
  }

  void _openAddStudentDialog() {
    if (_availableStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFrench
                ? 'Aucun autre élève disponible.'
                : 'No other student is available.',
          ),
        ),
      );

      return;
    }

    final filteredStudents = List<Map<String, dynamic>>.from(
      _availableStudents,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final searchController = TextEditingController();

            List<Map<String, dynamic>> visibleStudents =
                List<Map<String, dynamic>>.from(filteredStudents);

            return AlertDialog(
              title: Text(isFrench ? 'Ajouter un élève' : 'Add student'),
              content: SizedBox(
                width: 520,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: isFrench ? 'Rechercher' : 'Search',
                      ),
                      onChanged: (value) {
                        final query = value.trim().toLowerCase();

                        setDialogState(() {
                          visibleStudents = filteredStudents.where((student) {
                            final name = _fullName(student).toLowerCase();

                            final email = (student['email'] ?? '')
                                .toString()
                                .toLowerCase();

                            return name.contains(query) ||
                                email.contains(query);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visibleStudents.isEmpty
                          ? Center(
                              child: Text(
                                isFrench ? 'Aucun résultat.' : 'No result.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: visibleStudents.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final student = visibleStudents[index];

                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_rounded),
                                  ),
                                  title: Text(_fullName(student)),
                                  subtitle: Text(
                                    student['email']?.toString() ??
                                        '',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_rounded,
                                      color: Color(0xFF166534),
                                    ),
                                    onPressed: () async {
                                      Navigator.pop(dialogContext);

                                      await _assignStudent(student);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: Text(isFrench ? 'Fermer' : 'Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openAddTeacherDialog() {
    if (_availableTeachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFrench
                ? 'Aucun autre enseignant disponible.'
                : 'No other teacher is available.',
          ),
        ),
      );

      return;
    }

    final filteredTeachers = List<Map<String, dynamic>>.from(
      _availableTeachers,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final searchController = TextEditingController();

            List<Map<String, dynamic>> visibleTeachers =
                List<Map<String, dynamic>>.from(filteredTeachers);

            return AlertDialog(
              title: Text(
                isFrench ? 'Affecter un enseignant' : 'Assign teacher',
              ),
              content: SizedBox(
                width: 520,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: isFrench ? 'Rechercher' : 'Search',
                      ),
                      onChanged: (value) {
                        final query = value.trim().toLowerCase();

                        setDialogState(() {
                          visibleTeachers = filteredTeachers.where((teacher) {
                            final name = _fullName(teacher).toLowerCase();

                            final email = (teacher['email'] ?? '')
                                .toString()
                                .toLowerCase();

                            return name.contains(query) ||
                                email.contains(query);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visibleTeachers.isEmpty
                          ? Center(
                              child: Text(
                                isFrench ? 'Aucun résultat.' : 'No result.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: visibleTeachers.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final teacher = visibleTeachers[index];

                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_rounded),
                                  ),
                                  title: Text(_fullName(teacher)),
                                  subtitle: Text(
                                    teacher['email']?.toString() ??
                                        '',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_rounded,
                                      color: Color(0xFF166534),
                                    ),
                                    onPressed: () async {
                                      Navigator.pop(dialogContext);

                                      await _assignTeacher(teacher);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: Text(isFrench ? 'Fermer' : 'Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF064D2B),
        foregroundColor: Colors.white,
        title: Text(classDisplayName.isEmpty ? className : classDisplayName),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              icon: const Icon(Icons.school_rounded),
              text: isFrench ? 'Élèves' : 'Students',
            ),
            Tab(
              icon: const Icon(Icons.person_rounded),
              text: isFrench ? 'Enseignants' : 'Teachers',
            ),
            Tab(
              icon: const Icon(Icons.menu_book_rounded),
              text: isFrench ? 'Matières' : 'Subjects',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildError()
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildStudentsTab(), _buildTeachersTab(), _buildSubjectsTab()],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final isActive = widget.schoolClass['is_active'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFF0FDF4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: const Icon(Icons.language_rounded, size: 18),
            label: Text(_subsystemLabel(subsystem)),
          ),
          Chip(
            avatar: const Icon(Icons.category_rounded, size: 18),
            label: Text(_sectorLabel(sector)),
          ),
          Chip(
            avatar: Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.pause_circle_rounded,
              size: 18,
            ),
            label: Text(
              isActive
                  ? (isFrench ? 'Active' : 'Active')
                  : (isFrench ? 'Inactive' : 'Inactive'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _students.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 80),
                    Icon(
                      Icons.school_outlined,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        isFrench
                            ? 'Aucun élève dans cette classe.'
                            : 'No student in this class.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _students.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final membership = _students[index];

                    final profile = membership['profiles'] is Map
                        ? Map<String, dynamic>.from(
                            membership['profiles'] as Map,
                          )
                        : <String, dynamic>{};

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFDCFCE7),
                          child: Icon(
                            Icons.person_rounded,
                            color: Color(0xFF166534),
                          ),
                        ),
                        title: Text(
                          _fullName(profile),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          profile['email']?.toString() ??
                              '',
                        ),
                        trailing: IconButton(
                          tooltip: isFrench ? 'Retirer' : 'Remove',
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeStudent(membership),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _openAddStudentDialog,
            backgroundColor: const Color(0xFF166534),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.person_add_rounded),
            label: Text(isFrench ? 'Ajouter' : 'Add'),
          ),
        ),
      ],
    );
  }

  Widget _buildTeachersTab() {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: _teachers.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 80),
                    Icon(
                      Icons.groups_outlined,
                      size: 72,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        isFrench
                            ? 'Aucun enseignant affecté à cette classe.'
                            : 'No teacher assigned to this class.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _teachers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final assignment = _teachers[index];

                    final profile = assignment['profiles'] is Map
                        ? Map<String, dynamic>.from(
                            assignment['profiles'] as Map,
                          )
                        : <String, dynamic>{};

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFDCFCE7),
                          child: Icon(
                            Icons.person_rounded,
                            color: Color(0xFF166534),
                          ),
                        ),
                        title: Text(
                          _fullName(profile),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          profile['email']?.toString() ??
                              '',
                        ),
                        trailing: IconButton(
                          tooltip: isFrench ? 'Retirer' : 'Remove',
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeTeacher(assignment),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: FloatingActionButton.extended(
            onPressed: _openAddTeacherDialog,
            backgroundColor: const Color(0xFF166534),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(isFrench ? 'Affecter' : 'Assign'),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              isFrench
                  ? 'Impossible de charger cette classe.'
                  : 'Unable to load this class.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isFrench ? 'Réessayer' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
