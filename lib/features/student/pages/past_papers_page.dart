import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/services/exam_catalog_service.dart';
import '../../../core/services/past_paper_service.dart';
import '../../../models/exam_catalog.dart';
import '../../../models/past_paper.dart';
import 'past_paper_viewer_page.dart';
import '../../../core/services/quota_service.dart';
import '../../../models/user_profile.dart';
import '../../premium/premium_gate.dart';

class PastPapersPage extends StatefulWidget {
  final Locale locale;
  final UserProfile? profile;
  const PastPapersPage({super.key, required this.locale, this.profile});

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
  final Map<String, String> _localPaths = {};
  final Set<String> _downloadingIds = {};
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
      final localPaths = <String, String>{};
      for (final paper in papers) {
        final path = await _service.localFilePath(paper);
        if (path != null) localPaths[paper.id] = path;
      }
      Map<String, ExamDefinition> exams = {};
      try {
        final list = await ExamCatalogService().getExams().timeout(const Duration(seconds: 2));
        exams = {for (final e in list) e.id: e};
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _papers = papers;
        _localPaths..clear()..addAll(localPaths);
        _exams = exams;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _fr
            ? 'Les annales ne sont pas encore en cache. Connecte-toi une fois pour les charger.'
            : 'Past papers are not cached yet. Connect once to load them.';
        _loading = false;
      });
    }
  }

  Future<void> _open(PastPaper paper) async {
    // Keep the existing quota/window rules, but always open inside Fise School.
    final profile = widget.profile;
    if (profile != null) {
      final allowed = await PremiumGate.ensure(
        context,
        profile: profile,
        feature: QuotaFeature.annale,
        resourceId: paper.id,
        offlineFallback: _localPaths[paper.id] != null,
      );
      if (!allowed || !mounted) return;
    }
    if (_downloadingIds.contains(paper.id)) return;
    setState(() => _downloadingIds.add(paper.id));
    try {
      var localPath = _localPaths[paper.id];
      if (localPath == null || !File(localPath).existsSync()) {
        localPath = await _service.localFilePath(paper);
      }
      if (localPath == null || !File(localPath).existsSync()) {
        // First open downloads the PDF and stores it for instant offline reuse.
        localPath = await _service.download(paper);
      }
      if (!mounted) return;
      setState(() => _localPaths[paper.id] = localPath!);
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => PastPaperViewerPage(
          locale: widget.locale,
          localPath: localPath!,
          fileName: paper.fileName,
        ),
      ));
    } catch (_) {
      if (mounted) {
        _snack(_fr
            ? 'Impossible de télécharger ou d’ouvrir cette annale. Vérifie la connexion puis réessaie.'
            : 'Unable to download or open this paper. Check the connection and retry.');
      }
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(paper.id));
    }
  }

  Future<void> _download(PastPaper paper) async {
    if (_downloadingIds.contains(paper.id)) return;
    final profile = widget.profile;
    if (profile != null) {
      final allowed = await PremiumGate.ensure(
        context,
        profile: profile,
        feature: QuotaFeature.annale,
        resourceId: paper.id,
      );
      if (!allowed || !mounted) return;
    }
    setState(() => _downloadingIds.add(paper.id));
    try {
      final path = await _service.download(paper);
      if (!mounted) return;
      setState(() => _localPaths[paper.id] = path);
      _snack(_fr ? 'Annale enregistrée pour la lecture hors ligne.' : 'Past paper saved for offline reading.');
    } catch (_) {
      if (mounted) {
        _snack(_fr
            ? 'Téléchargement impossible. Vérifie la connexion puis réessaie.'
            : 'Download failed. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(paper.id));
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  List<PastPaper> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _papers.where((paper) {
      if (_examId != null && paper.examId != _examId) return false;
      if (_year != null && paper.year != _year) return false;
      if (q.isNotEmpty &&
          !paper.subjectFr.toLowerCase().contains(q) &&
          !paper.subjectEn.toLowerCase().contains(q)) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final years = _papers.map((paper) => paper.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final examIds = _papers.map((paper) => paper.examId).whereType<String>().toSet();
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Annales d’examens' : 'Past exam papers'),
        actions: [
          IconButton(
            tooltip: _fr ? 'Actualiser' : 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(_fr ? 'Réessayer' : 'Retry'),
                      ),
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
                            decoration: InputDecoration(
                              labelText: _fr ? 'Examen' : 'Exam',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<String?>(value: null, child: Text(_fr ? 'Tous' : 'All')),
                              ...examIds.map((id) => DropdownMenuItem<String?>(
                                value: id,
                                child: Text(_exams[id]?.labelFor(widget.locale.languageCode) ?? id, overflow: TextOverflow.ellipsis),
                              )),
                            ],
                            onChanged: (value) => setState(() => _examId = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            initialValue: _year,
                            decoration: InputDecoration(
                              labelText: _fr ? 'Année' : 'Year',
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<int?>(value: null, child: Text(_fr ? 'Toutes' : 'All')),
                              ...years.map((year) => DropdownMenuItem<int?>(value: year, child: Text('$year'))),
                            ],
                            onChanged: (value) => setState(() => _year = value),
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
                                  ? (_fr ? 'Aucune annale publiée ou enregistrée sur cet appareil.' : 'No past papers published or cached on this device.')
                                  : (_fr ? 'Aucun résultat pour ces filtres.' : 'No results for these filters.'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ...items.map((paper) {
                        final exam = paper.examId == null ? null : _exams[paper.examId!];
                        final parts = <String>[
                          if (exam != null) exam.labelFor(widget.locale.languageCode),
                          '${paper.year}',
                          if (paper.session != null && paper.session!.isNotEmpty) paper.session!,
                        ];
                        final downloaded = _localPaths.containsKey(paper.id);
                        final downloading = _downloadingIds.contains(paper.id);
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: paper.isCorrection ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                              child: Icon(paper.isCorrection ? Icons.task_alt : Icons.description_outlined, color: const Color(0xFF166534)),
                            ),
                            title: Text(paper.subjectFor(widget.locale.languageCode), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${paper.isCorrection ? (_fr ? 'Corrigé' : 'Correction') : (_fr ? 'Sujet' : 'Paper')} · ${parts.join(' · ')}'
                              '${downloaded ? (_fr ? '\nDisponible hors ligne' : '\nAvailable offline') : ''}',
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (downloading)
                                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                IconButton(
                                  tooltip: downloaded
                                      ? (_fr ? 'Déjà téléchargé' : 'Downloaded')
                                      : (_fr ? 'Télécharger pour le mode hors ligne' : 'Download for offline'),
                                  onPressed: downloaded ? null : () => _download(paper),
                                  icon: Icon(downloaded ? Icons.download_done : Icons.download_for_offline_outlined),
                                ),
                              IconButton(
                                tooltip: _fr ? 'Ouvrir' : 'Open',
                                onPressed: () => _open(paper),
                                icon: const Icon(Icons.open_in_new),
                              ),
                            ]),
                            onTap: () => _open(paper),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
