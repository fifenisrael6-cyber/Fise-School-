-- Copy only the already verified MINESEC Terminale A Informatics chapter headings
-- to the matching A2/A3/A4/A5/AC curricula. No lesson content is copied.
insert into public.course_chapters
  (curriculum_id, title_fr, title_en, position, is_active)
select target.id, source_chapter.title_fr, source_chapter.title_en,
       source_chapter.position, true
from public.curricula source_curriculum
join public.subjects source_subject on source_subject.id = source_curriculum.subject_id
join public.exam_levels level on level.id = source_curriculum.exam_level_id
join public.series source_series on source_series.id = source_curriculum.series_id
join public.course_chapters source_chapter on source_chapter.curriculum_id = source_curriculum.id
join public.curricula target
  on target.subject_id = source_curriculum.subject_id
 and target.exam_level_id = source_curriculum.exam_level_id
 and target.title_fr = source_curriculum.title_fr
 and target.specialty_id is null
join public.series target_series on target_series.id = target.series_id
where source_subject.code = 'informatique'
  and source_curriculum.subsystem = 'francophone'
  and source_curriculum.sector = 'general'
  and level.code = 'fr_general_terminale'
  and source_series.code = 'a1'
  and target_series.code in ('a2','a3','a4','a5','ac')
  and source_curriculum.title_fr in (
    'Module 1 : Systèmes informatiques et humanités numériques',
    'Module 2 : Systèmes d’information et bases de données',
    'Module 3 : Production des contenus numériques'
  )
  and source_curriculum.is_active
  and target.is_active
on conflict (curriculum_id, position) do update
set title_fr = excluded.title_fr,
    title_en = excluded.title_en,
    is_active = true,
    updated_at = now();
