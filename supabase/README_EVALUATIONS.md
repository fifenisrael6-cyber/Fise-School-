# Évaluations automatisées — mise en service (Supabase)

## 1. Pousser les migrations (dans cet ordre, automatique avec `supabase db push`)
- `20261015100000_eval_papers_and_submissions.sql` — épreuves PDF, remises photos, stockage privé, RLS
- `20261015110000_eval_correction_scores_validation.sql` — file de correction IA, notes, historique, validation
- `20261015120000_period_publication_and_bulletin_rules.sql` — publication programmée, classement, bulletin

## 2. Déployer la fonction de correction
```
supabase functions deploy evaluation-correct-worker --no-verify-jwt
supabase secrets set EVAL_WORKER_SECRET=<un-long-secret-aléatoire>
```
`GEMINI_API_KEY` doit déjà exister (utilisée par `grade-assignment`). Optionnel : `GEMINI_MODEL`, `EVAL_MIN_CONFIDENCE` (0.75 par défaut).

## 3. Relier la base à la fonction (SQL Editor, une seule fois)
```sql
select vault.create_secret('https://<REF_PROJET>.supabase.co/functions/v1/evaluation-correct-worker', 'fise_eval_worker_url');
select vault.create_secret('<le même secret que EVAL_WORKER_SECRET>', 'fise_eval_worker_secret');
```
Sans ces deux secrets, les remises sont enregistrées mais aucune correction ne démarre.

## 4. Vérifier
- Extensions `pg_net` et `pg_cron` activées (Database > Extensions).
- Tâches planifiées : `select jobname, schedule from cron.job where jobname like 'fise-%' or jobname like 'publish-fise%';`
  attendu : fise-eval-dispatch, fise-eval-reminders, fise-eval-notify-results, fise-period-publications.
- Le webhook `send-push` existant (INSERT sur `notifications`) envoie déjà les notifications push.

## Réglages
- Règle de classement : `update grading_settings set ranking_method = 'dense' | 'standard', min_subjects_for_rank = 1;`
