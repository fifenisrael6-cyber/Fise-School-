import 'package:flutter/material.dart';

import '../../../core/services/bulletin_pdf.dart';
import '../../../core/services/grade_service.dart';
import '../../../models/grades.dart';

/// Bulletin d'un élève. Pour l'élève lui-même, seules les périodes publiées sont proposées.
class BulletinPage extends StatefulWidget {
  final Locale locale;
  final String studentId;
  final String studentName;
  final String? className;
  final bool onlyPublished;

  const BulletinPage({
    super.key,
    required this.locale,
    required this.studentId,
    required this.studentName,
    this.className,
    this.onlyPublished = true,
  });

  @override
  State<BulletinPage> createState() => _BulletinPageState();
}

class _BulletinPageState extends State<BulletinPage> {
  final _service = GradeService();
  bool _loadingPeriods = true;
  bool _loadingBulletin = false;
  String? _error;
  List<GradePeriod> _periods = const [];
  GradePeriod? _period;
  Bulletin? _bulletin;

  bool get _fr => widget.locale.languageCode == 'fr';
  String get _lang => widget.locale.languageCode;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    setState(() {
      _loadingPeriods = true;
      _error = null;
    });
    try {
      final periods = await _service.listPeriods(onlyPublished: widget.onlyPublished);
      if (!mounted) {
        return;
      }
      setState(() {
        _periods = periods;
        _loadingPeriods = false;
      });
      if (periods.isNotEmpty) {
        await _select(periods.last);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingPeriods = false;
        _error = _fr ? 'Impossible de charger les périodes.' : 'Unable to load periods.';
      });
    }
  }

  Future<void> _select(GradePeriod period) async {
    setState(() {
      _period = period;
      _loadingBulletin = true;
      _error = null;
      _bulletin = null;
    });
    try {
      final bulletin = await _service.bulletin(widget.studentId, period.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _bulletin = bulletin;
        _loadingBulletin = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingBulletin = false;
        _error = _fr ? 'Bulletin indisponible pour le moment.' : 'Report card unavailable right now.';
      });
    }
  }

  String _f(double? v) => v == null ? '-' : v.toStringAsFixed(2);

  Future<void> _pdf() async {
    final b = _bulletin;
    final p = _period;
    if (b == null || p == null) {
      return;
    }
    try {
      await BulletinPdf.share(
        bulletin: b,
        studentName: widget.studentName,
        className: widget.className ?? '-',
        periodLabel: p.labelFor(_lang),
        fr: _fr,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fr ? 'Création du PDF impossible.' : 'Unable to create the PDF.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bulletin;
    return Scaffold(
      appBar: AppBar(
        title: Text(_fr ? 'Bulletin de notes' : 'Report card'),
        actions: [
          if (b != null && b.lines.isNotEmpty)
            IconButton(
              tooltip: _fr ? 'Exporter en PDF' : 'Export as PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _pdf,
            ),
        ],
      ),
      body: _loadingPeriods
          ? const Center(child: CircularProgressIndicator())
          : _periods.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ??
                          (_fr
                              ? 'Aucun bulletin n’est encore publié.'
                              : 'No report card has been published yet.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.studentName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _period?.id,
                      decoration: InputDecoration(
                        labelText: _fr ? 'Période' : 'Period',
                        border: const OutlineInputBorder(),
                      ),
                      items: _periods
                          .map((p) => DropdownMenuItem(value: p.id, child: Text(p.labelFor(_lang))))
                          .toList(),
                      onChanged: (id) {
                        final p = _periods.firstWhere((e) => e.id == id);
                        _select(p);
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_loadingBulletin) const Center(child: CircularProgressIndicator()),
                    if (_error != null && !_loadingBulletin) Text(_error!),
                    if (b != null) ..._content(b),
                  ],
                ),
    );
  }

  List<Widget> _content(Bulletin b) {
    if (b.lines.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Center(child: Text(_fr ? 'Aucune note pour cette période.' : 'No marks for this period.')),
        ),
      ];
    }
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${_fr ? 'Moyenne générale' : 'Overall average'} : ${_f(b.average)} / 20',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('${_fr ? 'Rang' : 'Rank'} : ${b.rank ?? '-'} / ${b.classSize}'),
            Text('${_fr ? 'Moyenne de la classe' : 'Class average'} : ${_f(b.classAverage)}'),
            Text('${_fr ? 'Appréciation' : 'Remark'} : ${Bulletin.appreciation(b.average, _fr)}'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ...b.lines.map(
        (l) => Card(
          child: ListTile(
            title: Text(l.nameFor(_lang), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              'Coef. ${l.coefficient.toStringAsFixed(l.coefficient % 1 == 0 ? 0 : 1)}'
              ' · ${_fr ? 'classe' : 'class'} ${_f(l.classAverage)}'
              ' (${_f(l.classMin)} – ${_f(l.classMax)})'
              '${(l.comment ?? '').isEmpty ? '' : '\n${l.comment}'}',
            ),
            isThreeLine: (l.comment ?? '').isNotEmpty,
            trailing: Text(
              _f(l.score20),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: l.score20 >= 10 ? const Color(0xFF166534) : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
