import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminChapterAssessmentsPage extends StatefulWidget {
  const AdminChapterAssessmentsPage({super.key, required this.chapterId, required this.chapterTitle, required this.locale});
  final String chapterId;
  final String chapterTitle;
  final Locale locale;
  @override
  State<AdminChapterAssessmentsPage> createState() => _AdminChapterAssessmentsPageState();
}

class _AdminChapterAssessmentsPageState extends State<AdminChapterAssessmentsPage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> exercises = [];
  List<Map<String, dynamic>> quizzes = [];
  bool busy = true;
  String? error;
  bool get en => widget.locale.languageCode == 'en';
  String tr(String fr, String english) => en ? english : fr;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { busy = true; error = null; });
    try {
      final rows = await Future.wait<dynamic>([
        db.from('chapter_exercises').select().eq('chapter_id', widget.chapterId).order('position'),
        db.from('chapter_quizzes').select().eq('chapter_id', widget.chapterId).order('position'),
      ]);
      exercises = (rows[0] as List).map((x) => Map<String, dynamic>.from(x)).toList();
      quizzes = (rows[1] as List).map((x) => Map<String, dynamic>.from(x)).toList();
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => busy = false);
  }

  void note(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  Future<void> addExercise([Map<String, dynamic>? existing]) async {
    final sf = TextEditingController(text: existing?['statement_fr'] as String? ?? '');
    final se = TextEditingController(text: existing?['statement_en'] as String? ?? '');
    final cf = TextEditingController(), ce = TextEditingController();
    final xf = TextEditingController(), xe = TextEditingController();
    final level = ValueNotifier<String>(existing?['difficulty'] as String? ?? 'medium');
    final published = ValueNotifier<bool>(existing?['is_published'] as bool? ?? false);
    if (existing != null) {
      try {
        final correction = await db.from('chapter_exercise_corrections')
            .select().eq('exercise_id', existing['id']).maybeSingle();
        if (correction != null) {
          final correctionMap = Map<String, dynamic>.from(correction as Map);
          cf.text = correctionMap['correction_fr'] as String? ?? '';
          ce.text = correctionMap['correction_en'] as String? ?? '';
          xf.text = correctionMap['explanation_fr'] as String? ?? '';
          xe.text = correctionMap['explanation_en'] as String? ?? '';
        }
      } catch (e) { note(e.toString()); return; }
    }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(existing == null ? tr('Nouvel exercice', 'New exercise') : tr('Modifier l’exercice', 'Edit exercise')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: sf, maxLines: 3, decoration: const InputDecoration(labelText: 'Énoncé français')),
        TextField(controller: se, maxLines: 3, decoration: const InputDecoration(labelText: 'English statement')),
        ValueListenableBuilder<String>(valueListenable: level, builder: (_, v, __) => DropdownButtonFormField<String>(
          initialValue: v, decoration: InputDecoration(labelText: tr('Niveau','Difficulty')),
          items: [DropdownMenuItem(value:'easy',child:Text(tr('Facile','Easy'))),DropdownMenuItem(value:'medium',child:Text(tr('Moyen','Medium'))),DropdownMenuItem(value:'hard',child:Text(tr('Difficile','Hard')))],
          onChanged: (x) { if (x != null) level.value = x; },
        )),
        TextField(controller: cf, maxLines: 3, decoration: const InputDecoration(labelText: 'Corrigé français')),
        TextField(controller: ce, maxLines: 3, decoration: const InputDecoration(labelText: 'English correction')),
        TextField(controller: xf, maxLines: 2, decoration: const InputDecoration(labelText: 'Explication française')),
        TextField(controller: xe, maxLines: 2, decoration: const InputDecoration(labelText: 'English explanation')),
        ValueListenableBuilder<bool>(valueListenable: published, builder: (_, v, __) => SwitchListTile(value:v,title:Text(tr('Publier','Publish')),onChanged:(x)=>published.value=x)),
      ])),
      actions: [TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('Enregistrer','Save')))],
    ));
    if (ok != true) return;
    if ([sf,se,cf,ce].any((x) => x.text.trim().isEmpty)) { note(tr('Énoncés et corrigés obligatoires dans les deux langues.','Statements and corrections are required in both languages.')); return; }
    try {
      String exerciseId;
      if (existing == null) {
        final row = await db.from('chapter_exercises').insert({
          'chapter_id': widget.chapterId, 'statement_fr': sf.text.trim(), 'statement_en': se.text.trim(),
          'difficulty': level.value, 'position': exercises.length + 1, 'is_published': published.value,
          'created_by': db.auth.currentUser?.id,
        }).select('id').single();
        exerciseId = row['id'] as String;
      } else {
        exerciseId = existing['id'] as String;
        await db.from('chapter_exercises').update({
          'statement_fr': sf.text.trim(), 'statement_en': se.text.trim(),
          'difficulty': level.value, 'is_published': published.value,
        }).eq('id', exerciseId);
      }
      await db.from('chapter_exercise_corrections').upsert({
        'exercise_id': exerciseId, 'correction_fr': cf.text.trim(), 'correction_en': ce.text.trim(),
        'explanation_fr': xf.text.trim().isEmpty ? null : xf.text.trim(),
        'explanation_en': xe.text.trim().isEmpty ? null : xe.text.trim(),
      }, onConflict: 'exercise_id');
      await load(); note(tr('Exercice enregistré.','Exercise saved.'));
    } catch (e) { note(e.toString()); }
  }

  Future<void> addQuiz([Map<String, dynamic>? existing]) async {
    final tf = TextEditingController(text: existing?['title_fr'] as String? ?? '');
    final te = TextEditingController(text: existing?['title_en'] as String? ?? '');
    final qf = TextEditingController(), qe = TextEditingController();
    final of = List.generate(4, (_) => TextEditingController());
    final oe = List.generate(4, (_) => TextEditingController());
    final xf = TextEditingController(), xe = TextEditingController();
    final answer = ValueNotifier<int>(0);
    final published = ValueNotifier<bool>(existing?['is_published'] as bool? ?? false);
    String? existingQuestionId;
    if (existing != null) {
      try {
        final questions = await db.from('chapter_quiz_questions').select()
            .eq('quiz_id', existing['id']).order('position').limit(1);
        if (questions.isNotEmpty) {
          final question = Map<String, dynamic>.from(questions.first);
          existingQuestionId = question['id'] as String;
          qf.text = question['prompt_fr'] as String? ?? '';
          qe.text = question['prompt_en'] as String? ?? '';
          final frOptions = question['options_fr'] as List? ?? const [];
          final enOptions = question['options_en'] as List? ?? const [];
          for (var i = 0; i < 4; i++) {
            if (i < frOptions.length) of[i].text = frOptions[i].toString();
            if (i < enOptions.length) oe[i].text = enOptions[i].toString();
          }
          final key = await db.from('chapter_quiz_answer_keys').select()
              .eq('question_id', existingQuestionId).maybeSingle();
          if (key != null) {
            final keyMap = Map<String, dynamic>.from(key as Map);
            answer.value = (keyMap['correct_option_index'] as num?)?.toInt() ?? 0;
            xf.text = keyMap['explanation_fr'] as String? ?? '';
            xe.text = keyMap['explanation_en'] as String? ?? '';
          }
        }
      } catch (e) { note(e.toString()); return; }
    }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(existing == null ? tr('Créer un quiz avec une question','Create a quiz with one question') : tr('Modifier le quiz','Edit quiz')),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller:tf,decoration:const InputDecoration(labelText:'Titre français')),
        TextField(controller:te,decoration:const InputDecoration(labelText:'English title')),
        TextField(controller:qf,maxLines:2,decoration:const InputDecoration(labelText:'Question française')),
        TextField(controller:qe,maxLines:2,decoration:const InputDecoration(labelText:'English question')),
        for (var i=0; i<4; i++) ...[
          TextField(controller:of[i],decoration:InputDecoration(labelText:'Choix français numéro ' + (i+1).toString())),
          TextField(controller:oe[i],decoration:InputDecoration(labelText:'English option ' + (i+1).toString())),
        ],
        ValueListenableBuilder<int>(valueListenable:answer,builder:(_,v,__)=>DropdownButtonFormField<int>(
          initialValue:v,decoration:InputDecoration(labelText:tr('Bonne réponse','Correct answer')),
          items:List.generate(4,(i)=>DropdownMenuItem(value:i,child:Text((i+1).toString()))),
          onChanged:(x){if(x!=null)answer.value=x;},
        )),
        TextField(controller:xf,maxLines:2,decoration:const InputDecoration(labelText:'Explication française')),
        TextField(controller:xe,maxLines:2,decoration:const InputDecoration(labelText:'English explanation')),
        ValueListenableBuilder<bool>(valueListenable:published,builder:(_,v,__)=>SwitchListTile(value:v,title:Text(tr('Publier','Publish')),onChanged:(x)=>published.value=x)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('Enregistrer','Save')))],
    ));
    if (ok != true) return;
    if ([tf,te,qf,qe,...of,...oe].any((x)=>x.text.trim().isEmpty)) { note(tr('Tous les champs du quiz sont obligatoires.','All quiz fields are required.')); return; }
    try {
      String quizId;
      if (existing == null) {
        final quiz = await db.from('chapter_quizzes').insert({
          'chapter_id':widget.chapterId,'title_fr':tf.text.trim(),'title_en':te.text.trim(),
          'position':quizzes.length+1,'is_published':published.value,'created_by':db.auth.currentUser?.id,
        }).select('id').single();
        quizId = quiz['id'] as String;
      } else {
        quizId = existing['id'] as String;
        await db.from('chapter_quizzes').update({
          'title_fr':tf.text.trim(),'title_en':te.text.trim(),'is_published':published.value,
        }).eq('id', quizId);
      }
      String questionId;
      final questionData = {
        'quiz_id':quizId,'prompt_fr':qf.text.trim(),'prompt_en':qe.text.trim(),
        'options_fr':of.map((x)=>x.text.trim()).toList(),'options_en':oe.map((x)=>x.text.trim()).toList(),'position':1,
      };
      if (existingQuestionId == null) {
        final question = await db.from('chapter_quiz_questions').insert(questionData).select('id').single();
        questionId = question['id'] as String;
      } else {
        questionId = existingQuestionId;
        await db.from('chapter_quiz_questions').update(questionData).eq('id', questionId);
      }
      await db.from('chapter_quiz_answer_keys').upsert({
        'question_id':questionId,'correct_option_index':answer.value,
        'explanation_fr':xf.text.trim().isEmpty?null:xf.text.trim(),
        'explanation_en':xe.text.trim().isEmpty?null:xe.text.trim(),
      }, onConflict: 'question_id');
      await load(); note(tr('Quiz enregistré.','Quiz saved.'));
    } catch (e) { note(e.toString()); }
  }

  Future<void> addQuestion(Map<String, dynamic> quiz) async {
    final qf = TextEditingController(), qe = TextEditingController();
    final of = List.generate(4, (_) => TextEditingController());
    final oe = List.generate(4, (_) => TextEditingController());
    final xf = TextEditingController(), xe = TextEditingController();
    final answer = ValueNotifier<int>(0);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(tr('Ajouter une question au quiz', 'Add a quiz question')),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: qf, maxLines: 2, decoration: const InputDecoration(labelText: 'Question française')),
        TextField(controller: qe, maxLines: 2, decoration: const InputDecoration(labelText: 'English question')),
        for (var i = 0; i < 4; i++) ...[
          TextField(controller: of[i], decoration: InputDecoration(labelText: 'Choix français ${i + 1}')),
          TextField(controller: oe[i], decoration: InputDecoration(labelText: 'English option ${i + 1}')),
        ],
        ValueListenableBuilder<int>(valueListenable: answer, builder: (_, value, __) =>
          DropdownButtonFormField<int>(
            initialValue: value,
            decoration: InputDecoration(labelText: tr('Bonne réponse', 'Correct answer')),
            items: List.generate(4, (i) => DropdownMenuItem(value: i, child: Text('${i + 1}'))),
            onChanged: (next) { if (next != null) answer.value = next; },
          )),
        TextField(controller: xf, maxLines: 2, decoration: const InputDecoration(labelText: 'Explication française')),
        TextField(controller: xe, maxLines: 2, decoration: const InputDecoration(labelText: 'English explanation')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Annuler', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ajouter', 'Add'))),
      ],
    ));
    if (ok != true) return;
    if ([qf, qe, ...of, ...oe].any((x) => x.text.trim().isEmpty)) {
      note(tr('Remplis la question et les quatre choix dans les deux langues.',
          'Fill in the question and all four options in both languages.'));
      return;
    }
    try {
      final rows = await db.from('chapter_quiz_questions').select('position')
          .eq('quiz_id', quiz['id']).order('position', ascending: false).limit(1);
      final position = rows.isEmpty ? 1 : ((rows.first['position'] as num).toInt() + 1);
      final question = await db.from('chapter_quiz_questions').insert({
        'quiz_id': quiz['id'],
        'prompt_fr': qf.text.trim(),
        'prompt_en': qe.text.trim(),
        'options_fr': of.map((x) => x.text.trim()).toList(),
        'options_en': oe.map((x) => x.text.trim()).toList(),
        'position': position,
      }).select('id').single();
      await db.from('chapter_quiz_answer_keys').insert({
        'question_id': question['id'],
        'correct_option_index': answer.value,
        'explanation_fr': xf.text.trim().isEmpty ? null : xf.text.trim(),
        'explanation_en': xe.text.trim().isEmpty ? null : xe.text.trim(),
      });
      await load();
      note(tr('Question ajoutée au quiz.', 'Question added to quiz.'));
    } catch (e) { note(e.toString()); }
  }

  Future<void> toggle(String table, Map<String,dynamic> row) async {
    try { await db.from(table).update({'is_published':!(row['is_published'] as bool? ?? false)}).eq('id',row['id']); await load(); }
    catch(e) { note(e.toString()); }
  }

  Future<void> remove(String table, Map<String,dynamic> row) async {
    final yes = await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      content:Text(tr('Supprimer cet élément ?','Delete this item?')),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(tr('Annuler','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(tr('Supprimer','Delete')))],
    ));
    if (yes != true) return;
    try { await db.from(table).delete().eq('id',row['id']); await load(); } catch(e) { note(e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(tr('Exercices et quiz','Exercises and quizzes'))),
    body:busy?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!)):RefreshIndicator(
      onRefresh:load,
      child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(widget.chapterTitle,style:Theme.of(context).textTheme.titleLarge),
        Row(children:[Expanded(child:Text(tr('Exercices','Exercises'),style:Theme.of(context).textTheme.titleMedium)),FilledButton.icon(onPressed:addExercise,icon:const Icon(Icons.add),label:Text(tr('Ajouter','Add')))]),
        for(final item in exercises) Card(child:ListTile(
          title:Text((en?item['statement_en']:item['statement_fr']) as String? ?? ''),
          subtitle:Text((item['difficulty'] as String? ?? '')+' • '+(((item['is_published'] as bool?)??false)?tr('Publié','Published'):tr('Masqué','Hidden'))),
          trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')addExercise(item);if(v=='toggle')toggle('chapter_exercises',item);if(v=='delete')remove('chapter_exercises',item);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Modifier','Edit'))),PopupMenuItem(value:'toggle',child:Text(tr('Masquer / publier','Hide / publish'))),PopupMenuItem(value:'delete',child:Text(tr('Supprimer','Delete')))]),
        )),
        const Divider(height:32),
        Row(children:[Expanded(child:Text('Quiz',style:Theme.of(context).textTheme.titleMedium)),FilledButton.icon(onPressed:addQuiz,icon:const Icon(Icons.add),label:Text(tr('Créer','Create')))]),
        for(final item in quizzes) Card(child:ListTile(
          title:Text((en?item['title_en']:item['title_fr']) as String? ?? ''),
          subtitle:Text(((item['is_published'] as bool?)??false)?tr('Publié','Published'):tr('Masqué','Hidden')),
          trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')addQuiz(item);if(v=='add_question')addQuestion(item);if(v=='toggle')toggle('chapter_quizzes',item);if(v=='delete')remove('chapter_quizzes',item);},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Modifier','Edit'))),PopupMenuItem(value:'add_question',child:Text(tr('Ajouter une question','Add question'))),PopupMenuItem(value:'toggle',child:Text(tr('Masquer / publier','Hide / publish'))),PopupMenuItem(value:'delete',child:Text(tr('Supprimer','Delete')))]),
        )),
      ]),
    ),
  );
}
