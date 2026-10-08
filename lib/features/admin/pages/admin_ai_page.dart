import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/gemini_service.dart';
import '../../../models/user_profile.dart';

/// Assistant IA réservé à l'administrateur pour préparer et contrôler les contenus pédagogiques.
class AdminAiPage extends StatefulWidget {
  final Locale locale;
  const AdminAiPage({super.key, required this.locale});

  @override
  State<AdminAiPage> createState() => _AdminAiPageState();
}

class _AdminAiPageState extends State<AdminAiPage> {
  final _client = Supabase.instance.client;
  final _ai = GeminiService();
  final _prompt = TextEditingController();
  final _context = TextEditingController();
  final _scroll = ScrollController();
  UserProfile? _profile;
  bool _loading = true;
  bool _sending = false;
  final List<_AdminAiMessage> _messages = [];

  bool get _fr => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw Exception('Session introuvable.');
      final row = await _client.from('profiles').select().eq('id', user.id).single();
      final profile = UserProfile.fromMap(Map<String, dynamic>.from(row));
      if (profile.role != 'admin') throw Exception(_fr ? 'Accès administrateur requis.' : 'Administrator access required.');
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
        _messages.add(_AdminAiMessage(
          text: _fr
              ? 'Je peux préparer des leçons, exercices, QCM, corrigés et adaptations par classe, filière et sous-système. Décris précisément la salle et le contenu à produire.'
              : 'I can prepare lessons, exercises, quizzes, answer keys and adaptations by class, track and subsystem. Describe the classroom and content to create.',
          fromUser: false,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messages.add(_AdminAiMessage(text: e.toString().replaceFirst('Exception: ', ''), fromUser: false));
      });
    }
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _sending || _profile == null) return;
    final context = _context.text.trim();
    _prompt.clear();
    setState(() {
      _sending = true;
      _messages.add(_AdminAiMessage(text: text, fromUser: true));
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .takeLast(20)
          .map((m) => AiHistoryMessage(role: m.fromUser ? 'user' : 'model', text: m.text))
          .toList();
      final answer = await _ai.ask(
        message: text,
        profile: _profile!,
        history: history,
        mode: 'admin',
        schoolContext: {
          'target': context,
          'instruction': _fr
              ? 'Respecter le programme camerounais fourni et ne pas inventer les données officielles.'
              : 'Respect the supplied Cameroon curriculum context and do not invent official data.',
        },
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_AdminAiMessage(text: answer, fromUser: false));
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_AdminAiMessage(text: e.toString().replaceFirst('Exception: ', ''), fromUser: false));
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _prompt.dispose();
    _context.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'IA pédagogique administrateur' : 'Administrator pedagogical AI'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: _context,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: _fr ? 'Contexte scolaire' : 'School context',
                          hintText: _fr
                              ? 'Ex. 3e francophone, série D, Mathématiques, chapitre Fonctions…'
                              : 'E.g. Form 3 English subsystem, Mathematics, Functions chapter…',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fr
                            ? 'Pour un programme officiel précis, fournissez le chapitre, la classe et les éléments validés afin que l’IA n’invente pas.'
                            : 'For precise official curriculum content, provide the chapter, class and validated elements so the AI does not invent them.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[i];
                  return Align(
                    alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 720),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: m.fromUser ? const Color(0xFF166534) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        m.text,
                        style: TextStyle(color: m.fromUser ? Colors.white : const Color(0xFF0F172A), height: 1.45),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_sending) const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prompt,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: _fr ? 'Demande à l’IA de préparer un contenu…' : 'Ask AI to prepare content…',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAiMessage {
  final String text;
  final bool fromUser;
  const _AdminAiMessage({required this.text, required this.fromUser});
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    return list.length <= count ? list : list.sublist(list.length - count);
  }
}
