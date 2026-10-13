import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final Set<String> _checkingQcm = {};

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
      if (submission.status == 'submitted') {
        // Retry a previous transient AI error when the student reopens a saved submission.
        unawaited(_service.requestAiCorrection(submission.id));
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
    try {
      final submission = await _service.createOrGetStudentSubmission(assignmentId: widget.assignment.id, studentId: widget.profile.id);
      if (!mounted) {
        return;
      }
      setState(() => _submission = submission);
    } catch (_) {
      final now = DateTime.now();
      final submission = AssignmentSubmission(
        id: 'local-${widget.assignment.id}-${widget.profile.id}',
        assignmentId: widget.assignment.id, studentId: widget.profile.id, status: 'draft',
        createdAt: now, updatedAt: now,
      );
      await _offline.saveSubmission(submission, widget.profile.id);
      if (mounted) {
        setState(() => _submission = submission);
      }
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

  bool get _isNotStarted {
    final start = widget.assignment.startsAt;
    return start != null && DateTime.now().isBefore(start.toLocal());
  }

  bool get _isClosed {
    final deadline = widget.assignment.dueAt;
    return widget.assignment.status == 'closed' ||
        (deadline != null &&
            !DateTime.now().isBefore(deadline.toLocal()));
  }

  Future<void> _openOfficialExamPdf() async {
    final path = widget.assignment.evaluationFilePath;
    if (path == null || path.trim().isEmpty || _isNotStarted || _isClosed) {
      return;
    }
    try {
      final url = await Supabase.instance.client.storage
          .from('assignment-files')
          .createSignedUrl(path, 900);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEnglish
              ? 'Unable to open the exam PDF.'
              : 'Impossible d’ouvrir le PDF de l’épreuve.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${_isEnglish ? 'Exam PDF unavailable' : 'PDF de l’épreuve indisponible'}: $error'),
        ));
      }
    }
  }

  Widget _buildOfficialExamPdfButton() {
    final enabled = !_isNotStarted && !_isClosed;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_rounded),
        title: Text(widget.assignment.evaluationFileName ??
            (_isEnglish ? 'Official exam PDF' : 'Épreuve officielle PDF')),
        subtitle: Text(enabled
            ? (_isEnglish ? 'Open during the evaluation window' : 'Disponible pendant la période de l’évaluation')
            : (_isNotStarted
                ? (_isEnglish ? 'Available when the exam starts' : 'Disponible à l’ouverture de l’épreuve')
                : (_isEnglish ? 'Evaluation closed' : 'Évaluation terminée'))),
        trailing: const Icon(Icons.open_in_new_rounded),
        onTap: enabled ? _openOfficialExamPdf : null,
      ),
    );
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
                          if (widget.assignment.evaluationFilePath != null) ...[
                            const SizedBox(height: 12),
                            _buildOfficialExamPdfButton(),
                          ],
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
                        !_isClosed &&
                        !_isNotStarted)
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
              if (widget.assignment.startsAt != null)
                _buildHeaderChip(
                  Icons.play_circle_outline_rounded,
                  '${_isEnglish ? 'Starts' : 'Début'} : ${_formatDueDate(widget.assignment.startsAt)}',
                ),
              _buildHeaderChip(
                Icons.calendar_today_rounded,
                _formatDueDate(widget.assignment.dueAt),
              ),
              if (_isNotStarted)
                _buildHeaderChip(
                  Icons.schedule_rounded,
                  _isEnglish ? 'Not started yet' : 'Pas encore ouvert',
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

  Future<void> _checkAssignmentQcmAnswer(
    AssignmentQuestion question,
    String selectedOption,
  ) async {
    try {
      final feedback = await _service.checkQcmAnswer(
        questionId: question.id,
        selectedOption: selectedOption,
      );
      if (!mounted) return;
      setState(() {
        _checkingQcm.remove(question.id);
        _qcmFeedback[question.id] = feedback;
      });
      final correct = feedback['is_correct'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(correct
              ? (_isEnglish ? 'Correct answer! Well done.' : 'Bonne réponse ! Bravo.')
              : (_isEnglish ? 'Incorrect answer.' : 'Mauvaise réponse.')),
          backgroundColor: correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingQcm.remove(question.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEnglish
              ? 'Unable to check this answer. Check your connection.'
              : 'Impossible de vérifier cette réponse. Vérifie ta connexion.'),
        ),
      );
    }
  }

  Widget _buildAnswerWidget(AssignmentQuestion question) {
    final enabled = _isDraftSubmission && !_isClosed && !_isNotStarted;

    if (question.isQcm || question.isTrueFalse) {
      final options = question.isQcm
          ? question.options
          : <String>[_isEnglish ? 'True' : 'Vrai', _isEnglish ? 'False' : 'Faux'];
      final selected = _selectedAnswers[question.id];
      final feedback = _qcmFeedback[question.id];
      final correctOption = feedback?['correct_option']?.toString();
      final hasFeedback = feedback != null;
      return Column(
        children: [
          RadioGroup<String>(
            groupValue: selected,
            onChanged: (value) {
              if (!enabled || value == null) return;
              setState(() {
                _selectedAnswers[question.id] = value;
                _qcmFeedback.remove(question.id);
                _checkingQcm.add(question.id);
              });
              _saveAnswer(question);
              _checkAssignmentQcmAnswer(question, value);
            },
            child: Column(
              children: options.map((option) {
                final isCorrect = hasFeedback &&
                    correctOption != null &&
                    _normalizeAnswer(correctOption) == _normalizeAnswer(option);
                final isSelected = selected != null &&
                    _normalizeAnswer(selected) == _normalizeAnswer(option);
                final isWrongSelected = hasFeedback && isSelected &&
                    feedback['is_correct'] != true;
                return RadioListTile<String>(
                  value: option,
                  enabled: enabled && !_checkingQcm.contains(question.id),
                  activeColor: const Color(0xFF166534),
                  contentPadding: EdgeInsets.zero,
                  tileColor: isCorrect
                      ? const Color(0xFFE8F5E9)
                      : (isWrongSelected ? const Color(0xFFFFEBEE) : null),
                  title: Text(option, style: const TextStyle(height: 1.35)),
                  secondary: _checkingQcm.contains(question.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (isCorrect
                          ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
                          : (isWrongSelected
                              ? const Icon(Icons.cancel, color: Color(0xFFC62828))
                              : null)),
                );
              }).toList(),
            ),
          ),
          if (selected != null && hasFeedback)
            _buildImmediateFeedback(feedback['is_correct'] == true),
        ],
      );
    }

    final controller = _answerControllers.putIfAbsent(
      question.id,
      () => TextEditingController(),
    );

    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: question.isShortAnswer ? 2 : 4,
      maxLines: question.isShortAnswer ? 4 : 8,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: question.isShortAnswer
            ? (_isEnglish ? 'Write your answer...' : 'Écrivez votre réponse...')
            : (_isEnglish
                  ? 'Write your answer in detail...'
                  : 'Écrivez votre réponse en détail...'),
        filled: true,
        fillColor: const Color(0xFFF7F9F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF166534)),
        ),
      ),
    );
  }

  String _normalizeAnswer(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Widget _buildImmediateFeedback(bool correct) {
    final color = correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: correct ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(correct ? Icons.check_circle : Icons.cancel, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(
          correct
              ? (_isEnglish ? 'Correct answer! Well done.' : 'Bonne réponse ! Bravo.')
              : (_isEnglish ? 'Incorrect. The correct answer is marked in green.' : 'Mauvaise réponse. La bonne réponse est indiquée en vert.'),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        )),
      ]),
    );
  }

  Widget _buildSubmissionStatus() {
    final submission = _submission;
    if (submission == null) return const SizedBox.shrink();

    final corrected = submission.status == 'corrected';
    final feedback = submission.feedbackFor(widget.locale)?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: corrected ? const Color(0xFFE7F7EC) : const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                corrected ? Icons.task_alt_rounded : Icons.check_circle_outline_rounded,
                color: corrected ? const Color(0xFF166534) : Colors.blueAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  corrected
                      ? (_isEnglish
                          ? 'Your assignment has been corrected and the result is published.'
                          : 'Votre devoir est corrigé et le résultat est publié.')
                      : (_isEnglish
                          ? 'Your assignment has been submitted. The result will appear after its scheduled release.'
                          : 'Votre devoir a été envoyé. Le résultat apparaîtra à la date de publication prévue.'),
                  style: TextStyle(
                    color: corrected ? const Color(0xFF166534) : Colors.blueAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (corrected && submission.score != null) ...[
            const SizedBox(height: 12),
            Text(
              '${_isEnglish ? 'Published score' : 'Note publiée'} : ${submission.score!.toStringAsFixed(2)} / ${widget.assignment.maxScore.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
          if (corrected && feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(feedback, style: const TextStyle(height: 1.4)),
          ],
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
                onPressed: _saving || _submitting || _isNotStarted || _isClosed
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
                onPressed: _saving || _submitting || _isNotStarted || _isClosed
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
