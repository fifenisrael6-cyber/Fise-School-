alter table public.subjects add column if not exists teaching_stream text not null default 'general';
alter table public.curricula add column if not exists teaching_stream text not null default 'general';
alter table public.subjects drop constraint if exists subjects_teaching_stream_check;
alter table public.subjects add constraint subjects_teaching_stream_check check (teaching_stream in ('literary','scientific','general','technical'));
alter table public.curricula drop constraint if exists curricula_teaching_stream_check;
alter table public.curricula add constraint curricula_teaching_stream_check check (teaching_stream in ('literary','scientific','general','technical'));
create or replace function public.enforce_curriculum_stream_matches_subject()
returns trigger language plpgsql set search_path=public as $function$
declare v_stream text;
begin
 select teaching_stream into v_stream from public.subjects where id=new.subject_id;
 if not found then raise exception 'Subject not found'; end if;
 if new.teaching_stream is distinct from v_stream then raise exception 'Curriculum stream must match its subject stream'; end if;
 return new;
end;$function$;
drop trigger if exists enforce_curriculum_stream_matches_subject on public.curricula;
create trigger enforce_curriculum_stream_matches_subject before insert or update of subject_id,teaching_stream on public.curricula for each row execute function public.enforce_curriculum_stream_matches_subject();
