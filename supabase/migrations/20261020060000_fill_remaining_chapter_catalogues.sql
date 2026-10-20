-- Fill the 12 remaining active, assigned catalogues with meaningful chapter
-- headings. The official MINESEC syllabus index separates subsystems and sectors,
-- but these exact 12 class-level headings could not all be independently verified
-- from accessible public documents. Keep every inserted row pending confirmation.
-- Idempotent: only currently empty catalog containers are targeted.
-- No lessons, course bodies, quizzes, or media are created.

WITH target_catalogues AS (
  SELECT cu.id AS curriculum_id, s.name_fr, s.name_en,
         cu.subsystem, cu.sector, lower(trim(el.level_name_fr)) AS level_key,
         lower(trim(coalesce(sr.name_fr,''))) AS series_key
  FROM public.curricula cu
  JOIN public.subjects s ON s.id=cu.subject_id
  LEFT JOIN public.exam_levels el ON el.id=cu.exam_level_id
  LEFT JOIN public.series sr ON sr.id=cu.series_id
  WHERE cu.is_active AND cu.is_catalog_container
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters ch
      WHERE ch.curriculum_id=cu.id AND ch.is_active
    )
    AND EXISTS (
      SELECT 1 FROM public.class_subjects cs
      JOIN public.school_classes cl ON cl.id=cs.class_id
      WHERE cs.subject_id=cu.subject_id AND cs.is_active AND cl.is_active
        AND cl.subsystem=cu.subsystem AND cl.sector=cu.sector
        AND cl.exam_level_id IS NOT DISTINCT FROM cu.exam_level_id
        AND cl.series_id IS NOT DISTINCT FROM cu.series_id
        AND cl.specialty_id IS NOT DISTINCT FROM cu.specialty_id
    )
),
esf(position,title_fr,title_en) AS (
 VALUES
 (1,'Hygiène individuelle et collective','Personal and community hygiene'),
 (2,'Alimentation et nutrition équilibrée','Food and balanced nutrition'),
 (3,'Habitat, entretien et sécurité domestique','Housing, home care and domestic safety'),
 (4,'Vêtements, textiles et entretien du linge','Clothing, textiles and laundry care'),
 (5,'Organisation du budget familial','Managing the family budget'),
 (6,'Santé familiale et prévention des risques','Family health and risk prevention'),
 (7,'Consommation responsable et protection du consommateur','Responsible consumption and consumer protection'),
 (8,'Environnement familial et développement durable','Family environment and sustainable living')
),
citizenship(position,title_fr,title_en) AS (
 VALUES
 (1,'Citizenship, identity and national values','Citizenship, identity and national values'),
 (2,'The Constitution, the rule of law and human rights','The Constitution, the rule of law and human rights'),
 (3,'Democracy, elections and political participation','Democracy, elections and political participation'),
 (4,'Government institutions and separation of powers','Government institutions and separation of powers'),
 (5,'Duties, responsibilities and civic participation','Duties, responsibilities and civic participation'),
 (6,'National unity, cultural diversity and social cohesion','National unity, cultural diversity and social cohesion'),
 (7,'Peaceful conflict resolution and community service','Peaceful conflict resolution and community service'),
 (8,'International cooperation and global citizenship','International cooperation and global citizenship')
),
commerce(position,title_fr,title_en) AS (
 VALUES
 (1,'The nature, scope and importance of commerce','The nature, scope and importance of commerce'),
 (2,'Production, trade and the distribution chain','Production, trade and the distribution chain'),
 (3,'Business ownership and forms of enterprise','Business ownership and forms of enterprise'),
 (4,'Home trade and foreign trade','Home trade and foreign trade'),
 (5,'Transport, warehousing and communication in trade','Transport, warehousing and communication in trade'),
 (6,'Banking, payments and financial services','Banking, payments and financial services'),
 (7,'Insurance and risk management in business','Insurance and risk management in business'),
 (8,'Business documents, records and commercial correspondence','Business documents, records and commercial correspondence'),
 (9,'Marketing, advertising and consumer protection','Marketing, advertising and consumer protection'),
 (10,'Entrepreneurship, e-commerce and ethical trade','Entrepreneurship, e-commerce and ethical trade')
),
pe(position,title_fr,title_en) AS (
 VALUES
 (1,'Physical fitness, health and personal wellbeing','Physical fitness, health and personal wellbeing'),
 (2,'Warm-up, exercise principles and safe participation','Warm-up, exercise principles and safe participation'),
 (3,'Athletics: running, jumping and throwing','Athletics: running, jumping and throwing'),
 (4,'Team games: rules, skills and tactics','Team games: rules, skills and tactics'),
 (5,'Individual and racket sports','Individual and racket sports'),
 (6,'Gymnastics, movement and coordination','Gymnastics, movement and coordination'),
 (7,'Nutrition, hydration, recovery and injury prevention','Nutrition, hydration, recovery and injury prevention'),
 (8,'Fair play, leadership and organization of sporting activities','Fair play, leadership and organization of sporting activities')
),
selected AS (
 SELECT t.curriculum_id,h.position,h.title_fr,h.title_en,
        'Économie sociale et familiale'::text subject_label,
        'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'::text source_url,
        'MINESEC — Programmes officiels; headings pending class-level confirmation'::text source_title
 FROM target_catalogues t CROSS JOIN esf h
 WHERE t.subsystem='francophone' AND t.sector='general'
   AND lower(trim(t.name_fr))='économie sociale et familiale'
 UNION ALL
 SELECT t.curriculum_id,h.position,h.title_fr,h.title_en,
        'Citizenship Education',
        'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en',
        'MINESEC — Anglophone general syllabus; headings pending class-level confirmation'
 FROM target_catalogues t CROSS JOIN citizenship h
 WHERE t.subsystem='anglophone' AND t.sector='general'
   AND lower(trim(t.name_en))='citizenship education'
 UNION ALL
 SELECT t.curriculum_id,h.position,h.title_fr,h.title_en,
        'Commerce',
        'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en',
        'MINESEC — Anglophone general syllabus; headings pending class-level confirmation'
 FROM target_catalogues t CROSS JOIN commerce h
 WHERE t.subsystem='anglophone' AND t.sector='general'
   AND lower(trim(t.name_en))='commerce'
 UNION ALL
 SELECT t.curriculum_id,h.position,h.title_fr,h.title_en,
        'Physical Education',
        'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en',
        'MINESEC — Anglophone general syllabus; headings pending class-level confirmation'
 FROM target_catalogues t CROSS JOIN pe h
 WHERE t.subsystem='anglophone' AND t.sector='general'
   AND lower(trim(t.name_en))='physical education'
)
INSERT INTO public.course_chapters
 (curriculum_id,title_fr,title_en,description_fr,description_en,position,
  is_active,verification_status,source_url,source_title)
SELECT s.curriculum_id,s.title_fr,s.title_en,
 'Titre de chapitre de restauration fonctionnelle. Le programme exact par classe doit être confirmé avec le document MINESEC correspondant avant validation officielle.',
 'Restored functional chapter heading. Confirm the exact class-level syllabus against the corresponding MINESEC document before official approval.',
 s.position,true,'pending_official_confirmation',s.source_url,s.source_title
FROM selected s
WHERE NOT EXISTS (
 SELECT 1 FROM public.course_chapters old
 WHERE old.curriculum_id=s.curriculum_id AND old.is_active
   AND lower(trim(old.title_fr))=lower(trim(s.title_fr))
);
