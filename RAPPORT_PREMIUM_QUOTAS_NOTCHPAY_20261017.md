# Rapport — Premium 2 000 FCFA, quotas 24 h, Notch Pay, sécurité (17/10/2026)

**Statut : code modifié dans l'archive uniquement. Rien n'est poussé, déployé ni testé en conditions réelles.**
Aucune compilation Flutter/Dart, aucun test Deno, aucune exécution SQL n'ont pu être faits dans cet environnement
(pas de Flutter, Deno ni PostgreSQL). Les fichiers ont seulement été relus et leurs parenthèses vérifiées.

## Constats sur le dépôt avant modification
- Prix codé à **1 000 FCFA** (Flutter, Edge Function, SQL) au lieu de 2 000.
- Commission : 200 FCFA pour un seul enseignant (code enseignant), pas 200 scientifique + 200 littéraire.
- `PremiumPage` / `PaymentPage` n'étaient reliées à **aucun écran** : Premium était inaccessible.
- Aucun contrôle Premium/quota sur leçons, QCM, annales, messagerie. Seule l'IA avait un quota.
- `consume_ai_daily_limits` (appelée par `gemini-chat`) n'était **définie dans aucune migration** du dépôt.
- `notchpay-callback` n'était pas déployée avec `--no-verify-jwt` (la redirection navigateur aurait été refusée).
- Callback : montant et devise non vérifiés auprès de Notch Pay ; aucun webhook signé.
- RLS `payment_orders` : un élève pouvait insérer sa propre commande (statut, montant, commissions).
- `functions.invoke` lève une exception sur 429 : le message de quota IA n'était pas reconnu côté Flutter.
- Évaluations : `submit_chapter_quiz` est déjà serveur (clés de correction non lisibles) — conservé.

## Modifications
**Migration** `supabase/migrations/20261017100000_premium_quota_and_payment_hardening.sql`
prix 2 000 / 30 j ; `profiles.teaching_stream` ; commissions 200+200 (reste 1 600 plateforme) tracées dans
`teacher_wallet_transactions` (unique par commande+enseignant) ; `finalize_notchpay_payment` idempotente avec
contrôle du montant réellement payé ; `payment_events` (audit/déduplication) ; quotas 24 h glissants côté serveur
(`consume_feature_quota`, verrou par utilisateur, grants par ressource, remboursement IA) ; `get_my_quota_status` ;
`consume_ai_daily_limits` ; triggers d'envoi de message et de tentative QCM ; fonctions sensibles réservées à `service_role`.

**Edge Functions** : `_shared/notchpay.ts`, `notchpay-payment` (prix serveur, enseignants résolus serveur),
`notchpay-callback` (vérification Notch Pay), `notchpay-webhook` (HMAC-SHA256 `x-notch-signature`),
`notchpay-verify` (retour tardif), `gemini-chat` (402 Premium requis, remboursement d'unité si échec).
**Workflow** `supabase-functions.yml` : `--no-verify-jwt` pour callback/webhook, déploiement des 2 nouvelles fonctions.

**Flutter** : `quota_service.dart`, `premium_gate.dart` (fenêtre Premium + paiement Notch Pay + reprise de l'action),
`message_quota_events.dart` ; branchements leçons, QCM, annales, IA, messagerie privée/groupes ; `PremiumPage`
(2 000 FCFA, état gratuit/en attente/actif/expiré, quotas restants + réinitialisation) ; entrée dans le **profil** élève.

## Deuxième passe (migration `20261017110000_content_protection_and_received_quota.sql`)
- **Messages privés reçus** : 2 / 24 h, appliqué par RLS + `list_private_messages` (messages au-delà du quota
  renvoyés « verrouillés », tap = fenêtre Premium). Ne concerne que les messages reçus après la migration.
- **Leçons/exercices/QCM, fichiers de chapitres, annales, pièces jointes de cours** : lecture refusée par RLS/Storage
  sans droit valide (ouverture autorisée dans les 24 h, ou Premium). Catalogue, chapitres et titres restent gratuits.
- **Pièces jointes de messagerie** : téléversement Storage réservé au Premium (élèves).
- **Admin** : choix « Scientifique / Littéraire » dans la fiche enseignant (`admin_set_teacher_stream`).
- **Expiration** : tâche pg_cron créée seulement si l'extension est active.
- **Connexion** : message « Mot de passe incorrect » ajouté ; lien « Mot de passe oublié » et option « Stockage hors ligne »
  retirés des écrans (ils étaient présents dans ce dépôt) ; fichiers conservés. Changement de salle : présent dans Paramètres.

## Limites restantes (honnêtes)
1. **Messages de groupe reçus** : non limités (seul l'envoi l'est).
2. **Texte des leçons de cours** (`lessons.content_*`) : la liste des leçons et leur texte sont dans la même table ;
   non verrouillé côté serveur (seuls les fichiers joints le sont).
3. **Téléchargement hors ligne de chapitres** pour un élève gratuit : exige d'avoir ouvert le chapitre (droit 24 h).
   Les contenus déjà téléchargés restent lisibles.
4. Retraits Orange/MTN, vitesse de l'IA : non traités ni vérifiés.
5. **Rien n'a été compilé ni exécuté** (ni Flutter, ni Deno, ni SQL). Les politiques RLS/Storage sont les plus à risque :
   à tester sur une base de test avant production (élève gratuit, Premium, enseignant, admin).

## À faire avant mise en production
- Relire la migration : **un push sur `main` l'applique automatiquement** (workflow `supabase-migrations.yml`).
- `supabase secrets set NOTCHPAY_WEBHOOK_HASH=...` et déclarer l'URL `…/functions/v1/notchpay-webhook` dans Notch Pay.
- Vérifier si `consume_ai_daily_limits` existe déjà en production (elle y a peut-être été créée à la main) : ma migration la remplace.
- Lancer le build (GitHub Actions) et tester : paiement réussi/refusé/annulé, notification rejouée, expiration, quotas.

## Troisième passe — messagerie « comme les autres applications »
- Migration `20261017120000_message_avatars.sql` : photos de profil lisibles par les utilisateurs connectés ;
  `avatar_path` ajouté aux contacts privés et aux messages de groupe.
- Photo de profil affichée à côté de chaque message (la vôtre à droite, celle de l'autre à gauche), dans la liste des
  contacts et l'en-tête de conversation. Hors ligne ou sans photo : initiales.
- Pièces jointes : image plein écran zoomable ; notes vocales/audio avec lecteur (lecture, pause, barre, durée) ;
  vidéo avec lecteur plein écran ; PDF lu dans l'application ; autres documents (Word, Excel…) en carte, ouverts avec
  l'application du téléphone.
- Messages vocaux : bouton micro (nouvelle dépendance `record`, permission micro iOS ajoutée). Une note vocale est une
  pièce jointe : réservée au Premium comme les photos et documents.
- Non vérifié : compilation, enregistrement réel sur téléphone, lecture vidéo/audio en production.
