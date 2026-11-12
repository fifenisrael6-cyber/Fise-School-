import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'admin_chapter_assessments_page.dart';
import 'course_notebook_editor_page.dart';
import '../../../core/services/course_pdf_page_service.dart';

/// Administration des chapitres. La sécurité des écritures est imposée par RLS.
class AdminChapterContentPage extends StatefulWidget {
  const AdminChapterContentPage({super.key, required this.locale});
  final Locale locale;
  @override
  State<AdminChapterContentPage> createState() => _AdminChapterContentPageState();
}
class _AdminChapterContentPageState extends State<AdminChapterContentPage> {
  final db = Supabase.instance.client;
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
  Future<void> editChapter([Map<String,dynamic>? old]) async {
    final n=TextEditingController(text:(old?['position']??(chapters.length+1)).toString()), f=TextEditingController(text:old?['title_fr'] as String? ?? ''), e=TextEditingController(text:old?['title_en'] as String? ?? '');
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(t('Chapitre','Chapter')),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t('Numéro','Number'))),TextField(controller:f,decoration:const InputDecoration(labelText:'Titre français')),TextField(controller:e,decoration:const InputDecoration(labelText:'Titre anglais (facultatif)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(t('Enregistrer','Save')))]));
    if(ok!=true)return;if(f.text.trim().isEmpty){toast(t('Le titre français est obligatoire.','The French title is required.'));return;}
    try{final data={'curriculum_id':curriculum!['id'],'title_fr':f.text.trim(),'title_en':e.text.trim().isEmpty?f.text.trim():e.text.trim(),'position':int.tryParse(n.text)??chapters.length+1,'is_active':old?['is_active']??true};if(old==null){await db.from('course_chapters').insert(data);}else{await db.from('course_chapters').update(data).eq('id',old['id']);}await chooseCurriculum(curriculum);toast(t('Chapitre enregistré.','Chapter saved.'));}
    catch(e){toast(e.toString());}
  }
  Future<void> deleteChapter(Map<String,dynamic> ch) async {if(!await confirm(t('Supprimer ce chapitre et son contenu ?','Delete this chapter and its content?')))return;try{await db.from('course_chapters').delete().eq('id',ch['id']);if(chapter?['id']==ch['id'])chapter=null;await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> toggleChapter(Map<String,dynamic> ch) async {try{await db.from('course_chapters').update({'is_active':!(ch['is_active'] as bool? ?? true)}).eq('id',ch['id']);await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> addContent() => uploadPdfCourse();

  /// Un seul document source représente le cours du chapitre.
  /// Le PDF reste privé dans Storage ; l'élève voit uniquement le lecteur de cours.
  Future<void> uploadPdfCourse({Map<String, dynamic>? existingItem}) async {
    final selectedChapter = chapter;
    if (selectedChapter == null) return;

    String? uploadedPath;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.length < 5 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        toast(t('Le fichier sélectionné n’est pas un PDF valide.',
            'The selected file is not a valid PDF.'));
        return;
      }

      Map<String, dynamic>? current = existingItem;
      if (current == null) {
        final rows = await db
            .from('chapter_content_items')
            .select()
            .eq('chapter_id', selectedChapter['id'])
            .eq('content_type', 'course')
            .order('position')
            .limit(1);
        if (rows.isNotEmpty) current = Map<String, dynamic>.from(rows.first);
      }

      final oldSource = (current?['source_pdf_path'] as String? ?? '').trim();
      final oldStorage = (current?['storage_path'] as String? ?? '').trim();
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      uploadedPath = '${selectedChapter['id']}/course_${timestamp}_$safeName';
      await db.storage.from('chapter-content').uploadBinary(
        uploadedPath,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'application/pdf',
          upsert: false,
        ),
      );

      final rawTitle = p.basenameWithoutExtension(file.name).trim();
      final title = rawTitle.isEmpty ? t('Cours', 'Course') : rawTitle;
      final rowData = <String, dynamic>{
        'chapter_id': selectedChapter['id'],
        'content_type': 'course',
        'title_fr': current == null ? title : (current['title_fr'] ?? title),
        'title_en': current == null
            ? title
            : (current['title_en'] ?? current['title_fr'] ?? title),
        'body_text_fr': current?['body_text_fr'] ?? ' ',
        'body_text_en': current?['body_text_en'] ?? ' ',
        'source_pdf_path': uploadedPath,
        'source_page_start': 1,
        'source_page_end': null,
        'folder_key': 'course',
        'position': current?['position'] ?? 0,
        'is_published': current?['is_published'] == true,
      };

      Map<String, dynamic> saved;
      if (current == null) {
        final inserted = await db
            .from('chapter_content_items')
            .insert(rowData)
            .select()
            .single();
        saved = Map<String, dynamic>.from(inserted);
      } else {
        final updated = await db
            .from('chapter_content_items')
            .update(rowData)
            .eq('id', current['id'])
            .select()
            .single();
        saved = Map<String, dynamic>.from(updated);
      }

      if (saved['is_published'] == true) {
        try {
          await CoursePdfPageService(db).regenerate({
            ...saved,
            'source_bucket': 'chapter-content',
          });
        } catch (error) {
          await db.from('chapter_content_items')
              .update({'is_published': false}).eq('id', saved['id']);
          toast(t('Le PDF a été enregistré mais sa préparation a échoué. Le cours reste masqué : $error',
              'The PDF was saved but page preparation failed. The course remains hidden: $error'));
          if (mounted) await chooseCurriculum(curriculum);
          return;
        }
      }

      for (final oldPath in {oldSource, oldStorage}) {
        if (oldPath.isNotEmpty && oldPath != uploadedPath) {
          try { await db.storage.from('chapter-content').remove([oldPath]); } catch (_) {}
        }
      }
      uploadedPath = null;
      if (mounted) {
        await chooseCurriculum(curriculum);
        toast(t('Cours PDF enregistré. Il est visible aux élèves selon son statut de publication.',
            'Course document saved. Students can see it according to its publication status.'));
      }
    } catch (error) {
      if (uploadedPath != null) {
        try { await db.storage.from('chapter-content').remove([uploadedPath]); } catch (_) {}
      }
      toast(t('Envoi du cours impossible : $error', 'Could not upload the course: $error'));
    }
  }

  Future<void> regenerateCoursePages(Map<String, dynamic> item) async {
    try {
      toast(t('Régénération des pages en cours…', 'Regenerating course pages…'));
      final count = await CoursePdfPageService(db).regenerate(item);
      toast(t('Régénération terminée : $count page(s).',
          'Regeneration complete: $count page(s).'));
      if (mounted) setState(() {});
    } catch (error) {
      toast(t('Régénération impossible : $error',
          'Could not regenerate pages: $error'));
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
        final reportRows = (data['report'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        final itemIds = reportRows
            .map((row) => row['content_item_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);

        var rasterizedPages = 0;
        if (itemIds.isNotEmpty) {
          final restoredItems = await db
              .from('chapter_content_items')
              .select('id,source_pdf_path,source_page_start,source_page_end')
              .inFilter('id', itemIds);
          for (final restored in restoredItems) {
            final sourcePdfPath =
                (restored['source_pdf_path'] as String? ?? '').trim();
            if (sourcePdfPath.isEmpty) continue;
            rasterizedPages += await CoursePdfPageService(db).regenerate({
              ...Map<String, dynamic>.from(restored),
              'storage_path': sourcePdfPath,
              'source_bucket': 'chapter-content',
            });
          }
        }

        final count = data['restored'] ?? 0;
        toast(t(
          'Restauration terminée : $count cours actualisé(s), $rasterizedPages page(s) A4 préparée(s). Les PDF originaux, schémas et formules sont conservés.',
          'Restoration complete: $count lesson(s) updated and $rasterizedPages A4 page(s) prepared. Original PDFs, diagrams and formulas are preserved.',
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
    if (type == 'course') {
      await uploadPdfCourse(existingItem: item);
      return;
    }
    final titleFr = TextEditingController(text: item['title_fr'] as String? ?? '');
    final titleEn = TextEditingController(text: item['title_en'] as String? ?? '');
    final bodyFr = TextEditingController(text: item['body_text_fr'] as String? ?? '');
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
          TextField(controller: bodyFr, maxLines: 14, decoration: const InputDecoration(labelText: 'Cours complet en français')),
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
    if (type == 'course' && bodyFr.text.trim().isEmpty) {
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
        data['body_text_fr'] = bodyFr.text.trim();
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
      if (willPublish &&
          item['content_type'] == 'course' &&
          (item['source_pdf_path'] as String? ?? '').trim().isNotEmpty) {
        try {
          final count = await CoursePdfPageService(db).regenerate(item);
          toast(t('Pages du cours préparées : $count page(s).',
              'Course pages prepared: $count page(s).'));
        } catch (pageError) {
          toast(t('Publication bloquée : conversion des pages impossible. $pageError',
              'Publication blocked: page conversion failed. $pageError'));
          return;
        }
      }
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
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(t('Gestion des chapitres','Chapter management'))),floatingActionButton:chapter==null?null:FloatingActionButton.extended(onPressed:addContent,icon:const Icon(Icons.add),label:Text(t('Créer un cours A4 / ajouter une ressource','Create A4 course / add resource')),),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!)):RefreshIndicator(onRefresh:loadClasses,child:ListView(padding:const EdgeInsets.all(16),children:[
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
    for(final ch in chapters)Card(child:ListTile(title:Text(label(ch,'title_fr','title_en')),subtitle:Text((ch['is_active'] as bool? ?? true)?t('Visible','Visible'):t('Masqué','Hidden')),selected:chapter?['id']==ch['id'],onTap:()=>setState(()=>chapter=ch),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')editChapter(ch);if(v=='hide')toggleChapter(ch);if(v=='delete')deleteChapter(ch);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(t('Modifier','Edit'))),
                PopupMenuItem(value:'hide',child:Text(t('Masquer / afficher','Hide / show'))),PopupMenuItem(value:'delete',child:Text(t('Supprimer','Delete')))]))),
    if(chapter!=null) ...[
      Padding(padding:const EdgeInsets.only(top:20),child:Text(t('Chapitre sélectionné : ','Selected chapter: ')+label(chapter!,'title_fr','title_en'),style:const TextStyle(fontWeight:FontWeight.bold))),
      const SizedBox(height:8),
      FilledButton.icon(
        onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminChapterAssessmentsPage(chapterId:chapter!['id'].toString(),chapterTitle:label(chapter!,'title_fr','title_en'),locale:widget.locale))),
        icon:const Icon(Icons.quiz_outlined),
        label:Text(t('Gérer exercices et quiz','Manage exercises and quizzes')),
      ),
      const SizedBox(height: 8),
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
            trailing:PopupMenuButton<String>(
              onSelected:(v){if(v=='restore')restoreCourseFromPdf(item);if(v=='regenerate')regenerateCoursePages(item);if(v=='edit')editContent(item);if(v=='toggle')toggleContent(item);if(v=='delete')deleteContent(item);},
              itemBuilder:(_)=>[
                if (item['content_type'] == 'pdf' && (item['storage_path'] as String? ?? '').isNotEmpty)
                  PopupMenuItem(value:'restore',child:Text(t('Restaurer le cours depuis ce PDF','Restore lesson from this PDF'))),
                PopupMenuItem(value:'edit',child:Text(t('Modifier','Edit'))),
                if (item['content_type'] == 'course' &&
                    (item['source_pdf_path'] as String? ?? '').trim().isNotEmpty)
                  PopupMenuItem(value:'regenerate',child:Text(t('Régénérer les pages','Regenerate pages'))),
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
