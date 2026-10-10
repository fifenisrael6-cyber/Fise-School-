import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/past_paper_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/past_paper.dart';
import 'past_paper_viewer_page.dart';

/// Annales d'examens : sujets et corrigés, filtrables par examen, année et matière.
class PastPapersPage extends StatefulWidget {
  final Locale locale;
  const PastPapersPage({super.key, required this.locale});

  @override
  State<PastPapersPage> createState() => _PastPapersPageState();
}

class _PastPapersPageState extends State<PastPapersPage> {
  final _service = PastPaperService();
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<PastPaper> _papers = const [];
  Map<String, ExamDefinition> _exams = const {};
  String? _examId;
  int? _year;

  bool get _fr => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final papers = await _service.list();
      Map<String, ExamDefinition> exams = {};
      try {
        final list = await ExamCatalogService().getExams();
        exams = {for (final e in list) e.id: e};
      } catch (_) {
        // Les noms d'examens sont facultatifs : la liste reste utilisable.
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _papers = papers;
        _exams = exams;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _fr
            ? 'Impossible de charger les annales. Vérifiez votre connexion.'
            : 'Unable to load past papers. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _open(PastPaper paper) async {
    try {
      final url = await _service.signedUrl(paper.filePath);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}');
      }
      if (!mounted) return;
      final isPdf = paper.fileName.toLowerCase().endsWith('.pdf');
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PastPaperViewerPage(
            title: paper.subjectFor(widget.locale.languageCode),
            bytes: response.bodyBytes,
            isPdf: isPdf,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        _snack(_fr ? 'Impossible d’ouvrir ce fichier dans Fise School.' : 'Unable to open this file in Fise School.');
      }
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<PastPaper> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _papers.where((p) {
      if (_examId != null && p.examId != _examId) {
        return false;
      }
      if (_year != null && p.year != _year) {
        return false;
      }
      if (q.isNotEmpty &&
          !p.subjectFr.toLowerCase().contains(q) &&
          !p.subjectEn.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final years = _papers.map((p) => p.year).toSet().toList()..sort((a, b) => b.compareTo(a));
    final examIds = _papers.map((p) => p.examId).whereType<String>().toSet();
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(title: Text(_fr ? 'Annales d’examens' : 'Past exam papers')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_fr ? 'Réessayer' : 'Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: _fr ? 'Rechercher une matière' : 'Search a subject',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            initialValue: _examId,
                            decoration: InputDecoration(labelText: _fr ? 'Examen' : 'Exam', border: const OutlineInputBorder()),
                            items: [
                              DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Tous' : 'All')),
                              ...examIds.map((id) => DropdownMenuItem<String?>(
                                    value: id,
                                    child: Text(_exams[id]?.labelFor(widget.locale.languageCode) ?? id, overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _examId = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            initialValue: _year,
                            decoration: InputDecoration(labelText: _fr ? 'Année' : 'Year', border: const OutlineInputBorder()),
                            items: [
                              DropdownMenuItem<int?>(value: null, child: Text(_fr ? 'Toutes' : 'All')),
                              ...years.map((y) => DropdownMenuItem<int?>(value: y, child: Text('$y'))),
                            ],
                            onChanged: (v) => setState(() => _year = v),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              _papers.isEmpty
                                  ? (_fr ? 'Aucune annale n’est encore publiée.' : 'No past papers published yet.')
                                  : (_fr ? 'Aucun résultat pour ces filtres.' : 'No results for these filters.'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ...items.map((p) {
                        final exam = p.examId == null ? null : _exams[p.examId!];
                        final parts = <String>[
                          if (exam != null) exam.labelFor(widget.locale.languageCode),
                          '${p.year}',
                          if (p.session != null && p.session!.isNotEmpty) p.session!,
                        ];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: p.isCorrection ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                              child: Icon(p.isCorrection ? Icons.task_alt : Icons.description_outlined, color: const Color(0xFF166534)),
                            ),
                            title: Text(p.subjectFor(widget.locale.languageCode), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${p.isCorrection ? (_fr ? 'Corrigé' : 'Correction') : (_fr ? 'Sujet' : 'Paper')} · ${parts.join(' · ')}'),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => _open(p),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
