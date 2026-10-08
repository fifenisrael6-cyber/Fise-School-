import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/pedagogy_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';
import 'teacher_resource_page.dart';

class CreateLessonPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;
  final Lesson? lesson;

  const CreateLessonPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
    this.lesson,
  });

  bool get isEditing => lesson != null;

  @override
  State<CreateLessonPage> createState() => _CreateLessonPageState();
}

class _CreateLessonPageState extends State<CreateLessonPage> {
  final LessonService _service = LessonService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleFrController;
  late final TextEditingController _titleEnController;
  late final TextEditingController _contentFrController;
  late final TextEditingController _contentEnController;
  late final TextEditingController _objectivesFrController;
  late final TextEditingController _objectivesEnController;
  late final TextEditingController _examplesFrController;
  late final TextEditingController _examplesEnController;
  late final TextEditingController _summaryFrController;
  late final TextEditingController _summaryEnController;
  late final TextEditingController _minutesController;

  late bool _published;

  bool _saving = false;
  bool _deleting = false;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();

    final lesson = widget.lesson;

    _titleFrController = TextEditingController(text: lesson?.titleFr ?? '');
    _titleEnController = TextEditingController(text: lesson?.titleEn ?? '');
    _contentFrController = TextEditingController(text: lesson?.contentFr ?? '');
    _contentEnController = TextEditingController(text: lesson?.contentEn ?? '');
    _objectivesFrController = TextEditingController(
      text: lesson?.objectivesFr ?? '',
    );
    _objectivesEnController = TextEditingController(
      text: lesson?.objectivesEn ?? '',
    );
    _examplesFrController = TextEditingController(
      text: lesson?.examplesFr ?? '',
    );
    _examplesEnController = TextEditingController(
      text: lesson?.examplesEn ?? '',
    );
    _summaryFrController = TextEditingController(text: lesson?.summaryFr ?? '');
    _summaryEnController = TextEditingController(text: lesson?.summaryEn ?? '');
    _minutesController = TextEditingController(
      text: '${lesson?.estimatedMinutes ?? 15}',
    );

    _published = lesson?.isPublished ?? false;
  }

  @override
  void dispose() {
    _titleFrController.dispose();
    _titleEnController.dispose();
    _contentFrController.dispose();
    _contentEnController.dispose();
    _objectivesFrController.dispose();
    _objectivesEnController.dispose();
    _examplesFrController.dispose();
    _examplesEnController.dispose();
    _summaryFrController.dispose();
    _summaryEnController.dispose();
    _minutesController.dispose();

    super.dispose();
  }

  Future<void> _saveLesson() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final minutes = int.tryParse(_minutesController.text.trim());

    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Veuillez entrer une durée valide.'
                : 'Please enter a valid duration.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      int position;

      if (widget.lesson != null) {
        position = widget.lesson!.position;
      } else {
        final lessons = await _service.listAllLessons(widget.course.id);
        position = lessons.length + 1;
      }

      final lesson = await _service.saveLesson(
        id: widget.lesson?.id,
        courseId: widget.course.id,
        titleFr: _titleFrController.text,
        titleEn: _titleEnController.text,
        contentFr: _contentFrController.text,
        contentEn: _contentEnController.text,
        objectivesFr: _objectivesFrController.text,
        objectivesEn: _objectivesEnController.text,
        examplesFr: _examplesFrController.text,
        examplesEn: _examplesEnController.text,
        summaryFr: _summaryFrController.text,
        summaryEn: _summaryEnController.text,
        position: position,
        durationMinutes: minutes,
        estimatedMinutes: minutes,
        isPublished: _published,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TeacherResourcePage(
            locale: widget.locale,
            profile: widget.profile,
            course: widget.course,
            lesson: lesson,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? (_isFrench
                      ? 'Leçon modifiée avec succès.'
                      : 'Lesson updated successfully.')
                : (_isFrench
                      ? 'Leçon enregistrée avec succès.'
                      : 'Lesson saved successfully.'),
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppTexts(widget.locale).courseSaveError}\n$error'),
        ),
      );
    }
  }

  Future<void> _deleteLesson() async {
    final lesson = widget.lesson;

    if (lesson == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_isFrench ? 'Supprimer la leçon' : 'Delete lesson'),
          content: Text(
            _isFrench
                ? 'Voulez-vous vraiment supprimer cette leçon ? Cette action est définitive.'
                : 'Do you really want to delete this lesson? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(_isFrench ? 'Supprimer' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      await _service.deleteLesson(lesson.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFrench ? 'Leçon supprimée.' : 'Lesson deleted.'),
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppTexts(widget.locale).courseSaveError}\n$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? (_isFrench ? 'Modifier la leçon' : 'Edit lesson')
              : (_isFrench ? 'Nouvelle leçon' : 'New lesson'),
        ),
        actions: [
          if (widget.isEditing)
            IconButton(
              onPressed: (_saving || _deleting) ? null : _deleteLesson,
              tooltip: _isFrench ? 'Supprimer' : 'Delete',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFrench ? 'Cours' : 'Course',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.course.labelFor(widget.locale.languageCode),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                _isFrench
                    ? r'Astuce de mise en forme : « ## Titre » pour un sous-titre (ex. ## Définitions importantes, ## Formules, ## Exercices), « **mot** » pour le gras, « - » pour une liste, et les formules entre $...$ (ex. $x^2+1$) ou $$...$$ pour une formule centrée.'
                    : r'Formatting tip: "## Title" for a heading (e.g. ## Key definitions, ## Formulas, ## Exercises), "**word**" for bold, "-" for a list, and formulas between $...$ (e.g. $x^2+1$) or $$...$$ for a centred formula.',
                style: const TextStyle(height: 1.4, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            _field(controller: _titleFrController, label: 'Titre français'),
            _field(controller: _titleEnController, label: 'English title'),
            _field(
              controller: _contentFrController,
              label: 'Contenu français',
              maxLines: 8,
            ),
            _field(
              controller: _contentEnController,
              label: 'English content',
              maxLines: 8,
            ),
            _field(
              controller: _objectivesFrController,
              label: 'Objectifs',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _objectivesEnController,
              label: 'Objectives',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _examplesFrController,
              label: 'Exemples',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _examplesEnController,
              label: 'Examples',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _summaryFrController,
              label: 'Résumé',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _summaryEnController,
              label: 'Summary',
              required: false,
              maxLines: 5,
            ),
            _field(
              controller: _minutesController,
              label: _isFrench
                  ? 'Durée estimée (minutes)'
                  : 'Estimated duration (minutes)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _isFrench ? 'Publier cette leçon' : 'Publish this lesson',
              ),
              subtitle: Text(
                _published
                    ? (_isFrench
                          ? 'La leçon sera visible par les élèves.'
                          : 'The lesson will be visible to students.')
                    : (_isFrench
                          ? 'La leçon restera en brouillon.'
                          : 'The lesson will remain a draft.'),
              ),
              value: _published,
              onChanged: (_saving || _deleting)
                  ? null
                  : (value) {
                      setState(() {
                        _published = value;
                      });
                    },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: (_saving || _deleting) ? null : _saveLesson,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                widget.isEditing
                    ? (_isFrench
                          ? 'Enregistrer les modifications'
                          : 'Save changes')
                    : (_isFrench ? 'Enregistrer la leçon' : 'Save lesson'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool required = true,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return AppTexts(widget.locale).requiredField;
                }

                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
