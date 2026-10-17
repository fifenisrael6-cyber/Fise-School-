-- Populate teacher vocation for existing teacher profiles created before
-- the metadata-sync trigger was installed.
update public.profiles p
set teacher_vocation = lower(trim(u.raw_user_meta_data ->> 'teacher_vocation'))
from auth.users u
where u.id = p.id
  and p.role = 'teacher'
  and lower(trim(coalesce(u.raw_user_meta_data ->> 'teacher_vocation', ''))) in ('scientific','literary')
  and p.teacher_vocation is distinct from lower(trim(u.raw_user_meta_data ->> 'teacher_vocation'));
