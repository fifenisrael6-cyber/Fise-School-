-- Publication des TD depuis l'onglet Cours de l'administration.
-- Les droits de ligne restent actifs : les élèves ne lisent que les TD publiés
-- pour leurs salles, et les enseignants ne gèrent que leurs propres TD.
grant select, insert, update, delete on public.directed_studies to authenticated;

drop policy if exists "admins manage directed studies" on public.directed_studies;
create policy "admins manage directed studies"
on public.directed_studies
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
