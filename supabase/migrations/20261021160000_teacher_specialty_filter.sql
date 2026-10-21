alter table public.profiles
  add column if not exists teacher_specialty text;

alter table public.profiles
  drop constraint if exists profiles_teacher_specialty_check;

alter table public.profiles
  add constraint profiles_teacher_specialty_check
  check (teacher_specialty is null or teacher_specialty in ('literary', 'scientific'));

comment on column public.profiles.teacher_specialty is
  'Teacher curriculum track: literary or scientific. Set from the unique access-code page.';
