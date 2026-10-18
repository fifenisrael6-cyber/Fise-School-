import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
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
    try {final r=await db.from('curricula').select().eq('subject_id',v['id']).eq('is_active',true).order('title_fr');curricula=r.map((e)=>Map<String,dynamic>.from(e)).where((c)=>c['subsystem']==schoolClass!['subsystem']&&c['sector']==schoolClass!['sector']&&(c['exam_level_id']==null||c['exam_level_id']==schoolClass!['exam_level_id'])&&(c['series_id']==null||c['series_id']==schoolClass!['series_id'])&&(c['specialty_id']==null||c['specialty_id']==schoolClass!['specialty_id'])).toList();}
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
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(t('Chapitre','Chapter')),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:t('Numéro','Number'))),TextField(controller:f,decoration:const InputDecoration(labelText:'Titre français')),TextField(controller:e,decoration:const InputDecoration(labelText:'English title'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(t('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(t('Enregistrer','Save')))]));
    if(ok!=true)return;if(f.text.trim().isEmpty||e.text.trim().isEmpty){toast(t('Les deux titres sont obligatoires.','Both titles are required.'));return;}
    try{final data={'curriculum_id':curriculum!['id'],'title_fr':f.text.trim(),'title_en':e.text.trim(),'position':int.tryParse(n.text)??chapters.length+1,'is_active':old?['is_active']??true};if(old==null){await db.from('course_chapters').insert(data);}else{await db.from('course_chapters').update(data).eq('id',old['id']);}await chooseCurriculum(curriculum);toast(t('Chapitre enregistré.','Chapter saved.'));}
    catch(e){toast(e.toString());}
  }
  Future<void> deleteChapter(Map<String,dynamic> ch) async {if(!await confirm(t('Supprimer ce chapitre et son contenu ?','Delete this chapter and its content?')))return;try{await db.from('course_chapters').delete().eq('id',ch['id']);if(chapter?['id']==ch['id'])chapter=null;await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> toggleChapter(Map<String,dynamic> ch) async {try{await db.from('course_chapters').update({'is_active':!(ch['is_active'] as bool? ?? true)}).eq('id',ch['id']);await chooseCurriculum(curriculum);}catch(e){toast(e.toString());}}
  Future<void> addContent() async {
    if (chapter == null) return;
    final targetChapterId = chapter!['id'].toString();
    final titleFr = TextEditingController();
    final titleEn = TextEditingController();
    final bodyFr = TextEditingController();
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
              const DropdownMenuItem(value: 'pdf', child: Text('PDF depuis le téléphone')),
            ],
            onChanged: (next) { if (next != null) type.value = next; },
          )),
        TextField(controller: titleFr, decoration: const InputDecoration(labelText: 'Titre français')),
        TextField(controller: titleEn, decoration: const InputDecoration(labelText: 'English title')),
        ValueListenableBuilder<String>(valueListenable: type, builder: (_, v, __) => Column(children: [
          if (v == 'course') ...[
            TextField(controller: bodyFr, maxLines: 5, decoration: const InputDecoration(labelText: 'Cours français')),
            TextField(controller: bodyEn, maxLines: 5, decoration: const InputDecoration(labelText: 'English lesson')),
          ],
          if (v == 'video') TextField(controller: url, decoration: const InputDecoration(labelText: 'Lien vidéo direct MP4 ou YouTube/Vimeo')),
          if (v == 'pdf') Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(t('Le PDF sera choisi sur le téléphone après validation.','Choose the PDF from your phone after confirming.')),
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
    if (titleFr.text.trim().isEmpty || titleEn.text.trim().isEmpty) {
      toast(t('Les titres sont obligatoires.','Titles are required.')); return;
    }
    String? storagePath;
    try {
      if (type.value == 'course' && (bodyFr.text.trim().isEmpty || bodyEn.text.trim().isEmpty)) {
        toast(t('Remplis les cours en français et en anglais.','Enter the lesson in French and English.')); return;
      }
      if (type.value == 'video' && url.text.trim().isEmpty) {
        toast(t('Le lien vidéo est obligatoire.','A video URL is required.')); return;
      }
      if (type.value == 'pdf') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf'], withData: true,
        );
        if (picked == null || picked.files.isEmpty) return;
        final file = picked.files.single;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          toast(t('Impossible de lire ce fichier PDF.','Unable to read this PDF.')); return;
        }
        final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        storagePath = chapter!['id'].toString() + '/' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName;
        await db.storage.from('chapter-content').uploadBinary(
          storagePath, bytes,
          fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
        );
      }
      final existing = await db.from('chapter_content_items').select('id').eq('chapter_id', chapter!['id']);
      await db.from('chapter_content_items').insert({
        'chapter_id': chapter!['id'],
        'content_type': type.value,
        'title_fr': titleFr.text.trim(),
        'title_en': titleEn.text.trim(),
        'body_text_fr': type.value == 'course' ? bodyFr.text.trim() : null,
        'body_text_en': type.value == 'course' ? bodyEn.text.trim() : null,
        'external_url': type.value == 'video' ? url.text.trim() : null,
        'storage_path': storagePath,
        'position': existing.length + 1,
        'is_published': published.value,
        'created_by': db.auth.currentUser?.id,
      });
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

  Future<void> editContent(Map<String, dynamic> item) async {
    final targetChapterId = chapter?['id']?.toString();
    final type = item['content_type'] as String? ?? 'course';
    final titleFr = TextEditingController(text: item['title_fr'] as String? ?? '');
    final titleEn = TextEditingController(text: item['title_en'] as String? ?? '');
    final bodyFr = TextEditingController(text: item['body_text_fr'] as String? ?? '');
    final bodyEn = TextEditingController(text: item['body_text_en'] as String? ?? '');
    final url = TextEditingController(text: item['external_url'] as String? ?? '');
    final published = ValueNotifier<bool>(item['is_published'] as bool? ?? false);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(t('Modifier le contenu', 'Edit content')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleFr, decoration: const InputDecoration(labelText: 'Titre français')),
        TextField(controller: titleEn, decoration: const InputDecoration(labelText: 'English title')),
        if (type == 'course') ...[
          TextField(controller: bodyFr, maxLines: 5, decoration: const InputDecoration(labelText: 'Cours français')),
          TextField(controller: bodyEn, maxLines: 5, decoration: const InputDecoration(labelText: 'English lesson')),
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
    if (titleFr.text.trim().isEmpty || titleEn.text.trim().isEmpty) {
      toast(t('Les titres sont obligatoires.', 'Titles are required.'));
      return;
    }
    if (type == 'course' && (bodyFr.text.trim().isEmpty || bodyEn.text.trim().isEmpty)) {
      toast(t('Remplis le cours dans les deux langues.', 'Enter the lesson in both languages.'));
      return;
    }
    if (type == 'video' && url.text.trim().isEmpty) {
      toast(t('Le lien vidéo est obligatoire.', 'A video URL is required.'));
      return;
    }
    String? replacementPath;
    final oldPath = item['storage_path'] as String?;
    try {
      if (type == 'pdf') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf'], withData: true,
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
          await db.storage.from('chapter-content').uploadBinary(
            replacementPath, bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: false),
          );
        }
      }
      final data = <String, dynamic>{
        'title_fr': titleFr.text.trim(),
        'title_en': titleEn.text.trim(),
        'is_published': published.value,
      };
      if (type == 'course') {
        data['body_text_fr'] = bodyFr.text.trim();
        data['body_text_en'] = bodyEn.text.trim();
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
            trailing:PopupMenuButton<String>(
              onSelected:(v){if(v=='edit')editContent(item);if(v=='toggle')toggleContent(item);if(v=='delete')deleteContent(item);},
              itemBuilder:(_)=>[
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
