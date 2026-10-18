-- Le code Flutter (évaluations : épreuves PDF et copies photo) et plusieurs
-- politiques de stockage utilisent le bucket « assignment-files », mais aucune
-- migration ne le créait : sur une base neuve, tout envoi échouait avec
-- « Bucket not found ». Création idempotente, bucket privé.
insert into storage.buckets (id, name, public)
values ('assignment-files', 'assignment-files', false)
on conflict (id) do nothing;
