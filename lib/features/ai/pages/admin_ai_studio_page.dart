import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/offline/connectivity_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/widgets/rich_lesson_text.dart';

/// Assistant IA pour l'administrateur : aide à PRÉPARER du contenu
/// pédagogique. Le résultat est un brouillon modifiable. Cette page ne publie
/// rien : l'administrateur relit, corrige, puis publie lui-même depuis la
/// gestion des cours.
class AdminAiStudioPage extends StatefulWidget {
  final Locale locale;

  const AdminAiStudioPage({super.key, required this.locale});

  @override
  State<AdminAiStudioPage> createState() => _AdminAiStudioPageState();
}

enum _StudioTask {
  fullLesson,
  structure,
  objectives,
  explanation,
  examples,
  exercises,
  qcm,
  improve,
}

class _AdminAiStudioPageState extends State<AdminAiStudioPage> {
  final GeminiService _gemini = GeminiService();
  final ConnectivityService _connectivity = ConnectivityService();

  final TextEditingController _classController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _chapterController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _draftController = TextEditingController();

  _StudioTask _task = _StudioTask.fullLesson;
  bool _generating = false;
  bool _preview = false;
  String? _error;

  bool get _isFrench => widget.locale.languageCode != 'en';

  @override
  void dispose() {
    _classController.dispose();
    _subjectController.dispose();
    _chapterController.dispose();
    _topicController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  String _taskLabel(_StudioTask task) {
    switch (task) {
      case _StudioTask.fullLesson:
        return _isFrench ? 'Leçon complète' : 'Complete lesson';
      case _StudioTask.structure:
        return _isFrench ? 'Structure de cours' : 'Course outline';
      case _StudioTask.objectives:
        return _isFrench ? 'Objectifs' : 'Objectives';
      case _StudioTask.explanation:
        return _isFrench ? 'Explications adaptées à la classe' : 'Class-level explanations';
      case _StudioTask.examples:
        return _isFrench ? 'Exemples résolus' : 'Worked examples';
      case _StudioTask.exercises:
        return _isFrench ? 'Exercices avec corrigés' : 'Exercises with solutions';
      case _StudioTask.qcm:
        return _isFrench ? 'QCM avec réponses' : 'MCQ with answers';
      case _StudioTask.improve:
        return _isFrench ? 'Corriger / améliorer un texte' : 'Fix / improve a text';
    }
  }

  String _taskInstruction(_StudioTask task) {
    if (_isFrench) {
      switch (task) {
        case _StudioTask.fullLesson:
          return 'Rédige une leçon complète avec toutes les sections prévues (titre, objectifs, introduction, cours progressif, définitions, formules et leur explication, exemples résolus, applications, exercices, QCM, résumé).';
        case _StudioTask.structure:
          return 'Propose seulement la structure (plan) du cours : parties et sous-parties, dans un ordre pédagogique logique.';
        case _StudioTask.objectives:
          return 'Propose 4 à 6 objectifs pédagogiques précis, formulés avec des verbes d’action.';
        case _StudioTask.explanation:
          return 'Rédige des explications progressives, adaptées au niveau de la classe, avec les définitions importantes.';
        case _StudioTask.examples:
          return 'Propose 3 exemples résolus, du plus simple au plus difficile, avec toutes les étapes.';
        case _StudioTask.exercises:
          return 'Propose 5 exercices de difficulté progressive, avec corrigé détaillé.';
        case _StudioTask.qcm:
          return 'Génère 8 QCM avec 4 choix (A à D), indique la bonne réponse et une courte justification.';
        case _StudioTask.improve:
          return 'Corrige les fautes et améliore la formulation du texte ci-dessous, sans changer le sens ni ajouter de notions hors programme. Garde sa structure.';
      }
    }
    switch (task) {
      case _StudioTask.fullLesson:
        return 'Write a complete lesson with all the planned sections (title, objectives, introduction, progressive course, definitions, formulas and their explanation, worked examples, applications, exercises, MCQ, summary).';
      case _StudioTask.structure:
        return 'Propose only the course outline: parts and sub-parts, in a logical teaching order.';
      case _StudioTask.objectives:
        return 'Propose 4 to 6 precise learning objectives, written with action verbs.';
      case _StudioTask.explanation:
        return 'Write progressive explanations adapted to the class level, with the important definitions.';
      case _StudioTask.examples:
        return 'Propose 3 worked examples, from easiest to hardest, with every step.';
      case _StudioTask.exercises:
        return 'Propose 5 exercises of increasing difficulty, with detailed solutions.';
      case _StudioTask.qcm:
        return 'Generate 8 MCQs with 4 choices (A to D), mark the correct answer and give a short justification.';
      case _StudioTask.improve:
        return 'Fix the mistakes and improve the wording of the text below, without changing its meaning or adding out-of-syllabus notions. Keep its structure.';
    }
  }

  String _buildPrompt() {
    final className = _classController.text.trim();
    final subject = _subjectController.text.trim();
    final chapter = _chapterController.text.trim();
    final topic = _topicController.text.trim();

    final lines = <String>[
      _taskInstruction(_task),
      if (className.isNotEmpty) '${_isFrench ? 'Classe / série' : 'Class / series'} : $className',
      if (subject.isNotEmpty) '${_isFrench ? 'Matière' : 'Subject'} : $subject',
      if (chapter.isNotEmpty) '${_isFrench ? 'Chapitre' : 'Chapter'} : $chapter',
      if (topic.isNotEmpty)
        _task == _StudioTask.improve
            ? '${_isFrench ? 'Texte à améliorer' : 'Text to improve'} :\n$topic'
            : '${_isFrench ? 'Sujet / précisions' : 'Topic / details'} : $topic',
    ];
    return lines.join('\n');
  }

  Future<void> _generate() async {
    if (_generating) {
      return;
    }
    if (_classController.text.trim().isEmpty ||
        (_subjectController.text.trim().isEmpty && _topicController.text.trim().isEmpty)) {
      setState(() {
        _error = _isFrench
            ? 'Indique au moins la classe, et la matière ou le sujet.'
            : 'Enter at least the class, and the subject or topic.';
      });
      return;
    }
    if (_task == _StudioTask.improve && _topicController.text.trim().isEmpty) {
      setState(() {
        _error = _isFrench
            ? 'Colle le texte à améliorer dans le champ « Sujet / texte ».'
            : 'Paste the text to improve in the “Topic / text” field.';
      });
      return;
    }

    // On ne remplace pas un brouillon déjà modifié sans prévenir.
    if (_draftController.text.trim().isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_isFrench ? 'Remplacer le brouillon ?' : 'Replace the draft?'),
          content: Text(_isFrench
              ? 'Le brouillon actuel (avec tes modifications) sera remplacé par une nouvelle génération.'
              : 'The current draft (with your edits) will be replaced by a new generation.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_isFrench ? 'Remplacer' : 'Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) {
        return;
      }
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      if (!await _connectivity.isOnline()) {
        throw AiServiceException(_isFrench
            ? 'Pas de connexion Internet. Reconnecte-toi puis réessaie.'
            : 'No Internet connection. Reconnect and try again.');
      }
      final answer = await _gemini.ask(
        message: _buildPrompt(),
        mode: 'admin',
        languageCode: _isFrench ? 'fr' : 'en',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _draftController.text = answer;
        _generating = false;
        _preview = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _generating = false;
      });
    }
  }

  Future<void> _copyDraft() async {
    final text = _draftController.text.trim();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFrench
            ? 'Brouillon copié. Colle-le dans la leçon (Cours), relis-le, puis publie.'
            : 'Draft copied. Paste it in the lesson (Courses), review it, then publish.'),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDraft = _draftController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isFrench ? 'Assistant IA pédagogique' : 'Teaching AI assistant'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF9A3412)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isFrench
                          ? 'L’IA prépare un BROUILLON. Rien n’est publié automatiquement : relis, corrige puis publie toi-même depuis la gestion des cours.'
                          : 'The AI prepares a DRAFT. Nothing is published automatically: review, edit, then publish yourself from course management.',
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<_StudioTask>(
              initialValue: _task,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _isFrench ? 'Que veux-tu préparer ?' : 'What do you want to prepare?',
                border: const OutlineInputBorder(),
              ),
              items: _StudioTask.values
                  .map((task) => DropdownMenuItem(
                        value: task,
                        child: Text(_taskLabel(task), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _generating
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _task = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            _field(
              _classController,
              _isFrench ? 'Classe / série' : 'Class / series',
              hint: _isFrench ? 'Ex. Terminale D, 3ème, Form 5 Science' : 'E.g. Upper Sixth Science, Form 3',
            ),
            _field(
              _subjectController,
              _isFrench ? 'Matière' : 'Subject',
              hint: _isFrench ? 'Ex. Mathématiques' : 'E.g. Mathematics',
            ),
            _field(
              _chapterController,
              _isFrench ? 'Chapitre' : 'Chapter',
              hint: _isFrench ? 'Ex. Dérivation' : 'E.g. Differentiation',
            ),
            _field(
              _topicController,
              _task == _StudioTask.improve
                  ? (_isFrench ? 'Texte à améliorer' : 'Text to improve')
                  : (_isFrench ? 'Sujet / précisions (facultatif)' : 'Topic / details (optional)'),
              minLines: _task == _StudioTask.improve ? 6 : 2,
              maxLines: 12,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ),
            FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating
                  ? (_isFrench ? 'Génération en cours…' : 'Generating…')
                  : (hasDraft
                      ? (_isFrench ? 'Générer à nouveau' : 'Generate again')
                      : (_isFrench ? 'Générer un brouillon' : 'Generate a draft'))),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            if (hasDraft || _generating) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isFrench ? 'Brouillon (modifiable)' : 'Draft (editable)',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(_isFrench ? 'Aperçu' : 'Preview'),
                  Switch(
                    value: _preview,
                    onChanged: (value) => setState(() => _preview = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_preview)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: RichLessonText(text: _draftController.text),
                )
              else
                TextField(
                  controller: _draftController,
                  minLines: 12,
                  maxLines: null,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: hasDraft ? _copyDraft : null,
                icon: const Icon(Icons.copy_rounded),
                label: Text(_isFrench ? 'Copier le brouillon' : 'Copy the draft'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
