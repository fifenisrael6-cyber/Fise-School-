import 'package:flutter/material.dart';

import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';

class CreateAssignmentQuestionsPage extends StatefulWidget {
  final Locale locale;
  final Assignment assignment;

  const CreateAssignmentQuestionsPage({
    super.key,
    required this.locale,
    required this.assignment,
  });

  @override
  State<CreateAssignmentQuestionsPage> createState() =>
      _CreateAssignmentQuestionsPageState();
}

class _CreateAssignmentQuestionsPageState
    extends State<CreateAssignmentQuestionsPage> {
  final AssignmentService _service = AssignmentService();

  late Future<List<AssignmentQuestion>> _questionsFuture;

  bool get _isEnglish => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  void _loadQuestions() {
    _questionsFuture = _service.listQuestions(widget.assignment.id);
  }

  Future<void> _refresh() async {
    setState(_loadQuestions);
    await _questionsFuture;
  }

  Future<void> _openQuestionForm({AssignmentQuestion? question}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _QuestionFormSheet(
          locale: widget.locale,
          assignment: widget.assignment,
          question: question,
          service: _service,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (result == true) {
      setState(_loadQuestions);
    }
  }

  Future<void> _deleteQuestion(AssignmentQuestion question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _isEnglish ? 'Delete question?' : 'Supprimer la question ?',
          ),
          content: Text(
            _isEnglish
                ? 'This question will be permanently removed.'
                : 'Cette question sera définitivement supprimée.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(_isEnglish ? 'Cancel' : 'Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(_isEnglish ? 'Delete' : 'Supprimer'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await _service.deleteQuestion(question.id);

      if (!mounted) {
        return;
      }

      setState(_loadQuestions);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish ? 'Question deleted.' : 'Question supprimée.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish
                ? 'Unable to delete the question.'
                : 'Impossible de supprimer la question.',
          ),
        ),
      );
    }
  }

  String _questionTypeLabel(String type) {
    switch (type) {
      case 'qcm':
        return _isEnglish ? 'Multiple choice' : 'QCM';
      case 'true_false':
        return _isEnglish ? 'True / False' : 'Vrai / Faux';
      case 'short_answer':
        return _isEnglish ? 'Short answer' : 'Réponse courte';
      default:
        return _isEnglish ? 'Long answer' : 'Réponse libre';
    }
  }

  String _questionPreview(AssignmentQuestion question) {
    final text = question.questionFor(widget.locale).trim();

    if (text.length <= 110) {
      return text;
    }

    return '${text.substring(0, 110)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text(
          _isEnglish ? 'Assignment questions' : 'Questions du devoir',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        onPressed: () => _openQuestionForm(),
        icon: const Icon(Icons.add_rounded),
        label: Text(_isEnglish ? 'Add question' : 'Ajouter une question'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AssignmentQuestion>>(
          future: _questionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF166534)),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isEnglish
                        ? 'Unable to load questions.'
                        : 'Impossible de charger les questions.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_isEnglish ? 'Retry' : 'Réessayer'),
                    ),
                  ),
                ],
              );
            }

            final questions = snapshot.data ?? const <AssignmentQuestion>[];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                _buildAssignmentHeader(),
                const SizedBox(height: 18),
                if (questions.isEmpty)
                  _buildEmptyState()
                else
                  ...List.generate(
                    questions.length,
                    (index) => _buildQuestionCard(questions[index], index),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAssignmentHeader() {
    final title = widget.assignment.titleFor(widget.locale);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _isEnglish ? 'Build the questions that students will answer.' : 'Ajoutez les questions auxquelles les élèves devront répondre.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(AssignmentQuestion question, int index) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F2E9),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _questionPreview(question),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildSmallChip(
                  Icons.help_outline_rounded,
                  _questionTypeLabel(question.questionType),
                ),
                _buildSmallChip(
                  Icons.grade_rounded,
                  '${question.points.toStringAsFixed(0)} pts',
                ),
                if (question.options.isNotEmpty)
                  _buildSmallChip(
                    Icons.list_rounded,
                    _isEnglish
                        ? '${question.options.length} options'
                        : '${question.options.length} options',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openQuestionForm(question: question),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(_isEnglish ? 'Edit' : 'Modifier'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: _isEnglish ? 'Delete' : 'Supprimer',
                  onPressed: () => _deleteQuestion(question),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Colors.redAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 0),
          Icon(icon, size: 15, color: const Color(0xFF166534)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.quiz_outlined, size: 62, color: Colors.grey),
          const SizedBox(height: 14),
          Text(
            _isEnglish ? 'No questions yet' : 'Aucune question pour le moment',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _isEnglish
                ? 'Add the first question to this assignment.'
                : 'Ajoutez la première question à ce devoir.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _openQuestionForm(),
            icon: const Icon(Icons.add_rounded),
            label: Text(_isEnglish ? 'Add question' : 'Ajouter une question'),
          ),
        ],
      ),
    );
  }
}

class _QuestionFormSheet extends StatefulWidget {
  final Locale locale;
  final Assignment assignment;
  final AssignmentQuestion? question;
  final AssignmentService service;

  const _QuestionFormSheet({
    required this.locale,
    required this.assignment,
    required this.question,
    required this.service,
  });

  @override
  State<_QuestionFormSheet> createState() => _QuestionFormSheetState();
}

class _QuestionFormSheetState extends State<_QuestionFormSheet> {
  final _formKey = GlobalKey<FormState>();

  final _questionFrController = TextEditingController();
  final _questionEnController = TextEditingController();
  final _pointsController = TextEditingController(text: '1');

  final List<TextEditingController> _optionControllers = [];

  String _questionType = 'text';
  String? _correctAnswer;

  bool _saving = false;

  bool get _isEnglish => widget.locale.languageCode == 'en';

  bool get _isEditing => widget.question != null;

  @override
  void initState() {
    super.initState();

    final question = widget.question;

    if (question != null) {
      _questionFrController.text = question.questionFr;
      _questionEnController.text = question.questionEn;
      _pointsController.text = _formatNumber(question.points);
      _questionType = question.questionType;

      for (final option in question.options) {
        _optionControllers.add(TextEditingController(text: option));
      }

      _correctAnswer = question.correctAnswer;
    }

    if (_questionType == 'qcm' && _optionControllers.isEmpty) {
      _addOption();
      _addOption();
    }

    if (_questionType == 'true_false') {
      _setupTrueFalseOptions();
    }
  }

  @override
  void dispose() {
    _questionFrController.dispose();
    _questionEnController.dispose();
    _pointsController.dispose();

    for (final controller in _optionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toString();
  }

  void _setupTrueFalseOptions() {
    for (final controller in _optionControllers) {
      controller.dispose();
    }

    _optionControllers
      ..clear()
      ..add(TextEditingController(text: 'true'))
      ..add(TextEditingController(text: 'false'));

    if (_correctAnswer != 'true' && _correctAnswer != 'false') {
      _correctAnswer = null;
    }
  }

  void _clearOptions() {
    for (final controller in _optionControllers) {
      controller.dispose();
    }

    _optionControllers.clear();
    _correctAnswer = null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final points = double.tryParse(_pointsController.text.trim());

    if (points == null || points <= 0) {
      _showMessage(
        _isEnglish
            ? 'Enter a valid number of points.'
            : 'Entrez un nombre de points valide.',
      );
      return;
    }

    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (_questionType == 'qcm' && options.length < 2) {
      _showMessage(
        _isEnglish
            ? 'A multiple-choice question needs at least two options.'
            : 'Un QCM doit avoir au moins deux options.',
      );
      return;
    }

    if (_questionType == 'qcm' || _questionType == 'true_false') {
      if (_correctAnswer == null || !options.contains(_correctAnswer)) {
        _showMessage(
          _isEnglish
              ? 'Please select the correct answer.'
              : 'Veuillez sélectionner la bonne réponse.',
        );
        return;
      }
    }

    try {
      setState(() {
        _saving = true;
      });

      final existingQuestions = await widget.service.listQuestions(
        widget.assignment.id,
      );

      if (!mounted) {
        return;
      }

      final position =
          widget.question?.position ?? existingQuestions.length + 1;

      await widget.service.saveQuestion(
        id: widget.question?.id,
        assignmentId: widget.assignment.id,
        position: position,
        questionFr: _questionFrController.text.trim(),
        questionEn: _questionEnController.text.trim(),
        questionType: _questionType,
        points: points,
        options: options,
        correctAnswer: _questionType == 'qcm' || _questionType == 'true_false'
            ? _correctAnswer
            : null,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      _showMessage(
        _isEnglish
            ? 'Unable to save the question.'
            : 'Impossible d’enregistrer la question.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      return;
    }

    final controller = _optionControllers.removeAt(index);

    if (_correctAnswer == controller.text.trim()) {
      _correctAnswer = null;
    }

    controller.dispose();

    setState(() {});
  }

  Widget _buildCorrectAnswerSection() {
    if (_questionType == 'text' || _questionType == 'short_answer') {
      return const SizedBox.shrink();
    }

    if (_questionType == 'true_false') {
      return _buildCorrectAnswerDropdown(options: const ['true', 'false']);
    }

    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildCorrectAnswerDropdown(options: options);
  }

  Widget _buildCorrectAnswerDropdown({required List<String> options}) {
    final currentValue = options.contains(_correctAnswer)
        ? _correctAnswer
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: currentValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _isEnglish ? 'Correct answer' : 'Bonne réponse',
            prefixIcon: const Icon(Icons.check_circle_outline_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          items: options.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;

            final displayOption = _questionType == 'qcm'
                ? '${String.fromCharCode(65 + index)}. $option'
                : option == 'true'
                ? (_isEnglish ? 'True' : 'Vrai')
                : (_isEnglish ? 'False' : 'Faux');

            return DropdownMenuItem<String>(
              value: option,
              child: Text(displayOption, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _correctAnswer = value;
            });
          },
        ),
        const SizedBox(height: 6),
        Text(
          _isEnglish
              ? 'This answer will be stored as the correct answer.'
              : 'Cette réponse sera enregistrée comme bonne réponse.',
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F8F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _isEditing
                      ? (_isEnglish ? 'Edit question' : 'Modifier la question')
                      : (_isEnglish ? 'New question' : 'Nouvelle question'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                _buildQuestionField(
                  controller: _questionFrController,
                  label: 'Question en français',
                  icon: Icons.translate_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La question française est obligatoire.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildQuestionField(
                  controller: _questionEnController,
                  label: 'Question in English',
                  icon: Icons.translate_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'The English question is required.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _questionType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _isEnglish
                        ? 'Question type'
                        : 'Type de question',
                    prefixIcon: const Icon(Icons.category_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'text',
                      child: Text('Réponse libre / Long answer'),
                    ),
                    DropdownMenuItem(
                      value: 'short_answer',
                      child: Text('Réponse courte / Short answer'),
                    ),
                    DropdownMenuItem(
                      value: 'qcm',
                      child: Text('QCM / Multiple choice'),
                    ),
                    DropdownMenuItem(
                      value: 'true_false',
                      child: Text('Vrai/Faux / True-False'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _questionType = value;
                    });

                    if (value == 'qcm') {
                      if (_optionControllers.isEmpty) {
                        _addOption();
                        _addOption();
                      }
                    } else if (value == 'true_false') {
                      setState(_setupTrueFalseOptions);
                    } else {
                      setState(_clearOptions);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pointsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _isEnglish ? 'Points' : 'Points',
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
                          ? 'Enter a valid number.'
                          : 'Entrez un nombre valide.';
                    }

                    return null;
                  },
                ),
                if (_questionType == 'qcm') ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEnglish ? 'Answer options' : 'Options de réponse',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addOption,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(_isEnglish ? 'Add' : 'Ajouter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_optionControllers.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4F2E9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              String.fromCharCode(65 + index),
                              style: const TextStyle(
                                color: Color(0xFF166534),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _optionControllers[index],
                              onChanged: (_) {
                                setState(() {});
                              },
                              decoration: InputDecoration(
                                labelText:
                                    '${_isEnglish ? 'Option' : 'Option'} ${index + 1}',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(13),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          IconButton(
                            onPressed: _optionControllers.length > 2
                                ? () => _removeOption(index)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: Colors.redAccent,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (_questionType == 'true_false') ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.rule_rounded,
                          color: Color(0xFF166534),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isEnglish
                                ? 'The options are True and False.'
                                : 'Les réponses sont Vrai et Faux.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildCorrectAnswerSection(),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _isEditing
                          ? (_isEnglish
                                ? 'Save changes'
                                : 'Enregistrer les modifications')
                          : (_isEnglish
                                ? 'Add question'
                                : 'Ajouter la question'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 7,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 50),
          child: Icon(icon),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
      validator: validator,
    );
  }
}
