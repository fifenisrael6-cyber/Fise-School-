-- Fise School: verified MINESEC technical Terminale ICT module titles.
-- Official source: Programme d'informatique, classes de Terminale ESTP - Industriel (2020):
-- https://files.minesec.gov.cm/jj/programme_T_ESTP_06-08-2020.pdf
-- Additive and idempotent: only verified module and component headings are seeded.

do $$
declare
  v_subject_id uuid;
  v_level_id uuid;
  v_curriculum_id uuid;
  v_module record;
  v_chapter record;
begin
  select id into v_subject_id
  from public.subjects
  where code = 'fr_tech_informatique'
    and subsystem = 'francophone'
    and sector = 'technical'
    and is_active
  limit 1;

  select id into v_level_id
  from public.exam_levels
  where code = 'fr_technical_terminale'
    and subsystem = 'francophone'
    and sector = 'technical'
  limit 1;

  if v_subject_id is null or v_level_id is null then
    raise notice 'Verified MINESEC technical Terminale ICT seed skipped: subject or exam level not found';
    return;
  end if;

  for v_module in
    select * from (values
      (1, 'Module 1 : Protection d’un environnement de travail et création de contenus numériques', 'Module 1: Protecting a work environment and creating digital content'),
      (2, 'Module 2 : Réseaux informatiques et systèmes d’information', 'Module 2: Computer networks and information systems'),
      (3, 'Module 3 : Dessin de spécialité et suivi des projets', 'Module 3: Speciality drawing and project monitoring')
    ) as m(module_no, title_fr, title_en)
  loop
    v_curriculum_id := null;

    select id into v_curriculum_id
    from public.curricula
    where subject_id = v_subject_id
      and exam_level_id = v_level_id
      and title_fr = v_module.title_fr
    limit 1;

    if v_curriculum_id is null then
      insert into public.curricula
        (subject_id, subsystem, sector, exam_level_id, title_fr, title_en,
         description_fr, description_en, is_active)
      values
        (v_subject_id, 'francophone', 'technical', v_level_id,
         v_module.title_fr, v_module.title_en,
         'Intitulé vérifié dans le programme officiel MINESEC d’informatique de Terminale ESTP - Industriel (2020).',
         'Title verified in the official MINESEC Terminale ESTP - Industrial ICT syllabus (2020).',
         true)
      returning id into v_curriculum_id;
    end if;

    for v_chapter in
      select * from (values
        (1, 'Description de l’architecture d’un système informatique', 'Description of a computer system architecture', 1),
        (1, 'Protection d’un environnement de travail', 'Protecting a work environment', 2),
        (1, 'Production d’une feuille de calculs', 'Creating a spreadsheet', 3),
        (2, 'Réseaux informatiques', 'Computer networks', 1),
        (2, 'Systèmes d’information', 'Information systems', 2),
        (3, 'Dessin de spécialité', 'Speciality drawing', 1),
        (3, 'Suivi des projets', 'Project monitoring', 2)
      ) as ch(module_no, title_fr, title_en, position)
      where ch.module_no = v_module.module_no
    loop
      insert into public.course_chapters
        (curriculum_id, title_fr, title_en, position, is_active)
      select v_curriculum_id, v_chapter.title_fr, v_chapter.title_en, v_chapter.position, true
      where not exists (
        select 1 from public.course_chapters
        where curriculum_id = v_curriculum_id
          and position = v_chapter.position
      );
    end loop;
  end loop;
end $$;
