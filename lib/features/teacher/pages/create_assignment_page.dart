import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/school_class.dart';
import 'create_assignment_questions_page.dart';

class CreateAssignmentPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const CreateAssignmentPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<CreateAssignmentPage> createState() => _CreateAssignmentPageState();
}

class _CreateAssignmentPageState extends State<CreateAssignmentPage> {
  final AssignmentService _service = AssignmentService();

  final _formKey = GlobalKey<FormState>();

  final _titleFrController = TextEditingController();
  final _titleEnController = TextEditingController();
  final _instructionsFrController = TextEditingController();
  final _instructionsEnController = TextEditingController();
  final _scoreController = TextEditingController(text: '20');

  final CourseService _courseService = CourseService();
  final LessonService _lessonService = LessonService();
  late Future<List<SchoolClass>> _classesFuture;
  List<Course> _courses = const [];
  List<Lesson> _lessons = const [];
  SchoolClass? _selectedClass;
  Course? _selectedCourse;
  Lesson? _selectedLesson;

  String _status = 'draft';
  DateTime? _dueAt;
  bool _saving = false;

  bool get _isEnglish => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _classesFuture = _courseService.listTeacherCompatibleClasses();
  }

  @override
  void dispose() {
    _titleFrController.dispose();
    _titleEnController.dispose();
    _instructionsFrController.dispose();
    _instructionsEnController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  Future<void> _saveAssignment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedClass == null || _selectedCourse == null) {
      _showMessage(_isEnglish ? 'Select the classroom and course first.' : 'Sélectionnez d’abord la salle et le cours.');
      return;
    }

    final maxScore = double.tryParse(_scoreController.text.trim());

    if (maxScore == null || maxScore <= 0) {
      _showMessage(
        _isEnglish
            ? 'Enter a valid maximum score.'
            : 'Entrez une note maximale valide.',
      );
      return;
    }

    try {
      setState(() {
        _saving = true;
      });

      final assignment = await _service.saveAssignment(
        courseId: _selectedCourse!.id,
        lessonId: _selectedLesson?.id,
        teacherId: widget.profile.id,
        classId: _selectedClass!.id,
        titleFr: _titleFrController.text.trim(),
        titleEn: _titleEnController.text.trim(),
        instructionsFr: _instructionsFrController.text.trim().isEmpty
            ? null
            : _instructionsFrController.text.trim(),
        instructionsEn: _instructionsEnController.text.trim().isEmpty
            ? null
            : _instructionsEnController.text.trim(),
        dueAt: _dueAt,
        status: _status,
        maxScore: maxScore,
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => CreateAssignmentQuestionsPage(
            locale: widget.locale,
            assignment: assignment,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish
                ? 'Assignment created successfully.'
                : 'Devoir créé avec succès.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish
                ? 'Unable to create the assignment.'
                : 'Impossible de créer le devoir.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _selectClass(SchoolClass? value) async {
    setState(() {
      _selectedClass = value;
      _selectedCourse = null;
      _selectedLesson = null;
      _courses = const [];
      _lessons = const [];
    });
    if (value == null) {
      return;
    }
    try {
      await _courseService.authorizeTeacherClasses([value.id]);
      final courses = await _courseService.listTeacherCourses(widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _courses = courses.where((c) => c.classId == value.id && c.status != 'archived').toList(growable: false);
      });
    } catch (error) {
      if (mounted) {
        _showMessage('${_isEnglish ? 'Unable to access this classroom' : 'Accès à cette salle impossible'}: $error');
      }
    }
  }

  Future<void> _selectCourse(Course? value) async {
    setState(() {
      _selectedCourse = value;
      _selectedLesson = null;
      _lessons = const [];
    });
    if (value == null) {
      return;
    }
    final lessons = await _lessonService.listAllLessons(value.id);
    if (!mounted) {
      return;
    }
    setState(() { _lessons = lessons; });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5, now.month, now.day),
      initialDate: _dueAt ?? now,
    );

    if (!mounted || pickedDate == null) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _dueAt != null
          ? TimeOfDay.fromDateTime(_dueAt!)
          : TimeOfDay.now(),
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    setState(() {
      _dueAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDueDate() {
    if (_dueAt == null) {
      return _isEnglish ? 'No deadline' : 'Aucune date limite';
    }

    final date = _dueAt!.toLocal();

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text(
          _isEnglish ? 'Create assignment' : 'Créer un devoir',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildLearningContextSection(),
            const SizedBox(height: 18),
            _buildTitlesSection(),
            const SizedBox(height: 18),
            _buildInstructionsSection(),
            const SizedBox(height: 18),
            _buildScoreField(),
            const SizedBox(height: 14),
            _buildDeadlineField(),
            const SizedBox(height: 14),
            _buildStatusSection(),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveAssignment,
                icon: _saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _isEnglish
                      ? 'Create and add questions'
                      : 'Créer et ajouter les questions',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF166534), Color(0xFF21844A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.assignment_add,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _isEnglish
                  ? 'Create an assignment, then add its questions.'
                  : 'Créez le devoir, puis ajoutez ses questions.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLearningContextSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isEnglish ? 'Learning location' : 'Emplacement pédagogique', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(_isEnglish ? 'Choose where students will find this activity. IDs are handled automatically.' : 'Choisissez où les élèves trouveront cette activité. Les identifiants sont gérés automatiquement.'),
        const SizedBox(height: 14),
        FutureBuilder<List<SchoolClass>>(
          future: _classesFuture,
          builder: (_, snapshot) => _dropdown<SchoolClass>(
            label: _isEnglish ? 'Classroom' : 'Salle de classe', value: _selectedClass,
            items: snapshot.data ?? const [], labelOf: (item) => item.displayName, onChanged: _selectClass,
          ),
        ),
        const SizedBox(height: 12),
        _dropdown<Course>(
          label: _isEnglish ? 'Course' : 'Cours', value: _selectedCourse, items: _courses,
          labelOf: (item) => item.labelFor(widget.locale.languageCode), onChanged: _selectCourse,
        ),
        const SizedBox(height: 12),
        _dropdown<Lesson>(
          label: _isEnglish ? 'Lesson (optional)' : 'Leçon (facultative)', value: _selectedLesson, items: _lessons,
          labelOf: (item) => item.labelFor(widget.locale.languageCode), onChanged: (value) => setState(() => _selectedLesson = value),
        ),
      ]),
    );
  }

  Widget _dropdown<T>({required String label, required T? value, required List<T> items, required String Function(T) labelOf, required ValueChanged<T?> onChanged}) {
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined), filled: true, fillColor: const Color(0xFFF7F9F8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
      items: items.map((item) => DropdownMenuItem<T>(value: item, child: Text(labelOf(item), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: items.isEmpty ? null : onChanged,
    );
  }

  Widget _buildTitlesSection() {
    return Column(
      children: [
        TextFormField(
          controller: _titleFrController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Titre français',
            prefixIcon: const Icon(Icons.title_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Le titre français est obligatoire.';
            }

            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _titleEnController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'English title',
            prefixIcon: const Icon(Icons.title_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'English title is required.';
            }

            return null;
          },
        ),
      ],
    );
  }

  Widget _buildInstructionsSection() {
    return Column(
      children: [
        TextFormField(
          controller: _instructionsFrController,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Consignes en français',
            alignLabelWithHint: true,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 58),
              child: Icon(Icons.description_outlined),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _instructionsEnController,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Instructions in English',
            alignLabelWithHint: true,
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 58),
              child: Icon(Icons.description_outlined),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreField() {
    return TextFormField(
      controller: _scoreController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _isEnglish ? 'Maximum score' : 'Note maximale',
        prefixIcon: const Icon(Icons.grade_rounded),
        suffixText: 'pts',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (value) {
        final parsed = double.tryParse(value?.trim() ?? '');

        if (parsed == null || parsed <= 0) {
          return _isEnglish
              ? 'Enter a valid score.'
              : 'Entrez une note valide.';
        }

        return null;
      },
    );
  }

  Widget _buildDeadlineField() {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _pickDueDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _isEnglish ? 'Deadline' : 'Date limite',
          prefixIcon: const Icon(Icons.event_rounded),
          suffixIcon: _dueAt == null
              ? const Icon(Icons.calendar_month_rounded)
              : IconButton(
                  onPressed: () {
                    setState(() {
                      _dueAt = null;
                    });
                  },
                  icon: const Icon(Icons.clear_rounded),
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          _formatDueDate(),
          style: TextStyle(
            color: _dueAt == null ? Colors.black45 : Colors.black87,
            fontWeight: _dueAt == null ? FontWeight.normal : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEnglish ? 'Publication status' : 'Statut de publication',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _status,
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _status = value;
              });
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'draft',
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF166534),
                  title: Text(_isEnglish ? 'Draft' : 'Brouillon'),
                  subtitle: Text(
                    _isEnglish
                        ? 'Add questions before publishing.'
                        : 'Ajoutez les questions avant de publier.',
                  ),
                ),
                RadioListTile<String>(
                  value: 'published',
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF166534),
                  title: Text(_isEnglish ? 'Published' : 'Publié'),
                  subtitle: Text(
                    _isEnglish
                        ? 'Students can access it.'
                        : 'Les élèves pourront y accéder.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
