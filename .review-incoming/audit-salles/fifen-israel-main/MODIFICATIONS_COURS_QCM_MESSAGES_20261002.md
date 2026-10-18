# Fise School — cours, QCM et messages (2 octobre 2026)

## À appliquer
- Migration Supabase : `supabase/migrations/202610020006_cours_canaux_groupes.sql`
  (à pousser après les migrations existantes).

## Enseignant
- **Créer un cours** : choisir la ou les classes, la matière (matières de base de la salle),
  titre, texte, puis joindre PDF / photo prise à la caméra / images / autre fichier.
  Le cours est publié dans chaque classe choisie.
- **Ajouter une matière** : bouton dans le choix de matière (matières du même sous-système
  et secteur que la salle).
- **QCM** : nouvel espace (`qcm_builder_page.dart`) : classes, matière, titre, questions à
  4 réponses, bonne réponse, date limite facultative, publication dans plusieurs classes.
- **Messages** : groupes avec code d'invitation unique (créé par l'enseignant, régénérable).
- **Paramètres** : le code de paiement est maintenant dans Paramètres ; la tuile
  « Notifications » de l'accueil est retirée (elle existe déjà dans Paramètres).

## Élève
- **Cours** : grille des matières de la salle ; chaque matière ouvre un fil (cours, documents,
  photos, QCM), le plus récent en bas.
- **Messages** : liste de groupes ; on rejoint un groupe uniquement avec le code de l'enseignant.

## Base de données
- Matières de base ajoutées automatiquement à chaque salle (nouvelles et existantes), selon
  les listes déjà utilisées par `admin_apply_base_subject_catalog`.
- `courses.curriculum_id` / `chapter_id` deviennent facultatifs ; `assignments.course_id`
  devient facultatif, avec `assignments.subject_id`.
- Tables `message_groups`, `message_group_members`, `message_group_messages`, bucket privé
  `group-message-attachments`, RLS et fonctions RPC.

## Non modifié
Forum, notes, bulletins, emploi du temps, IA, paiements, administration, messages privés
(toujours accessibles depuis Messages).

## Vérification
Le SDK Flutter n'est pas installé ici : le code n'a pas été compilé. `flutter analyze`
dans GitHub Actions le fera au prochain push.
