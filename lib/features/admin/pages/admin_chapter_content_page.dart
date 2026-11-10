import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/widgets/course_image_embed.dart';
import '../../../core/widgets/course_table_embed.dart';
import '../../../core/widgets/lesson_content_renderer.dart';
import 'admin_chapter_assessments_page.dart';

/// Administration des chapitres. La sécurité des écritures est imposée par RLS.
class AdminChapterContentPage extends StatefulWidget {
  const AdminChapterContentPage({super.key, required this.locale});
  final Locale locale;
  @override
  State<AdminChapterContentPage> createState() => _AdminChapterContentPageState();
}
class _AdminChapterContentPageState extends State<AdminChapterContentPage> {
  final db = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();
  bool loading = true;
  String? error;
  List<Map<String,dynamic>> classes=[], subjects=[], curricula=[], chapters=[];
  Map<String,dynamic>? schoolClass, subject, curriculum, chapter;
  bool get fr => widget.locale.languageCode == 'fr';
  String t(String a,String b)=>fr?a:b;
  @override
  void initState(){super.initState();loadClasses();}
  Future<void> loadClasses() async {
    setState(()=>loading=true); error=null;
    try { final r=await db.from('school_classes').select('id,name,display_name,subsystem,sector,exam_level_id,series_id,specialty_id').eq('is_active',true).order('display_name'); classes=r.map((e)=>Map<String,dynamic>.from(e)).toList(); }
    catch(e){error=e.toString();}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> chooseClass(Map<String,dynamic>? v) async {
    setState(() { schoolClass=v; subject=null; curriculum=null; chapter=null; subjects=[]; curricula=[]; chapters=[]; loading=true; });
    if(v==null){if(mounted)setState(()=>loading=false);return;}
    try {final r=await db.from('class_subjects').select('subjects(id,name_fr,name_en,code)').eq('class_id',v['id']).eq('is_active',true).order('position');subjects=r.map((e)=>e['subjects']).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();}
    catch(e){error=e.toString();}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> chooseSubject(Map<String,dynamic>? v) async {
    setState(() { subject=v; curriculum=null; chapter=null; curricula=[]; chapters=[]; loading=true; });
    if(v==null||schoolClass==null){if(mounted)setState(()=>loading=false);return;}
    try {
      final r = await db.from('curricula').select().eq('subject_id', v['id']).eq('is_active', true).order('title_fr');
      final matching = r.map((e) => Map<String, dynamic>.from(e)).where((c) =>
        c['subsystem'] == schoolClass!['subsystem'] &&
        c['sector'] == schoolClass!['sector'] &&
        (c['exam_level_id'] == null || c['exam_level_id'] == schoolClass!['exam_level_id']) &&
        (c['series_id'] == null || c['series_id'] == schoolClass!['series_id']) &&
        (c['specialty_id'] == null || c['specialty_id'] == schoolClass!['specialty_id'])
      ).toList();
      final exactContainers = matching.where((c) =>
        c['is_catalog_container'] == true &&
        c['exam_level_id'] == schoolClass!['exam_level_id'] &&
        c['series_id'] == schoolClass!['series_id'] &&
        c['specialty_id'] == schoolClass!['specialty_id']
      ).toList();
      curricula = exactContainers.isNotEmpty ? exactContainers : matching.where((c) => c['is_catalog_container'] != true).toList();
    }
    catch(e){error=e.toString();}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> createCurriculum() async {
    if (schoolClass == null || subject == null) return;
    try {
      final className = (schoolClass!['display_name'] as String?) ??
          (schoolClass!['name'] as String?) ?? '';
      final subjectFr = (subject!['name_fr'] as String?) ?? 'Matière';
      final subjectEn = (subject!['name_en'] as String?) ?? 'Subject';
      await db.from('curricula').insert({
        'subject_id': subject!['id'],
        'subsystem': schoolClass!['subsystem'],
        'sector': schoolClass!['sector'],
        'exam_level_id': schoolClass!['exam_level_id'],
        'series_id': schoolClass!['series_id'],
        'specialty_id': schoolClass!['specialty_id'],
        'title_fr': 'Programme à compléter — $subjectFr ($className)',
        'title_en': 'Programme to complete — $subjectEn ($className)',
        'is_active': true,
      });
      await chooseSubject(subject);
      if (curricula.isNotEmpty) {
        await chooseCurriculum(curricula.first);
      }
      toast(t('Programme créé. Ajoute maintenant les chapitres et les contenus.',
          'Programme created. Now add chapters and content.'));
    } catch (e) {
      toast(e.toString());
    }
  }

  Future<void> chooseCurriculum(Map<String,dynamic>? v) async {
    setState(() { curriculum=v; chapter=null; chapters=[]; loading=true; });
    if(v==null){if(mounted)setState(()=>loading=false);return;}
    try{final r=await db.from('course_chapters').select().eq('curriculum_id',v['id']).order('position');chapters=r.map((e)=>Map<String,dynamic>.from(e)).toList();}
    catch(e){error=e.toString();}
    if(mounted)setState(()=>loading=false);
  }
  String label(Map<String,dynamic> m,String f,String e)=>(m[fr?f:e] as String?)??(m['display_name'] as String?)??'';
  void toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<bool> confirm(String s) async=>await showDialog<bool>(context:context,builder:(c)=>AlertDialog(content:Text(s),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(t('Confirmer','Confirm')))]))??false;
  QuillController _controllerFromStored(String? raw) {
    final value = raw ?? '';
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map && decoded['ops'] is List) {
        final operations = (decoded['ops'] as List)
            .whereType<Map>()
            .map((op) => Map<String, dynamic>.from(op))
            .toList(growable: false);
        if (operations.isNotEmpty) {
          return QuillController(
            document: Document.fromJson(operations),
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
      }
    } catch (_) {
      // Existing plain-text/Markdown lessons are converted without data loss.
    }
    final document = Document();
    if (value.isNotEmpty) document.insert(0, value);
    return QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Widget _buildCourseEditor(QuillController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: QuillSimpleToolbar(
            controller: controller,
            config: const QuillSimpleToolbarConfig(multiRowsDisplay: false),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _insertImage(controller),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(t('Ajouter une image ici', 'Insert image here')),
            ),
            OutlinedButton.icon(
              onPressed: () => _insertTable(controller),
              icon: const Icon(Icons.table_chart_outlined),
              label: Text(t('Insérer un tableau', 'Insert table')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 260, maxHeight: 420),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(8),
          child: QuillEditor.basic(
            controller: controller,
            config: QuillEditorConfig(
              padding: const EdgeInsets.all(8),
              expands: false,
              embedBuilders: [CourseTableEmbedBuilder(), CourseImageEmbedBuilder()],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _insertImage(QuillController controller) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      toast(t('Image vide ou illisible.', 'The image is empty or unreadable.'));
      return;
    }
    final extension = picked.name.split('.').last.toLowerCase();
    final mime = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final dataUri = 'data:' + mime + ';base64,' + base64Encode(bytes);
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start
        : controller.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    if (length > 0) {
      controller.replaceText(
        start, length, '', TextSelection.collapsed(offset: start),
      );
    }
    controller.document.insert(start, BlockEmbed.image(dataUri));
    controller.document.insert(start + 1, '\n');
    controller.updateSelection(
      TextSelection.collapsed(offset: start + 2),
      ChangeSource.local,
    );
  }

  Future<void> _insertTable(QuillController controller) async {
    final table = await showCourseTableDialog(context);
    if (table == null) return;
    final cells = (table['cells'] as List? ?? const [])
        .map((row) => (row as List).map((cell) => cell.toString()).toList())
        .toList();
    if (cells.isEmpty) return;
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start
        : controller.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    if (length > 0) {
      controller.replaceText(
        start, length, '', TextSelection.collapsed(offset: start),
      );
    }
    controller.document.insert(
      start,
      BlockEmbed.custom(CourseTableEmbed.fromCells(
        cells: cells,
        firstRowHeader: table['firstRowHeader'] == true,
      )),
    );
    controller.document.insert(start + 1, '\n');
    controller.updateSelection(
      TextSelection.collapsed(offset: start + 2),
      ChangeSource.local,
    );
  }

  Future<void> viewContent(Map<String, dynamic> item) async {
    final title = (item['title_fr'] ?? '').toString();
    final body = (item['body_text_fr'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title.isEmpty ? t('Aperçu du contenu', 'Content preview') : title),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (body.trim().isNotEmpty)
                  LessonContentRenderer(
                    text: body,
                    style: Theme.of(dialogContext).textTheme.bodyLarge ??
                        const TextStyle(fontSize: 16, height: 1.65),
                  )
                else
                  Text(t(
                    'Ce contenu est un fichier ou un média. Utilisez Modifier pour remplacer sa source.',
                    'This item is a file or media resource. Use Edit to replace its source.',
                  )),
                if ((item['storage_path'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    t('Fichier source conservé dans Supabase Storage.',
                      'Source file is preserved in Supabase Storage.'),
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('Fermer', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> editChapter([Map<String,dynamic>? old]) async {
    final n=TextEditingController(text:(old?['position']??(chapters.length+1)).toString()), f=TextEditingController(text:old?['title_fr'] as String? ?? ''), e=TextEditingController(text:old?['title_en'] as String? ?? '');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(t('Chapitre','Chapter')),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t('Numéro','Number'))),TextField(controller:f,decoration:const InputDecoration(labelText:'Titre français')),TextField(controller:e,decoration:const InputDecoration(labelText:'Titre anglais (facultatif)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(t('Enregistrer','Save')))]));
    if(ok!=true)return;if(f.text.trim().isEmpty){toast(t('Le titre français est obligatoire.','The French title is required.'));return;}
    try{final data={'curriculum_id':curriculum!['id'],'title_fr':f.text.trim(),'title_en':e.text.trim().isEmpty?f.text.trim():e.text.trim(),'position':int.tryParse(n.text)??chapters.length+1,'is_active':old?['is_active']??true};if(old==null){await db.from('course_chapters').insert(data);}else{await db.from('course_chapters').update(data).eq('id',old['id']);}await chooseCurriculum(curriculum);toast(t('Chapitre enregistré.','Chapter saved.'));}
    catch(e){toast(e.toString());}
  }
  Future<void> deleteChapter(Map<String,dynamic> ch) async {if(!await confirm(t('Supprimer ce chapitre et son contenu ?','Delete this chapter and its content?')))return;try{await db.from('course_chapters').delete().eq('id',ch['id']);if(chapter?['id']==ch['id'])chapter=null;await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> toggleChapter(Map<String,dynamic> ch) async {try{await db.from('course_chapters').update({'is_active':!(ch['is_active'] as bool? ?? true)}).eq('id',ch['id']);await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> addContent() async {
    if (chapter == null) return;
    final targetChapterId = chapter!['id'].toString();
    final titleFr = TextEditingController();
    final titleEn = TextEditingController();
    final bodyFr = QuillController.basic();
    final bodyEn = TextEditingController();
    final url = TextEditingController();
    final type = ValueNotifier<String>('course');
    final published = ValueNotifier<bool>(false);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(t('Ajouter un contenu','Add content')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) =>
          DropdownButtonFormField<String>(
            initialValue: v,
            items: [
              DropdownMenuItem(value: 'course', child: Text(t('Cours écrit','Written course'))),
              const DropdownMenuItem(value: 'video', child: Text('Vidéo')),
              const DropdownMenuItem(value: 'pdf', child: Text('PDF → leçons natives (IA)')),
              const DropdownMenuItem(value: 'image', child: Text('Image depuis le téléphone')),
              const DropdownMenuItem(value: 'audio', child: Text('Audio depuis le téléphone')),
            ],
            onChanged: (next) { if (next != null) type.value = next; },
          )),
        TextField(controller: titleFr, decoration: const InputDecoration(labelText: 'Titre français')),
        ExpansionTile(title:Text(t('Traduction anglaise (facultative)','English translation (optional)')),children:[TextField(controller:titleEn,decoration:const InputDecoration(labelText:'English title'))]),
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) => Column(children: [
          if (v == 'course') ...[
            _buildCourseEditor(bodyFr),
            ExpansionTile(title:Text(t('Traduction anglaise du cours (facultative)','Optional English lesson translation')),children:[TextField(controller:bodyEn,maxLines:8,decoration:const InputDecoration(labelText:'English lesson'))]),
          ],
          if (v == 'video') TextField(controller: url, decoration: const InputDecoration(labelText: 'Lien vidéo direct MP4 ou YouTube/Vimeo')),
          if (v == 'pdf' || v == 'image' || v == 'audio') Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(v == 'pdf'
                ? t('Le PDF sera converti en leçons natives. Les leçons seront créées en brouillon pour vérification avant publication.','Choose a PDF to convert into native lessons. Imported lessons remain drafts until you review and publish them.')
                : v == 'image'
                    ? t('L’image sera choisie sur le téléphone après validation.','Choose the image from your phone after confirming.')
                    : t('Le fichier audio sera choisi sur le téléphone après validation.','Choose the audio file from your phone after confirming.')),
          ),
        ])),
        ValueListenableBuilder<bool>(valueListenable: published, builder: (_, v, __) =>
          SwitchListTile(value: v, title: Text(t('Publier pour les élèves','Publish for students')),
            onChanged: (next) => published.value = next)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Annuler','Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Enregistrer','Save'))),
      ],
    ));
    if (ok != true) return;
    if (titleFr.text.trim().isEmpty) {
      toast(t('Le titre français est obligatoire.','The French title is required.')); return;
    }
    String? storagePath;
    try {
      if (type.value == 'course' && bodyFr.document.toPlainText().trim().isEmpty) {
        toast(t('Le contenu du cours en français est obligatoire.','French lesson content is required.')); return;
      }
      if (type.value == 'video' && url.text.trim().isEmpty) {
        toast(t('Le lien vidéo est obligatoire.','A video URL is required.')); return;
      }
      if (type.value == 'pdf' || type.value == 'image' || type.value == 'audio') {
        final extensions = type.value == 'pdf'
            ? ['pdf']
            : type.value == 'image'
                ? ['jpg', 'jpeg', 'png', 'webp']
                : ['mp3', 'm4a', 'aac', 'wav', 'ogg'];
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: extensions, withData: true,
        );
        if (picked == null || picked.files.isEmpty) return;
        final file = picked.files.single;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          toast(t('Impossible de lire ce fichier.','Unable to read this file.')); return;
        }
        if (type.value == 'pdf' && bytes.length > 25 * 1024 * 1024) {
          toast(t('Le PDF dépasse la limite de 25 Mo. Divise-le en plusieurs fichiers.',
              'The PDF exceeds the 25 MB limit. Split it into smaller files.'));
          return;
        }
        if (type.value == 'pdf' &&
            (bytes.length < 5 ||
             String.fromCharCodes(bytes.take(5)) != '%PDF-')) {
          toast(t('Le fichier sélectionné n’est pas un PDF valide.',
              'The selected file is not a valid PDF.'));
          return;
        }
        final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        storagePath = chapter!['id'].toString() + '/' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName;
        final ext = p.extension(file.name).toLowerCase();
        final mimeType = type.value == 'pdf'
            ? 'application/pdf'
            : type.value == 'image'
                ? (ext == '.png' ? 'image/png' : ext == '.webp' ? 'image/webp' : 'image/jpeg')
                : (ext == '.wav' ? 'audio/wav' : ext == '.ogg' ? 'audio/ogg' : ext == '.m4a' ? 'audio/mp4' : 'audio/mpeg');
        await db.storage.from('chapter-content').uploadBinary(
          storagePath, bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
      }
      final existing = await db.from('chapter_content_items').select('id').eq('chapter_id', chapter!['id']);
      final inserted = await db.from('chapter_content_items').insert({
        'chapter_id': chapter!['id'],
        'content_type': type.value,
        'title_fr': titleFr.text.trim(),
        'title_en': titleEn.text.trim().isEmpty ? titleFr.text.trim() : titleEn.text.trim(),
        'body_text_fr': type.value == 'course' ? jsonEncode(bodyFr.document.toDelta().toJson()) : null,
        'body_text_en': type.value == 'course' ? (bodyEn.text.trim().isEmpty ? bodyFr.document.toPlainText().trim() : bodyEn.text.trim()) : null,
        'external_url': type.value == 'video' ? url.text.trim() : null,
        'storage_path': storagePath,
        'position': existing.length + 1,
        'is_published': published.value,
        'created_by': db.auth.currentUser?.id,
      }).select('id').single();

      if (type.value == 'pdf') {
        toast(t('PDF envoyé. Extraction et organisation des leçons en cours…',
            'PDF uploaded. Extracting and organizing lessons…'));
        try {
          final result = await db.functions.invoke(
            'import-chapter-pdf',
            body: {'content_item_id': inserted['id']},
          );
          final data = result.data;
          if (result.status >= 200 && result.status < 300 &&
              data is Map && data['success'] == true) {
            final imported = data['imported'] ?? 0;
            final existingCount = data['already_exists'] ?? 0;
            final targetRooms = data['target_rooms'] is List
                ? (data['target_rooms'] as List)
                    .whereType<Map>()
                    .map((room) => room['name']?.toString() ?? '')
                    .where((name) => name.trim().isNotEmpty)
                    .toList(growable: false)
                : const <String>[];
            final roomSummary = targetRooms.isEmpty
                ? t('aucune salle correspondante détectée', 'no matching classroom detected')
                : targetRooms.take(3).join(', ') +
                    (targetRooms.length > 3 ? ' +${targetRooms.length - 3}' : '');
            final linkedChapters = (data['report'] is List)
                ? (data['report'] as List).fold<int>(0, (sum, row) =>
                    sum + ((row is Map ? row['linked_chapters'] as num? : null)?.toInt() ?? 0))
                : 0;
            toast(t(
              'Analyse terminée : $imported leçon(s) créée(s), $existingCount déjà existante(s). Salles concernées : $roomSummary. $linkedChapters liaison(s) de chapitre. Les leçons restent en brouillon : vérifiez puis publiez-les.',
              'Analysis complete: $imported lesson(s) created, $existingCount already existed. Matching classrooms: $roomSummary. $linkedChapters chapter link(s). Lessons remain drafts until reviewed and published.',
            ));
          } else {
            final message = data is Map
                ? (data['error']?.toString() ?? 'Erreur d’analyse inconnue.')
                : 'Réponse du serveur invalide.';
            toast(t('PDF conservé, mais conversion échouée : $message',
                'PDF saved, but conversion failed: $message'));
          }
        } catch (importError) {
          toast(t('PDF conservé dans Supabase, mais conversion échouée : $importError',
              'PDF saved in Supabase, but conversion failed: $importError'));
        }
      }

      await chooseCurriculum(curriculum);
      if (type.value == 'course' && published.value) {
        try {
          await db.functions.invoke('chapter-quiz', body: {'chapter_id': targetChapterId});
          toast(t('Cours publié et QCM généré par l’IA.', 'Course published and AI quiz generated.'));
        } catch (quizError) {
          toast(t('Cours publié. QCM IA non généré : $quizError',
                  'Course published. AI quiz was not generated: $quizError'));
        }
      } else {
        toast(t('Contenu ajouté.', 'Content added.'));
      }
    } catch (e) {
      if (storagePath != null) {
        try { await db.storage.from('chapter-content').remove([storagePath]); } catch (_) {}
      }
      toast(e.toString());
    }
  }

  Future<void> restoreCourseFromPdf(Map<String, dynamic> item) async {
    if (item['content_type'] != 'pdf' ||
        (item['storage_path'] as String? ?? '').isEmpty) {
      toast(t('Le PDF source est introuvable.', 'The source PDF is unavailable.'));
      return;
    }
    final ok = await confirm(t(
      'Reconstruire le cours à partir du PDF original ? Le contenu existant sera conservé si la génération échoue. Son état publié/masqué sera préservé.',
      'Rebuild the lesson from its original PDF? Existing content stays intact if generation fails. Its published/hidden state will be preserved.',
    ));
    if (!ok) return;
    try {
      toast(t('Restauration du cours en cours…', 'Restoring lesson…'));
      final result = await db.functions.invoke(
        'import-chapter-pdf',
        body: {'content_item_id': item['id'], 'restore_existing': true},
      );
      final data = result.data;
      if (result.status >= 200 && result.status < 300 &&
          data is Map && data['success'] == true) {
        final count = data['restored'] ?? 0;
        toast(t(
          'Restauration terminée : $count cours actualisé(s). Les anciens cours restent publiés comme avant.',
          'Restoration complete: $count lesson(s) updated. Existing publication settings were preserved.',
        ));
        if (mounted) setState(() {});
      } else {
        final message = data is Map
            ? (data['error']?.toString() ?? 'Erreur de restauration.')
            : 'Réponse serveur invalide.';
        toast(t('Restauration impossible : $message',
            'Restoration failed: $message'));
      }
    } catch (e) {
      toast(t('Restauration impossible : $e', 'Restoration failed: $e'));
    }
  }

  Future<void> editContent(Map<String, dynamic> item) async {
    final targetChapterId = chapter?['id']?.toString();
    final type = item['content_type'] as String? ?? 'course';
    final titleFr = TextEditingController(text: item['title_fr'] as String? ?? '');
    final titleEn = TextEditingController(text: item['title_en'] as String? ?? '');
    final bodyFr = _controllerFromStored(item['body_text_fr'] as String?);
    final bodyEn = TextEditingController(text: item['body_text_en'] as String? ?? '');
    final url = TextEditingController(text: item['external_url'] as String? ?? '');
    final published = ValueNotifier<bool>(item['is_published'] as bool? ?? false);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(t('Modifier le contenu', 'Edit content')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleFr, decoration: const InputDecoration(labelText: 'Titre du contenu')),
        ExpansionTile(
          title: Text(t('Traduction anglaise (facultative)', 'Optional English translation')),
          children: [
            TextField(controller: titleEn, decoration: const InputDecoration(labelText: 'English title')),
          ],
        ),
        if (type == 'course') ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              t('Mise en forme : ## pour un sous-titre, **mot** pour le gras, - pour une liste, \$...\$ pour une formule. Le cours français suffit ; la traduction est facultative.',
                'Formatting: ## for a heading, **word** for bold, - for a list, \$...\$ for a formula. French content is enough; translation is optional.'),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          _buildCourseEditor(bodyFr),
          ExpansionTile(
            title: Text(t('Traduction anglaise du cours (facultative)', 'Optional English lesson translation')),
            children: [
              TextField(controller: bodyEn, maxLines: 10, decoration: const InputDecoration(labelText: 'English lesson')),
            ],
          ),
        ],
        if (type == 'video') TextField(controller: url, decoration: const InputDecoration(labelText: 'Lien vidéo MP4, YouTube ou Vimeo')),
        if (type == 'pdf') Text(t('Le PDF actuel est conservé. Choisis un nouveau PDF pour le remplacer.',
            'The current PDF is kept. Choose a new PDF to replace it.')),
        ValueListenableBuilder<bool>(valueListenable: published, builder: (_, v, __) =>
          SwitchListTile(value: v, title: Text(t('Publier pour les élèves', 'Publish for students')),
            onChanged: (next) => published.value = next)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Annuler', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Enregistrer', 'Save'))),
      ],
    ));
    if (ok != true) return;
    if (titleFr.text.trim().isEmpty) {
      toast(t('Le titre français est obligatoire.', 'The French title is required.'));
      return;
    }
    if (type == 'course' && bodyFr.document.toPlainText().trim().isEmpty) {
      toast(t('Le contenu du cours en français est obligatoire.', 'French lesson content is required.'));
      return;
    }
    if (type == 'video' && url.text.trim().isEmpty) {
      toast(t('Le lien vidéo est obligatoire.', 'A video URL is required.'));
      return;
    }
    String? replacementPath;
    final oldPath = item['storage_path'] as String?;
    try {
      if (type == 'pdf' || type == 'image' || type == 'audio') {
        final extensions = type == 'pdf'
            ? ['pdf']
            : type == 'image'
                ? ['jpg', 'jpeg', 'png', 'webp']
                : ['mp3', 'm4a', 'aac', 'wav', 'ogg'];
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: extensions, withData: true,
        );
        if (picked != null && picked.files.isNotEmpty) {
          final file = picked.files.single;
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) {
            toast(t('Impossible de lire ce PDF.', 'Unable to read this PDF.'));
            return;
          }
          final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
          replacementPath = '${chapter!['id']}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
          final ext = p.extension(file.name).toLowerCase();
          final mimeType = type == 'pdf'
              ? 'application/pdf'
              : type == 'image'
                  ? (ext == '.png' ? 'image/png' : ext == '.webp' ? 'image/webp' : 'image/jpeg')
                  : (ext == '.wav' ? 'audio/wav' : ext == '.ogg' ? 'audio/ogg' : ext == '.m4a' ? 'audio/mp4' : 'audio/mpeg');
          await db.storage.from('chapter-content').uploadBinary(
            replacementPath, bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
        }
      }
      final data = <String, dynamic>{
        'title_fr': titleFr.text.trim(),
        'title_en': titleEn.text.trim().isEmpty ? titleFr.text.trim() : titleEn.text.trim(),
        'is_published': published.value,
      };
      if (type == 'course') {
        data['body_text_fr'] = jsonEncode(bodyFr.document.toDelta().toJson());
        data['body_text_en'] = bodyEn.text.trim().isEmpty ? bodyFr.text.trim() : bodyEn.text.trim();
      } else if (type == 'video') {
        data['external_url'] = url.text.trim();
      } else if (replacementPath != null) {
        data['storage_path'] = replacementPath;
      }
      await db.from('chapter_content_items').update(data).eq('id', item['id']);
      if (replacementPath != null && oldPath != null && oldPath.isNotEmpty) {
        try { await db.storage.from('chapter-content').remove([oldPath]); } catch (_) {}
      }
      if (mounted) setState(() {});
      if (type == 'course' && published.value && targetChapterId != null) {
        try {
          await db.functions.invoke('chapter-quiz', body: {'chapter_id': targetChapterId});
          toast(t('Cours publié et QCM IA actualisé.', 'Course published and AI quiz refreshed.'));
        } catch (quizError) {
          toast(t('Cours enregistré, mais QCM IA non généré : $quizError',
                  'Course saved, but AI quiz was not generated: $quizError'));
        }
      } else {
        toast(t('Contenu modifié.', 'Content updated.'));
      }
    } catch (e) {
      if (replacementPath != null) {
        try { await db.storage.from('chapter-content').remove([replacementPath]); } catch (_) {}
      }
      toast(e.toString());
    }
  }

  Future<void> toggleContent(Map<String, dynamic> item) async {
    final willPublish = !(item['is_published'] as bool? ?? false);
    final targetChapterId = item['chapter_id']?.toString() ?? chapter?['id']?.toString();
    try {
      await db.from('chapter_content_items')
          .update({'is_published': willPublish})
          .eq('id', item['id']);
      if (mounted) setState(() {});
      if (willPublish && item['content_type'] == 'course' && targetChapterId != null) {
        try {
          await db.functions.invoke('chapter-quiz', body: {'chapter_id': targetChapterId});
          toast(t('Cours publié et QCM IA généré.', 'Course published and AI quiz generated.'));
        } catch (quizError) {
          toast(t('Cours publié. QCM IA non généré : $quizError',
                  'Course published. AI quiz was not generated: $quizError'));
        }
      } else {
        toast(t(willPublish ? 'Contenu publié.' : 'Contenu masqué.',
                willPublish ? 'Content published.' : 'Content hidden.'));
      }
    } catch (e) { toast(e.toString()); }
  }

  Future<void> deleteContent(Map<String, dynamic> item) async {
    if (!await confirm(t('Supprimer ce contenu ?', 'Delete this content?'))) return;
    try {
      final storagePath = item['storage_path'] as String?;
      if (storagePath != null && storagePath.isNotEmpty) {
        await db.storage.from('chapter-content').remove([storagePath]);
      }
      await db.from('chapter_content_items').delete().eq('id', item['id']);
      if (mounted) setState(() {});
      toast(t('Contenu supprimé.', 'Content deleted.'));
    } catch (e) { toast(e.toString()); }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Gestion des chapitres','Chapter management'))),floatingActionButton:chapter==null?null:FloatingActionButton.extended(onPressed:addContent,icon:const Icon(Icons.add),label:Text(t('Ajouter un contenu','Add content')),),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!)):RefreshIndicator(onRefresh:loadClasses,child:ListView(padding:const EdgeInsets.all(16),children:[
    DropdownButtonFormField<Map<String,dynamic>>(value:schoolClass,isExpanded:true,decoration:InputDecoration(labelText:t('1. Classe','1. Class')),items:classes.map((v)=>DropdownMenuItem(value:v,child:Text(label(v,'display_name','display_name')))).toList(),onChanged:chooseClass),
    const SizedBox(height:12),DropdownButtonFormField<Map<String,dynamic>>(value:subject,isExpanded:true,decoration:InputDecoration(labelText:t('2. Matière','2. Subject')),items:subjects.map((v)=>DropdownMenuItem(value:v,child:Text(label(v,'name_fr','name_en')))).toList(),onChanged:chooseSubject),
    const SizedBox(height:12),DropdownButtonFormField<Map<String,dynamic>>(value:curriculum,isExpanded:true,decoration:InputDecoration(labelText:t('3. Programme','3. Curriculum')),items:curricula.map((v)=>DropdownMenuItem(value:v,child:Text(label(v,'title_fr','title_en')))).toList(),onChanged:chooseCurriculum),
    if(subject!=null && curricula.isEmpty)
      Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton.icon(
        onPressed:createCurriculum,
        icon:const Icon(Icons.add_circle_outline),
        label:Text(t('Créer le programme de cette classe','Create this class programme')),
      )),
    if(curriculum!=null)Row(children:[Expanded(child:Text(t('Chapitres au programme','Programme chapters'),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))),IconButton(onPressed:()=>editChapter(),icon:const Icon(Icons.add_circle,color:Color(0xFF166534)))]),
    for(final ch in chapters)Card(child:ListTile(title:Text(label(ch,'title_fr','title_en')),subtitle:Text((ch['is_active'] as bool? ?? true)?t('Visible','Visible'):t('Masqué','Hidden')),selected:chapter?['id']==ch['id'],onTap:()=>setState(()=>chapter=ch),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')editChapter(ch);if(v=='hide')toggleChapter(ch);if(v=='delete')deleteChapter(ch);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(t('Modifier','Edit'))),PopupMenuItem(value:'hide',child:Text(t('Masquer / afficher','Hide / show'))),PopupMenuItem(value:'delete',child:Text(t('Supprimer','Delete')))]))),
    if(chapter!=null) ...[
      Padding(padding:const EdgeInsets.only(top:20),child:Text(t('Chapitre sélectionné : ','Selected chapter: ')+label(chapter!,'title_fr','title_en'),style:const TextStyle(fontWeight:FontWeight.bold))),
      const SizedBox(height:8),
      FilledButton.icon(
        onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminChapterAssessmentsPage(chapterId:chapter!['id'].toString(),chapterTitle:label(chapter!,'title_fr','title_en'),locale:widget.locale))),
        icon:const Icon(Icons.quiz_outlined),
        label:Text(t('Gérer exercices et quiz','Manage exercises and quizzes')),
      ),
      FutureBuilder<List<Map<String,dynamic>>>(
        future:db.from('chapter_content_items').select().eq('chapter_id',chapter!['id']).order('position').then((rows)=>rows.map((r)=>Map<String,dynamic>.from(r)).toList()),
        builder:(context,snapshot){
          if(snapshot.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()));
          if(snapshot.hasError)return Text(snapshot.error.toString());
          final items=snapshot.data??const <Map<String,dynamic>>[];
          if(items.isEmpty)return Padding(padding:const EdgeInsets.all(12),child:Text(t('Aucun contenu ajouté.','No content added yet.')));
          return Column(children:items.map((item)=>Card(child:ListTile(
            leading:Icon(item['content_type']=='pdf'?Icons.picture_as_pdf:item['content_type']=='video'?Icons.play_circle:Icons.menu_book),
            title:Text((item['title_fr'] as String?)??''),
            subtitle:Text((item['is_published'] as bool? ?? false)?t('Publié','Published'):t('Masqué','Hidden')),
            onTap: () => viewContent(item),
            trailing:PopupMenuButton<String>(
              onSelected:(v){if(v=='view')viewContent(item);if(v=='restore')restoreCourseFromPdf(item);if(v=='edit')editContent(item);if(v=='toggle')toggleContent(item);if(v=='delete')deleteContent(item);},
              itemBuilder:(_)=>[
                PopupMenuItem(value:'view',child:Text(t('Voir le cours','View course'))),
                if (item['content_type'] == 'pdf' && (item['storage_path'] as String? ?? '').isNotEmpty)
                  PopupMenuItem(value:'restore',child:Text(t('Restaurer le cours depuis ce PDF','Restore lesson from this PDF'))),
                PopupMenuItem(value:'edit',child:Text(t('Modifier','Edit'))),
                PopupMenuItem(value:'toggle',child:Text(t('Masquer / publier','Hide / publish'))),
                PopupMenuItem(value:'delete',child:Text(t('Supprimer','Delete'))),
              ],
            ),
          ))).toList());
        },
      ),
    ]
  ])));
}
