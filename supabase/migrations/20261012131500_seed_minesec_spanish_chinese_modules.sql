-- Official MINESEC Spanish and Chinese module titles for 4e and 3e.
-- Titles only: no lesson text, documents, exercises, or quizzes are inserted.

do $$
declare
  item record;
  v_level_id uuid;
  v_subject_id uuid;
begin
  for item in
    select * from (values
      ('fr_general_quatrieme','espagnol',1,'Vie familiale et intégration sociale','Family Life and Social Integration','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_quatrieme','espagnol',2,'Environnement, santé et bien-être','Environment, Health and Well-being','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_quatrieme','espagnol',3,'Citoyenneté et ouverture au monde','Citizenship and Openness to the World','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_quatrieme','espagnol',4,'Activités économiques et monde du travail','Economic Activities and the World of Work','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_quatrieme','espagnol',5,'Communication et médias (TIC)','Communication and Media (ICT)','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_troisieme','espagnol',1,'Vie familiale et intégration sociale','Family Life and Social Integration','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_troisieme','espagnol',2,'Environnement, santé et bien-être','Environment, Health and Well-being','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_troisieme','espagnol',3,'Citoyenneté et ouverture au monde','Citizenship and Openness to the World','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_troisieme','espagnol',4,'Activités économiques et monde du travail','Economic Activities and the World of Work','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_troisieme','espagnol',5,'Communication et médias (TIC)','Communication and Media (ICT)','https://files.minesec.gov.cm/2o/programme_Espagnol_4eme3eme.pdf'),
      ('fr_general_quatrieme','chinois',1,'Vie familiale et intégration sociale','Family Life and Social Integration','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_quatrieme','chinois',2,'Environnement, bien-être et santé','Environment, Well-being and Health','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_quatrieme','chinois',3,'Citoyenneté et ouverture au monde','Citizenship and Openness to the World','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_quatrieme','chinois',4,'Activités économiques et monde du travail','Economic Activities and the World of Work','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_quatrieme','chinois',5,'Vie économique, médias et communication','Economic Life, Media and Communication','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_troisieme','chinois',1,'Vie familiale et intégration sociale','Family Life and Social Integration','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_troisieme','chinois',2,'Environnement, bien-être et santé','Environment, Well-being and Health','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_troisieme','chinois',3,'Citoyenneté et ouverture au monde','Citizenship and Openness to the World','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_troisieme','chinois',4,'Activités économiques et monde du travail','Economic Activities and the World of Work','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf'),
      ('fr_general_troisieme','chinois',5,'Vie économique, médias et communication','Economic Life, Media and Communication','https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf')
    ) as x(level_code, subject_code, module_no, module_fr, module_en, source_url)
  loop
    select id into v_level_id
    from public.exam_levels
    where code = item.level_code and active
    limit 1;

    select id into v_subject_id
    from public.subjects
    where code = item.subject_code
      and subsystem = 'francophone'
      and sector = 'general'
      and is_active
    limit 1;

    if v_level_id is null or v_subject_id is null then
      raise notice 'Skipping % module %: level or subject not found', item.subject_code, item.module_no;
      continue;
    end if;

    insert into public.curricula
      (subject_id, subsystem, sector, exam_level_id, title_fr, title_en,
       description_fr, description_en, is_active)
    values
      (v_subject_id, 'francophone', 'general', v_level_id,
       'Module ' || item.module_no || ' : ' || item.module_fr,
       'Module ' || item.module_no || ': ' || item.module_en,
       'Intitulé relevé du programme officiel MINESEC. Source : ' || item.source_url,
       'Title from the official MINESEC syllabus. Source: ' || item.source_url,
       true)
    on conflict do nothing;
  end loop;
end $$;
