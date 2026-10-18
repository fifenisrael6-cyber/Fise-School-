import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/grades.dart';

/// Génère et partage le bulletin au format PDF (texte sans caractères spéciaux
/// hors Latin-1, car la police standard du PDF ne les supporte pas).
class BulletinPdf {
  static String _f(double? v) => v == null ? '-' : v.toStringAsFixed(2);

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static Future<Uint8List> build({
    required Bulletin bulletin,
    required String studentName,
    required String className,
    required String periodLabel,
    required bool fr,
  }) async {
    final doc = pw.Document();
    final header = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _cell(fr ? 'Matiere' : 'Subject', bold: true),
        _cell(fr ? 'Note /20' : 'Mark /20', bold: true),
        _cell('Coef.', bold: true),
        _cell(fr ? 'Moy. classe' : 'Class avg', bold: true),
        _cell('Min', bold: true),
        _cell('Max', bold: true),
        _cell(fr ? 'Appreciation' : 'Remark', bold: true),
      ],
    );
    final rows = bulletin.lines
        .map(
          (l) => pw.TableRow(children: [
            _cell(l.nameFor(fr ? 'fr' : 'en')),
            _cell(_f(l.score20)),
            _cell(l.coefficient.toStringAsFixed(l.coefficient % 1 == 0 ? 0 : 1)),
            _cell(_f(l.classAverage)),
            _cell(_f(l.classMin)),
            _cell(_f(l.classMax)),
            _cell(Bulletin.appreciation(l.score20, fr)),
          ]),
        )
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('Fise School', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            fr ? 'Bulletin de notes - $periodLabel' : 'Report card - $periodLabel',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('${fr ? 'Eleve' : 'Student'} : $studentName'),
          pw.Text('${fr ? 'Salle' : 'Class'} : $className'),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(1),
              6: pw.FlexColumnWidth(2),
            },
            children: [header, ...rows],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '${fr ? 'Moyenne generale' : 'Overall average'} : ${_f(bulletin.average)} / 20',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('${fr ? 'Rang' : 'Rank'} : ${bulletin.rank ?? '-'} / ${bulletin.classSize}'),
          pw.Text('${fr ? 'Moyenne de la classe' : 'Class average'} : ${_f(bulletin.classAverage)}'),
          pw.Text('${fr ? 'Appreciation' : 'Remark'} : ${Bulletin.appreciation(bulletin.average, fr)}'),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> share({
    required Bulletin bulletin,
    required String studentName,
    required String className,
    required String periodLabel,
    required bool fr,
  }) {
    return Printing.layoutPdf(
      name: 'bulletin_${studentName.replaceAll(' ', '_')}',
      onLayout: (format) => build(
        bulletin: bulletin,
        studentName: studentName,
        className: className,
        periodLabel: periodLabel,
        fr: fr,
      ),
    );
  }
}
