-- Enforce official exam time windows and the 24-hour correction release server-side.
-- Applies only to rows representing official exams (exam_id IS NOT NULL).
create or replace function public.scheduled_evaluation_publication_guard()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  v_start_local timestamp;
  v_due_local timestamp;
  v_start_minutes integer;
  v_due_minutes integer;
  v_weekday integer;
begin
  if new.exam_id is not null then
    v_start_local := new.starts_at at time zone 'Africa/Douala';
    v_due_local := new.due_at at time zone 'Africa/Douala';
    v_start_minutes := extract(hour from v_start_local)::integer * 60
      + extract(minute from v_start_local)::integer;
    v_due_minutes := extract(hour from v_due_local)::integer * 60
      + extract(minute from v_due_local)::integer;
    v_weekday := extract(isodow from v_start_local)::integer;

    if v_start_local::date <> v_due_local::date then
      raise exception 'Une épreuve officielle doit se terminer le même jour.';
    end if;
    if v_weekday between 1 and 5 and v_start_minutes < (19 * 60 + 20) then
      raise exception 'En semaine, une épreuve officielle ne peut commencer avant 19 h 20.';
    end if;
    if v_weekday in (6, 7) and v_start_minutes < (18 * 60) then
      raise exception 'Le week-end, une épreuve officielle ne peut commencer avant 18 h.';
    end if;
    if v_due_minutes > (22 * 60) then
      raise exception 'Une épreuve officielle doit se terminer au plus tard à 22 h.';
    end if;
    if new.results_visible_at is distinct from new.due_at + interval '24 hours' then
      raise exception 'La correction officielle doit être programmée exactement 24 heures après la fin de l’épreuve.';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status in ('published', 'closed')
     and (
       new.correction_pdf_path is distinct from old.correction_pdf_path
       or new.correction_pdf_name is distinct from old.correction_pdf_name
     ) then
    raise exception 'Le corrigé officiel est figé après publication.';
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'draft'
     and new.status = 'published'
     and new.exam_id is not null
     and nullif(btrim(coalesce(new.correction_pdf_path, '')), '') is null then
    raise exception 'Le corrigé PDF officiel est obligatoire pour publier cette épreuve.';
  end if;

  return new;
end;
$function$;
