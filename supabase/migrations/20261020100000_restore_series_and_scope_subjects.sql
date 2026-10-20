-- Restore second-cycle francophone series links, create missing language-option rooms,
-- and ensure students see the curriculum for their exact series rather than every
-- optional subject listed for the Terminale level.
begin;

-- Re-activate only the known francophone general series for second-cycle levels.
insert into public.exam_level_series (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
join public.series s on lower(s.code) in ('a1','a2','a3','a4','a5','ac','c','d','ti','bil')
where el.subsystem = 'francophone'
  and el.sector = 'general'
  and el.level_order >= 5
  and el.active
  and s.active
on conflict (exam_level_id, series_id) do update
set active = true, verification_status = 'verified';

-- Subject reconciliation is performed by the following additive migration, using the
-- canonical curriculum chapter containers for every subsystem and sector. Keeping
-- it in one place avoids deactivating valid subjects from sparse legacy series lists.

-- AuthPage sends level/series/specialty/language metadata. Resolve the exact
-- classroom server-side so registration does not fail because class_id was omitted.
create or replace function public.sync_signup_language_option()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(metadata ->> 'role', 'student');
  requested_class_id uuid;
  requested_option text := nullif(trim(metadata ->> 'language_option'), '');
  selected_class public.school_classes%rowtype;
begin
  if requested_role <> 'student' then
    return new;
  end if;

  if coalesce(metadata ->> 'class_id', '') ~ '^[0-9a-fA-F-]{36}$' then
    requested_class_id := (metadata ->> 'class_id')::uuid;
  end if;

  if requested_class_id is not null then
    select c.* into selected_class
    from public.school_classes c
    where c.id = requested_class_id
      and c.is_active
      and c.language_option is not distinct from requested_option
      and c.exam_level_id::text is not distinct from nullif(metadata ->> 'exam_level_id', '')
      and c.series_id::text is not distinct from nullif(metadata ->> 'series_id', '')
      and c.specialty_id::text is not distinct from nullif(metadata ->> 'specialty_id', '')
      and c.subsystem::text is not distinct from nullif(metadata ->> 'subsystem', '')
      and c.sector::text is not distinct from nullif(metadata ->> 'sector', '');
  else
    select c.* into selected_class
    from public.school_classes c
    where c.is_active
      and c.exam_level_id::text is not distinct from nullif(metadata ->> 'exam_level_id', '')
      and c.series_id::text is not distinct from nullif(metadata ->> 'series_id', '')
      and c.specialty_id::text is not distinct from nullif(metadata ->> 'specialty_id', '')
      and c.subsystem::text is not distinct from nullif(metadata ->> 'subsystem', '')
      and c.sector::text is not distinct from nullif(metadata ->> 'sector', '')
      and c.language_option is not distinct from requested_option
    order by c.display_name
    limit 1;
  end if;

  if selected_class.id is null then
    raise exception 'Aucune salle ne correspond au niveau, à la série/filière et à la langue sélectionnés. Vérifier le catalogue des classes.';
  end if;

  update public.profiles
  set subsystem = selected_class.subsystem,
      sector = selected_class.sector,
      exam_level_id = selected_class.exam_level_id,
      series_id = selected_class.series_id,
      specialty_id = selected_class.specialty_id,
      class_name = selected_class.display_name,
      exam_level_label = nullif(metadata ->> 'exam_level', ''),
      exam_label = nullif(metadata ->> 'exam', ''),
      track_label = nullif(metadata ->> 'track', ''),
      language_option = requested_option,
      updated_at = now()
  where id = new.id;

  insert into public.class_students (class_id, student_id, is_active)
  select selected_class.id, new.id, true
  where not exists (
    select 1 from public.class_students cs
    where cs.class_id = selected_class.id
      and cs.student_id = new.id
      and cs.is_active
  );

  return new;
end;
$$;

drop trigger if exists zz_sync_signup_language_option on auth.users;
create trigger zz_sync_signup_language_option
after insert on auth.users
for each row execute function public.sync_signup_language_option();

commit;
