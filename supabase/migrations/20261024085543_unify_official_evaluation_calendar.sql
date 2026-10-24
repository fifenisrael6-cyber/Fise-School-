-- Unify the administration's official exam calendar with the automated evaluation pipeline.
-- Existing assignments, QCMs, lessons, and legacy exam records remain untouched.
alter table public.evaluations
  add column if not exists exam_id uuid references public.exams(id) on delete set null,
  add column if not exists correction_pdf_path text,
  add column if not exists correction_pdf_name text;

create index if not exists evaluations_exam_id_idx
  on public.evaluations(exam_id);

create or replace function public.scheduled_evaluation_publication_guard()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
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

drop trigger if exists scheduled_evaluation_publication_guard_trg on public.evaluations;
create trigger scheduled_evaluation_publication_guard_trg
before insert or update on public.evaluations
for each row execute function public.scheduled_evaluation_publication_guard();
