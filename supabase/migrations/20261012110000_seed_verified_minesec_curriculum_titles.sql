-- Fise School: verified MINESEC curriculum titles (additive seed).
-- Source: MINESEC, "Programme d'informatique, classes de Terminale séries C, D et E",
-- July 2020: https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_CDE_06_08_2020.pdf=&s=ji
-- This migration intentionally seeds only headings verified from that document.
-- It does not invent titles for other subjects/classes; those require their official syllabuses.

do $$
declare
  v_subject_id uuid;
  v_series record;
  v_module record;
  v_curriculum_id uuid;
  v_chapter text;
  v_pos integer;
begin
  select id into v_subject_id
  from public.subjects
  where code = 'informatique'
    and subsystem = 'francophone'
    and sector = 'general'
    and is_active
  limit 1;

  if v_subject_id is null then
    raise notice 'MINESEC verified seed skipped: active francophone general informatique subject not found';
    return;
  end if;

  for v_series in
    select id, code
    from public.series
    where lower(code) in ('c', 'd', 'e')
  loop
    for v_module in
      select *
      from (values
        (1, 'Module 1 : Systèmes informatiques', 'Module 1: Computer Systems'),
        (2, 'Module 2 : Systèmes d’information et bases de données', 'Module 2: Information Systems and Databases'),
        (3, 'Module 3 : Algorithmique et programmation', 'Module 3: Algorithms and Programming')
      ) as m(module_no, title_fr, title_en)
    loop
      select id into v_curriculum_id
      from public.curricula
      where subject_id = v_subject_id
        and series_id = v_series.id
        and title_fr = v_module.title_fr
      limit 1;

      if v_curriculum_id is null then
        insert into public.curricula
          (subject_id, subsystem, sector, series_id, title_fr, title_en, description_fr, description_en, is_active)
        values
          (v_subject_id, 'francophone', 'general', v_series.id,
           v_module.title_fr, v_module.title_en,
           'Titre de module relevé dans le programme officiel MINESEC de Terminale C, D et E (juillet 2020).',
           'Module title taken from the official MINESEC Terminale C, D and E syllabus (July 2020).',
           true)
        returning id into v_curriculum_id;
      end if;

      if v_module.module_no = 1 then
        for v_chapter, v_pos in
          select x.title_fr, x.position
          from (values
            ('Description de l’architecture d’un système informatique', 1),
            ('Protection d’un environnement de travail', 2),
            ('Production d’un classeur', 3),
            ('Configuration d’un réseau informatique', 4)
          ) as x(title_fr, position)
        loop
          insert into public.course_chapters (curriculum_id, title_fr, title_en, position, is_active)
          select v_curriculum_id, v_chapter,
            case v_chapter
              when 'Description de l’architecture d’un système informatique' then 'Description of a computer system architecture'
              when 'Protection d’un environnement de travail' then 'Protection of a work environment'
              when 'Production d’un classeur' then 'Creating a spreadsheet workbook'
              else 'Configuring a computer network'
            end,
            v_pos, true
          where not exists (
            select 1 from public.course_chapters
            where curriculum_id = v_curriculum_id and position = v_pos
          );
        end loop;
      elsif v_module.module_no = 2 then
        for v_chapter, v_pos in
          select x.title_fr, x.position
          from (values
            ('Conception des modèles de données d’un système d’information', 1),
            ('Implémentation d’une base de données', 2)
          ) as x(title_fr, position)
        loop
          insert into public.course_chapters (curriculum_id, title_fr, title_en, position, is_active)
          select v_curriculum_id, v_chapter,
            case v_chapter
              when 'Conception des modèles de données d’un système d’information' then 'Designing data models for an information system'
              else 'Implementing a database'
            end,
            v_pos, true
          where not exists (
            select 1 from public.course_chapters
            where curriculum_id = v_curriculum_id and position = v_pos
          );
        end loop;
      else
        for v_chapter, v_pos in
          select x.title_fr, x.position
          from (values
            ('Écriture et exécution des algorithmes intégrant une structure de données', 1),
            ('Programmation en langage C', 2)
          ) as x(title_fr, position)
        loop
          insert into public.course_chapters (curriculum_id, title_fr, title_en, position, is_active)
          select v_curriculum_id, v_chapter,
            case v_chapter
              when 'Écriture et exécution des algorithmes intégrant une structure de données' then 'Writing and executing algorithms using a data structure'
              else 'Programming in C'
            end,
            v_pos, true
          where not exists (
            select 1 from public.course_chapters
            where curriculum_id = v_curriculum_id and position = v_pos
          );
        end loop;
      end if;

      v_curriculum_id := null;
    end loop;
  end loop;
end $$;
