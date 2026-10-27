import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/offline/offline_repository.dart';
import '../../../core/services/assignment_service.dart';
import '../../../models/assignment.dart';
import '../../../models/user_profile.dart';

class AssignmentDetailPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Assignment assignment;

  const AssignmentDetailPage({
    super.key,
    required this.locale,
    required this.profile,
    required this.assignment,
  });

  @override
  State<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends State<AssignmentDetailPage> {
  final AssignmentService _service = AssignmentService();
  final OfflineRepository _offline = OfflineRepository();

  late Future<List<AssignmentQuestion>> _questionsFuture;

  AssignmentSubmission? _submission;

  final Map<String, TextEditingController> _answerControllers = {};
  final Map<String, String?> _selectedAnswers = {};
  final Map<String, Map<String, dynamic>> _qcmFeedback = {};
  final Set<String> _qcmChecking = <String>{};

  bool _loadingSubmission = true;
  bool _saving = false;
  bool _submitting = false;

  bool get _isEnglish => widget.locale.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _questionsFuture = _service.listQuestions(widget.assignment.id, studentId: widget.profile.id);
    _loadSubmission();
  }

  Future<void> _loadSubmission() async {
    try {
      final submission = await _service.getStudentSubmission(assignmentId: widget.assignment.id, studentId: widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(() { _submission = submission; _loadingSubmission = false; });
      if (submission == null) {
        return;
      }
      final answers = await _service.listAnswers(submission.id);
      await _applyAnswers(answers);
    } catch (_) {
      final localSubmission = await _offline.getSubmission(widget.profile.id, widget.assignment.id);
      if (!mounted) {
        return;
      }
      setState(() { _submission = localSubmission; _loadingSubmission = false; });
      if (localSubmission != null) {
        await _applyAnswers(await _offline.getAnswers(widget.profile.id, localSubmission.id));
      }
    }
  }

  Future<void> _applyAnswers(List<AssignmentAnswer> answers) async {
    if (!mounted) {
      return;
    }
    for (final answer in answers) {
      if (answer.answerText != null) {
        _answerControllers[answer.questionId] ??= TextEditingController();
        _answerControllers[answer.questionId]!.text = answer.answerText!;
      }
      if (answer.selectedOption != null) {
        _selectedAnswers[answer.questionId] = answer.selectedOption;
      }
    }
    setState(() {});
    unawaited(_restoreQcmFeedback(answers));
  }

  Future<void> _restoreQcmFeedback(List<AssignmentAnswer> answers) async {
    try {
      final questions = await _questionsFuture;
      final byId = {for (final question in questions) question.id: question};
      for (final answer in answers) {
        final question = byId[answer.questionId];
        final selected = answer.selectedOption;
        if (question == null || selected == null || (!question.isQcm && !question.isTrueFalse)) continue;
        try {
          final result = await Supabase.instance.client.rpc(
            'check_assignment_qcm_answer',
            params: {'p_question_id': question.id, 'p_selected_option': selected},
          );
          if (result is Map && mounted) {
            setState(() => _qcmFeedback[question.id] = Map<String, dynamic>.from(result));
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _selectQcmAnswer(AssignmentQuestion question, String? value) async {
    if (value == null || !_isDraftSubmission || _isClosed ||
        _selectedAnswers[question.id] != null || _qcmChecking.contains(question.id)) return;

    setState(() => _qcmChecking.add(question.id));
    try {
      await _ensureSubmission();
      final submission = _submission;
      if (submission == null || !mounted) return;

      try {
        await _service.saveAnswer(
          submissionId: submission.id,
          questionId: question.id,
          selectedOption: value,
        );
      } catch (_) {
        // A QCM choice must not disappear just because the network is down.
        await _offline.saveAnswer(AssignmentAnswer(
          id: 'local-${submission.id}-${question.id}',
          submissionId: submission.id,
          questionId: question.id,
          selectedOption: value,
          createdAt: DateTime.now(),
        ), widget.profile.id);
        if (!mounted) return;
        setState(() => _selectedAnswers[question.id] = value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEnglish
              ? 'Answer saved on this device. It will sync when you reconnect.'
              : 'Réponse enregistrée sur cet appareil. Elle sera synchronisée à la reconnexion.')),
        );
        return;
      }

      if (!mounted) return;
      // Keep the selected answer locked even if the feedback endpoint is
      // temporarily unavailable; the answer itself has already been saved.
      setState(() => _selectedAnswers[question.id] = value);
      try {
        final result = await Supabase.instance.client.rpc(
          'check_assignment_qcm_answer',
          params: {'p_question_id': question.id, 'p_selected_option': value},
        );
        if (result is Map && mounted) {
          setState(() => _qcmFeedback[question.id] = Map<String, dynamic>.from(result));
        } else if (mounted) {
          throw StateError('Correction QCM indisponible.');
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEnglish
                ? 'Answer saved. Correction will be available when the connection returns.'
                : 'Réponse enregistrée. La correction sera disponible au retour de la connexion.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEnglish
              ? 'Unable to save this answer on this device.'
              : 'Impossible d’enregistrer cette réponse sur cet appareil.')),
        );
      }
    } finally {
      if (mounted) setState(() => _qcmChecking.remove(question.id));
    }
  }

  String _normalizedOption(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool _isCorrectOption(AssignmentQuestion question, String option, Map<String, dynamic> feedback) {
    var correct = feedback['correct_option']?.toString() ?? '';
    if (question.isTrueFalse) {
      final normalized = _normalizedOption(correct);
      correct = (normalized == 'vrai' || normalized == 'true' || normalized == 'oui' || normalized == 'yes' || normalized == '1')
          ? 'true'
          : 'false';
    }
    return _normalizedOption(option) == _normalizedOption(correct);
  }

  @override
  void dispose() {
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> _ensureSubmission() async {
    if (_submission != null) {
      return;
    }

    Future<void> createLocalSubmission() async {
      final now = DateTime.now();
      final submission = AssignmentSubmission(
        id: 'local-${widget.assignment.id}-${widget.profile.id}',
        assignmentId: widget.assignment.id,
        studentId: widget.profile.id,
        status: 'draft',
        createdAt: now,
        updatedAt: now,
      );
      await _offline.saveSubmission(submission, widget.profile.id);
      if (mounted) setState(() => _submission = submission);
    }

    if (!await ConnectivityService().isOnline()) {
      await createLocalSubmission();
      return;
    }

    try {
      final submission = await _service.createOrGetStudentSubmission(
        assignmentId: widget.assignment.id,
        studentId: widget.profile.id,
      );
      if (!mounted) return;
      setState(() => _submission = submission);
    } catch (_) {
      await createLocalSubmission();
    }
  }

  Future<void> _saveAnswer(AssignmentQuestion question) async {
    await _ensureSubmission();

    if (!mounted) {
      return;
    }

    final submission = _submission;

    if (submission == null || submission.status != 'draft') {
      return;
    }

    final controller = _answerControllers[question.id];

    final answerText = controller?.text.trim();

    final selectedOption = _selectedAnswers[question.id];

    final hasTextAnswer = answerText != null && answerText.isNotEmpty;

    final hasSelectedAnswer =
        selectedOption != null && selectedOption.trim().isNotEmpty;

    if (!hasTextAnswer && !hasSelectedAnswer) {
      return;
    }

    try {
      await _service.saveAnswer(
        submissionId: submission.id, questionId: question.id,
        answerText: hasTextAnswer ? answerText : null,
        selectedOption: hasSelectedAnswer ? selectedOption : null,
      );
    } catch (_) {
      await _offline.saveAnswer(AssignmentAnswer(
        id: 'local-${submission.id}-${question.id}', submissionId: submission.id, questionId: question.id,
        answerText: hasTextAnswer ? answerText : null, selectedOption: hasSelectedAnswer ? selectedOption : null,
        createdAt: DateTime.now(),
      ), widget.profile.id);
    }
  }

  Future<void> _saveAllAnswers(List<AssignmentQuestion> questions) async {
    for (final question in questions) {
      await _saveAnswer(question);
    }
  }

  Future<void> _saveCurrentAnswers(List<AssignmentQuestion> questions) async {
    if (_submission != null && _submission!.status != 'draft') {
      return;
    }

    try {
      setState(() {
        _saving = true;
      });

      await _saveAllAnswers(questions);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish ? 'Answers saved.' : 'Réponses enregistrées.',
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
                ? 'Unable to save answers.'
                : 'Impossible d’enregistrer les réponses.',
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

  Future<void> _submitAssignment(List<AssignmentQuestion> questions) async {
    if (_submission == null) {
      await _ensureSubmission();
    }

    if (!mounted) {
      return;
    }

    final submission = _submission;

    if (submission == null || submission.status != 'draft') {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _isEnglish ? 'Submit assignment?' : 'Envoyer le devoir ?',
          ),
          content: Text(
            _isEnglish
                ? 'After submission, you will no longer be able to modify your answers.'
                : 'Après l’envoi, vous ne pourrez plus modifier vos réponses.',
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
              child: Text(_isEnglish ? 'Submit' : 'Envoyer'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      setState(() {
        _submitting = true;
      });

      await _saveAllAnswers(questions);

      if (!mounted) {
        return;
      }

      AssignmentSubmission updated;
      try {
        updated = await _service.submitAssignment(submissionId: submission.id);
      } catch (_) {
        final answers = <Map<String, dynamic>>[];
        for (final question in questions) {
          final controller = _answerControllers[question.id];
          final selected = _selectedAnswers[question.id];
          if ((controller?.text.trim().isNotEmpty ?? false) || (selected?.trim().isNotEmpty ?? false)) {
            answers.add({
              'question_id': question.id,
              'answer_text': controller?.text.trim(),
              'selected_option': selected,
            });
          }
        }
        await _offline.savePendingAssignment(
          userId: widget.profile.id, submissionId: submission.id, assignmentId: widget.assignment.id,
          payload: {'answers': answers},
        );
        updated = submission.copyWith(status: 'submitted', submittedAt: DateTime.now(), updatedAt: DateTime.now());
        await _offline.saveSubmission(updated, widget.profile.id);
      }

      if (!mounted) {
        return;
      }
      setState(() { _submission = updated; });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEnglish
                ? 'Assignment submitted successfully.'
                : 'Devoir envoyé avec succès.',
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
                ? 'Unable to submit the assignment.'
                : 'Impossible d’envoyer le devoir.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  bool get _isClosed {
    return widget.assignment.status == 'closed';
  }

  bool get _isDraftSubmission {
    return _submission == null || _submission!.status == 'draft';
  }

  bool get _isSubmitted {
    return _submission?.status == 'submitted' ||
        _submission?.status == 'corrected';
  }

  String _formatDueDate(DateTime? date) {
    if (date == null) {
      return _isEnglish ? 'No deadline' : 'Pas de date limite';
    }

    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.assignment.titleFor(widget.locale);

    final instructions = widget.assignment.instructionsFor(widget.locale);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      appBar: AppBar(
        title: Text(
          _isEnglish ? 'Assignment' : 'Devoir',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
      ),
      body: _loadingSubmission
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF166534)),
            )
          : FutureBuilder<List<AssignmentQuestion>>(
              future: _questionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF166534)),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _isEnglish
                            ? 'Unable to load questions.'
                            : 'Impossible de charger les questions.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final questions = snapshot.data ?? const <AssignmentQuestion>[];

                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _buildHeader(title, instructions),
                          const SizedBox(height: 18),
                          if (_isSubmitted) _buildSubmissionStatus(),
                          if (_isSubmitted) const SizedBox(height: 14),
                          if (questions.isEmpty)
                            _buildNoQuestions()
                          else
                            ...List.generate(
                              questions.length,
                              (index) =>
                                  _buildQuestionCard(questions[index], index),
                            ),
                        ],
                      ),
                    ),
                    if (questions.isNotEmpty &&
                        _isDraftSubmission &&
                        !_isClosed)
                      _buildBottomActions(questions),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildHeader(String title, String? instructions) {
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
                  Icons.assignment_rounded,
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
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (instructions != null && instructions.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              instructions.trim(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeaderChip(
                Icons.calendar_today_rounded,
                _formatDueDate(widget.assignment.dueAt),
              ),
              _buildHeaderChip(
                Icons.grade_rounded,
                '${widget.assignment.maxScore.toStringAsFixed(0)} pts',
              ),
              if (_isClosed)
                _buildHeaderChip(
                  Icons.lock_outline_rounded,
                  _isEnglish ? 'Closed' : 'Fermé',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(AssignmentQuestion question, int index) {
    final questionText = question.questionFor(widget.locale);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F2E9),
                    borderRadius: BorderRadius.circular(12),
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
                    questionText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${question.points.toStringAsFixed(0)} points',
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildAnswerWidget(question),
          ],
        ),
      ),
    );
  }

  /// Mélange les options d'un QCM de façon stable pour cet élève, afin que la
  /// bonne réponse ne reste pas toujours à la place choisie par l'enseignant.
  /// La correction se fait sur le texte de l'option : l'ordre n'a aucun effet.
  List<String> _arrangedOptions(AssignmentQuestion question) {
    final options = List<String>.of(question.options);
    final pinned = RegExp(
      r'^(toutes?\s+les\s+(réponses|options|propositions)|aucune?\s+(des|de\s+ces)|all\s+of\s+the\s+above|none\s+of\s+the\s+above)',
      caseSensitive: false,
    );
    if (options.any(pinned.hasMatch)) return options;
    final seed = '${question.id}|${widget.profile.id}'.codeUnits.fold<int>(
      7,
      (hash, unit) => (hash * 31 + unit) & 0x7fffffff,
    );
    options.shuffle(math.Random(seed));
    return options;
  }

  Widget _buildAnswerWidget(AssignmentQuestion question) {
    final enabled = _isDraftSubmission && !_isClosed;
    final selected = _selectedAnswers[question.id];
    final feedback = _qcmFeedback[question.id];
    final checking = _qcmChecking.contains(question.id);

    if (question.isQcm || question.isTrueFalse) {
      final options = question.isQcm ? _arrangedOptions(question) : <String>['true', 'false'];
      return Column(
        children: [
          if (checking) const LinearProgressIndicator(minHeight: 2),
          ...options.map((option) {
            final displayOption = question.isTrueFalse
                ? (option == 'true' ? (_isEnglish ? 'True' : 'Vrai') : (_isEnglish ? 'False' : 'Faux'))
                : option;
            final correct = feedback != null && _isCorrectOption(question, option, feedback);
            final selectedWrong = feedback != null && selected == option && feedback['is_correct'] != true;
            final background = correct
                ? const Color(0xFFE4F7E8)
                : selectedWrong ? const Color(0xFFFFE8E8) : const Color(0xFFF7F9F8);
            final foreground = correct
                ? const Color(0xFF166534)
                : selectedWrong ? const Color(0xFFB91C1C) : Colors.black87;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: correct ? const Color(0xFF16A34A)
                      : selectedWrong ? const Color(0xFFDC2626) : Colors.black12,
                  width: correct || selectedWrong ? 1.5 : 1,
                ),
              ),
              child: RadioListTile<String>(
                value: option,
                groupValue: selected,
                onChanged: enabled && selected == null && !checking
                    ? (value) => _selectQcmAnswer(question, value)
                    : null,
                activeColor: foreground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Row(
                  children: [
                    Expanded(child: Text(displayOption, style: TextStyle(
                      color: foreground,
                      fontWeight: correct || selectedWrong ? FontWeight.w700 : FontWeight.normal,
                    ))),
                    if (correct) const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
                    if (selectedWrong) const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626)),
                  ],
                ),
              ),
            );
          }),
          if (feedback != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: feedback['is_correct'] == true ? const Color(0xFFE4F7E8) : const Color(0xFFFFE8E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                feedback['is_correct'] == true
                    ? (_isEnglish ? 'Correct answer!' : 'Bonne réponse !')
                    : (_isEnglish ? 'Incorrect answer. The correct answer is shown in green.' : 'Mauvaise réponse. La bonne réponse est en vert.'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: feedback['is_correct'] == true ? const Color(0xFF166534) : const Color(0xFFB91C1C),
                ),
              ),
            ),
        ],
      );
    }

    final controller = _answerControllers.putIfAbsent(question.id, () => TextEditingController());
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: question.isShortAnswer ? 2 : 4,
      maxLines: question.isShortAnswer ? 4 : 8,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: question.isShortAnswer
            ? (_isEnglish ? 'Write your answer...' : 'Écrivez votre réponse...')
            : (_isEnglish ? 'Write your answer in detail...' : 'Écrivez votre réponse en détail...'),
        filled: true,
        fillColor: const Color(0xFFF7F9F8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF166534))),
      ),
    );
  }

  Widget _buildSubmissionStatus() {
    final submission = _submission;

    if (submission == null) {
      return const SizedBox.shrink();
    }

    final corrected = submission.status == 'corrected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: corrected ? const Color(0xFFE7F7EC) : const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            corrected
                ? Icons.task_alt_rounded
                : Icons.check_circle_outline_rounded,
            color: corrected ? const Color(0xFF166534) : Colors.blueAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              corrected
                  ? (_isEnglish
                        ? 'Your assignment has been corrected.'
                        : 'Votre devoir a été corrigé.')
                  : (_isEnglish
                        ? 'Your assignment has been submitted.'
                        : 'Votre devoir a été envoyé.'),
              style: TextStyle(
                color: corrected ? const Color(0xFF166534) : Colors.blueAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestions() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.help_outline_rounded, size: 58, color: Colors.grey),
          const SizedBox(height: 14),
          Text(
            _isEnglish
                ? 'No questions available.'
                : 'Aucune question disponible.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(List<AssignmentQuestion> questions) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving || _submitting
                    ? null
                    : () => _saveCurrentAnswers(questions),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isEnglish ? 'Save' : 'Enregistrer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving || _submitting
                    ? null
                    : () => _submitAssignment(questions),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_isEnglish ? 'Submit' : 'Envoyer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
