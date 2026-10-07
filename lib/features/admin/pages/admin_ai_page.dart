import 'package:flutter/material.dart';

import '../../../core/services/gemini_service.dart';
import '../../../models/user_profile.dart';

class AdminAiPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const AdminAiPage({
    super.key,
    required this.locale,
    required this.profile,
  });

  @override
  State<AdminAiPage> createState() => _AdminAiPageState();
}

class _AdminAiPageState extends State<AdminAiPage> {
  final TextEditingController _controller = TextEditingController();
  final GeminiService _service = GeminiService();

  bool _sending = false;
  String? _answer;
  String? _error;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final context = [
        'Tu es l’assistant IA administrateur de Fise School.',
        'Aide l’administration à gérer les salles, les matières, les cours, les devoirs et la pédagogie.',
        'Le compte connecté est : ${widget.profile.role} / ${widget.profile.firstName} ${widget.profile.lastName}.',
        if (widget.profile.subsystem != null) 'Sous-système : ${widget.profile.subsystem}',
        if (widget.profile.sector != null) 'Secteur : ${widget.profile.sector}',
        if (widget.profile.className != null) 'Classe : ${widget.profile.className}',
        if (widget.profile.examLevel != null) 'Niveau : ${widget.profile.examLevel}',
        if (widget.profile.exam != null) 'Examen : ${widget.profile.exam}',
        'Règle : réponds de façon claire, pédagogique et pratique, sans inventer de contenu de programme non connu.',
      ].join('\n');

      final answer = await _service.ask(
        message: message,
        profile: widget.profile,
        context: context,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _answer = answer;
        _sending = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '').trim();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Assistant IA Admin' : 'Admin AI Assistant',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5EC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Color(0xFF166534)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isFrench
                            ? 'Aide l’administration à préparer les classes, les contenus, les salles et la pédagogie.'
                            : 'Help the administration plan classrooms, content, rooms, and teaching operations.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _error ?? _answer ?? (
                        _isFrench
                            ? 'Pose une question sur les salles, le catalogue, les matières, les cours, les devoirs ou la gestion pédagogique.'
                            : 'Ask about classrooms, catalog, subjects, courses, tests, or academic management.',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _isFrench ? 'Exemple : propose une meilleure organisation des matières pour une classe...' : 'Example: suggest a better subject organization for a classroom…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_isFrench ? 'Envoyer' : 'Send'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
