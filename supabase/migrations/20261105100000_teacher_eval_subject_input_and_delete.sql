-- Let teachers enter the subject name when publishing an evaluation.
-- The RPC resolves an existing subject in the same school subsystem/sector or
-- creates a dedicated subject record without changing class curriculum mappings.
create or replace function public.teacher_resolve_evaluation_subject(
  p_class_ids uuid[],
  p_subject_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_first_class public.school_classes%rowtype;
  v_class public.school_classes%rowtype;
  v_class_id uuid;
  v_name text;
  v_stream text;
  v_subject_id uuid;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid and role = 'teacher';
  if not found then
    raise exception 'Accès réservé aux enseignants.';
  end if;

  v_name := regexp_replace(btrim(coalesce(p_subject_name, '')), '\s+', ' ', 'g');
  if length(v_name) < 2 or length(v_name) > 80 then
    raise exception 'Le nom de la matière doit contenir entre 2 et 80 caractères.';
  end if;

  if p_class_ids is null
     or cardinality(p_class_ids) < 1
     or cardinality(p_class_ids) > 20
     or (select count(distinct u.class_id) from unnest(p_class_ids) as u(class_id)) <> cardinality(p_class_ids) then
    raise exception 'Sélection de salles invalide.';
  end if;

  foreach v_class_id in array p_class_ids loop
    if not public.teacher_can_manage_class(v_class_id, v_uid) then
      raise exception 'Vous ne pouvez pas publier dans cette salle.';
    end if;

    select * into v_class
    from public.school_classes
    where id = v_class_id and is_active;
    if not found then
      raise exception 'Salle inactive ou introuvable.';
    end if;

    if v_first_class.id is null then
      v_first_class := v_class;
    elsif v_class.subsystem is distinct from v_first_class.subsystem
       or v_class.sector is distinct from v_first_class.sector then
      raise exception 'Les salles doivent appartenir au même sous-système et secteur.';
    end if;
  end loop;

  v_stream := case
    when v_profile.teaching_stream in ('literary', 'scientific')
      then v_profile.teaching_stream
    else 'general'
  end;

  select s.id into v_subject_id
  from public.subjects s
  where s.is_active
    and s.subsystem = v_first_class.subsystem
    and s.sector = v_first_class.sector
    and (lower(btrim(s.name_fr)) = lower(v_name)
      or lower(btrim(s.name_en)) = lower(v_name))
    and (s.teaching_stream = 'general' or s.teaching_stream = v_stream)
  order by case when s.teaching_stream = v_stream then 0 else 1 end
  limit 1;

  if v_subject_id is null then
    insert into public.subjects (
      name_fr, name_en, code, subsystem, sector, teaching_stream, is_active
    )
    values (
      v_name, v_name,
      'teacher_eval_' || replace(gen_random_uuid()::text, '-', ''),
      v_first_class.subsystem,
      v_first_class.sector,
      v_stream,
      true
    )
    returning id into v_subject_id;
  end if;

  return v_subject_id;
end;
$function$;

revoke all on function public.teacher_resolve_evaluation_subject(uuid[], text) from public, anon;
grant execute on function public.teacher_resolve_evaluation_subject(uuid[], text) to authenticated;

-- A teacher may remove a published evaluation only while no student has
-- started or submitted a copy. This preserves in-progress work and grades.
drop policy if exists "evaluations owner delete draft" on public.evaluations;
create policy "evaluations owner delete without submissions"
on public.evaluations
for delete
to authenticated
using (
  (public.eval_is_admin() or teacher_id = auth.uid())
  and not exists (
    select 1
    from public.evaluation_submissions s
    where s.evaluation_id = evaluations.id
  )
);

create or replace function public.delete_teacher_evaluation(p_evaluation uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_teacher_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Session requise.';
  end if;

  select teacher_id into v_teacher_id
  from public.evaluations
  where id = p_evaluation;

  if not found or (v_teacher_id <> auth.uid() and not public.eval_is_admin()) then
    raise exception 'EVALUATION_NOT_FOUND_OR_NOT_OWNED';
  end if;

  if exists (
    select 1
    from public.evaluation_submissions
    where evaluation_id = p_evaluation
  ) then
    raise exception 'EVALUATION_HAS_SUBMISSIONS';
  end if;

  delete from public.evaluations
  where id = p_evaluation
    and (teacher_id = auth.uid() or public.eval_is_admin());

  if not found then
    raise exception 'EVALUATION_NOT_FOUND_OR_NOT_OWNED';
  end if;

  return true;
end;
$function$;

revoke all on function public.delete_teacher_evaluation(uuid) from public, anon;
grant execute on function public.delete_teacher_evaluation(uuid) to authenticated;
