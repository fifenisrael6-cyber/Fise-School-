-- The source syllabus is explicitly for Terminale ESTP - Industrial.
-- The current specialty catalogue cannot yet identify a matching industrial room,
-- so do not expose these titles to every Terminale technical specialty.
-- They can be re-seeded with a specialty_id when the official matching is represented.
update public.curricula c
set is_active = false,
    updated_at = now()
from public.subjects s,
     public.exam_levels el
where c.subject_id = s.id
  and c.exam_level_id = el.id
  and s.code = 'fr_tech_informatique'
  and c.subsystem = 'francophone'
  and c.sector = 'technical'
  and el.code = 'fr_technical_terminale'
  and c.specialty_id is null
  and c.title_fr in (
    'Module 1 : Protection d’un environnement de travail et création de contenus numériques',
    'Module 2 : Réseaux informatiques et systèmes d’information',
    'Module 3 : Dessin de spécialité et suivi des projets'
  );
