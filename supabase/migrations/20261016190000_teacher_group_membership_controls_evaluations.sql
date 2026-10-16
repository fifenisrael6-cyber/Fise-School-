-- Cyber: le code unique autorise uniquement l'adhésion aux groupes et l'accès aux évaluations.
-- Les cours, ressources, QCM d'apprentissage, fichiers et autres fonctions ne sont pas concernés.
-- L'accès à une évaluation s'active immédiatement quand l'élève devient membre du groupe
-- du professeur pour la même salle. Les règles d'appartenance restent contrôlées côté serveur.

create or replace function public.evaluation_is_visible_to_student(p_evaluation uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.evaluations e
    join public.evaluation_classes ec
      on ec.evaluation_id = e.id
    join public.class_students cs
      on cs.class_id = ec.class_id
     and cs.student_id = auth.uid()
     and cs.is_active
    join public.message_group_members gm
      on gm.user_id = cs.student_id
    join public.message_groups g
      on g.id = gm.group_id
     and g.owner_id = e.teacher_id
     and (
       g.class_id = ec.class_id
       or exists (
         select 1
         from public.message_group_classrooms gc
         where gc.group_id = g.id
           and gc.class_id = ec.class_id
       )
     )
    where e.id = p_evaluation
      and e.status in ('published', 'closed')
  );
$$;

-- Empêche aussi le démarrage d'une remise sans appartenance au groupe du professeur.
-- Cette fonction est utilisée par le flux de dépôt d'évaluation.
create or replace function public.evaluation_student_class(p_evaluation uuid, p_student uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select ec.class_id
  from public.evaluation_classes ec
  join public.evaluations e
    on e.id = ec.evaluation_id
  join public.class_students cs
    on cs.class_id = ec.class_id
   and cs.student_id = p_student
   and cs.is_active
  where ec.evaluation_id = p_evaluation
    and (
      p_student = auth.uid()
      and exists (
        select 1
        from public.message_group_members gm
        join public.message_groups g
          on g.id = gm.group_id
         and g.owner_id = e.teacher_id
         and (
           g.class_id = ec.class_id
           or exists (
             select 1 from public.message_group_classrooms gc
             where gc.group_id = g.id and gc.class_id = ec.class_id
           )
         )
        where gm.user_id = p_student
      )
    )
  order by cs.joined_at desc
  limit 1;
$$;

revoke all on function public.evaluation_is_visible_to_student(uuid) from public, anon;
grant execute on function public.evaluation_is_visible_to_student(uuid) to authenticated;
revoke all on function public.evaluation_student_class(uuid, uuid) from public, anon;
grant execute on function public.evaluation_student_class(uuid, uuid) to authenticated;
