# Catalogue des examens

Cette migration contient uniquement le catalogue des niveaux d'examen de Fise School.
Elle ne contient pas les classes scolaires ordinaires, les matières, les cours,
les devoirs, les forums ou la messagerie.

Migrations :

- `migrations/202609090001_exam_catalog.sql`
- `migrations/202609090002_profiles_and_school_classes.sql`
- `migrations/202609090003_student_promotions.sql`
- `migrations/202609090004_settings_notifications_storage.sql`

## Tables

- `exams` : examens eux-mêmes, par exemple BEPC, Probatoire, GCE Ordinary Level ou TVE Advanced Level.
- `exam_levels` : niveau ou classe d'examen, avec le sous-système, le secteur et l'examen associé.
- `series` : séries générales pouvant être ajoutées après validation officielle.
- `specialties` : filières ou spécialités techniques pouvant être ajoutées après validation officielle.
- `exam_level_series` : relation plusieurs-à-plusieurs entre un niveau et des séries.
- `exam_level_specialties` : relation plusieurs-à-plusieurs entre un niveau et des spécialités.

La seconde migration ajoute :

- `profiles` : profil applicatif lié à `auth.users`. Il contient le rôle,
  le sous-système, le secteur et des références optionnelles vers le catalogue.
  Aucun mot de passe n'y est stocké.
- `academic_years` : années scolaires réutilisables par les classes.
- `school_classes` : classes scolaires réelles, distinctes des niveaux d'examen.
  Une classe est rattachée à une année scolaire et peut référencer un niveau,
  une série ou une spécialité lorsqu'ils sont pertinents.
- `class_students` : appartenance historisable d'un élève à une classe grâce à
  `joined_at` et `is_active`.
- `class_teachers` : affectation historisable d'un enseignant à une classe grâce
  à `assigned_at` et `is_active`.
- `student_promotions` : historique des demandes de passage initiées par les
  élèves. La demande conserve les classes et années source/destination ainsi
  que son statut de validation.
- `notifications` : notifications privées par utilisateur avec état de lecture.
- `storage.profile-photos` : bucket privé pour les avatars, limité au dossier
  de l'utilisateur connecté.

`exam_level` ne représente donc pas une classe scolaire générique. Il représente
uniquement un niveau lié à un examen.

## Statuts de vérification

Les valeurs possibles sont :

- `verified` : donnée confirmée par une source officielle enregistrée dans `source_url`.
- `pending_official_confirmation` : donnée conservée pour la structure du catalogue,
  mais qui doit encore être confirmée par une source officielle.

Les niveaux anglophones et les noms GCE/TVE utilisent les pages officielles du
Cameroon GCE Board :

- https://camgceb.org/examinations/gce-ordinary-level/
- https://camgceb.org/examinations/gce-advanced-level/
- https://camgceb.org/examinations/tve-intermediate-level/
- https://camgceb.org/examinations/tve-advanced-level/

Les niveaux francophones sont présents avec le statut
`pending_official_confirmation`, car aucune page MINESEC exploitable n'a été
confirmée dans cette étape. Aucune série ou spécialité non vérifiée n'est insérée
comme donnée officielle.

## Relations

```text
exams
  1 ──── n exam_levels

exam_levels
  n ──── n series       via exam_level_series
  n ──── n specialties  via exam_level_specialties

auth.users
  1 ──── 1 profiles

academic_years
  1 ──── n school_classes

school_classes
  n ──── n profiles(student)   via class_students
  n ──── n profiles(teacher)   via class_teachers

school_classes
  n ──── 1 exam_levels/series/specialties (références optionnelles)

profiles(student)
  1 ──── n student_promotions
        (classe source → classe destination)

profiles
  1 ──── n notifications
```

Chaque table possède une clé UUID, des timestamps et un indicateur `active`.
Les tables sont protégées par RLS : la lecture des lignes actives est publique,
tandis que les insertions, modifications et suppressions nécessitent un JWT dont
`app_metadata.role` vaut `admin`. Le rôle `service_role` ne doit jamais être
embarqué dans Flutter.

Pour les nouvelles tables :

- un élève ou un enseignant peut lire son profil ;
- un élève ne voit que les classes auxquelles il appartient ;
- un enseignant ne voit que les classes qui lui sont affectées ;
- seuls les administrateurs gèrent les classes et les affectations ;
- le rôle `admin` est protégé par un trigger et un index unique partiel.

La création automatique d'un utilisateur Supabase crée un profil `student` ou
`teacher` à partir des métadonnées approuvées. La création d'un administrateur
reste une opération backend contrôlée.

## Promotions

Un élève connecté crée sa propre demande `pending` depuis l'écran **Ma
promotion**. Le backend vérifie l'appartenance à la classe source de l'année
courante, l'existence de l'année suivante, la compatibilité du sous-système,
du secteur et de la série/spécialité, ainsi que l'absence de demande active
pour la même année destination.

L'élève peut uniquement annuler une demande en attente. Un administrateur peut
la valider ou la rejeter, mais ne la crée pas à la place de l'élève. Lorsqu'une
demande est approuvée, un trigger ajoute l'élève à la classe destination sans
supprimer son affectation historique.

Les champs de rôle et de scolarité sont protégés par trigger backend. Les
utilisateurs peuvent modifier leur identité et leur langue, mais pas leur rôle
ou leur parcours scolaire.
