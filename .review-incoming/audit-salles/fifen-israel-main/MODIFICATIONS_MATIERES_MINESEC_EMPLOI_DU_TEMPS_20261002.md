# Fise School — matières MINESEC par salle et emploi du temps personnel (2 octobre 2026)

## À appliquer
Migration Supabase : `supabase/migrations/202610020008_minesec_subjects_and_personal_timetable.sql`
(après `202610020007`).

## Matières de l'espace Cours (élève)
- 36 nouvelles matières ajoutées (EPS, Travail manuel, Éducation artistique, ESF, Sciences,
  Physique-Chimie-Technologie, Littérature, langues vivantes II : allemand, espagnol, italien,
  chinois, arabe, comptabilité, commerce, matières techniques, etc.).
- Table `level_subject_catalog` : liste des matières de **chaque niveau** (33 niveaux :
  francophone général et technique, anglophone général et technique).
  Obligatoires = matières de base ; options = choix de l'élève / de la série.
- Table `series_subject_catalog` : pour une salle rattachée à une série (C, D, A1…A5, AC, TI,
  GCE Arts / Science), les matières de la série passent en obligatoires.
- Le bouton « catalogue de base » de l'admin applique maintenant ce catalogue à toutes les salles ;
  les nouvelles salles le reçoivent automatiquement.
- Une matière désactivée par l'admin dans une salle reste désactivée.
- L'admin peut modifier le catalogue (tables ci-dessus) et ajouter des matières à une salle.

## Emploi du temps de l'élève
- Deux onglets : **Mon planning** (créé par l'élève) et **Ma salle** (fourni par l'école, lecture seule).
- Ajouter / modifier / supprimer (glisser vers la gauche) un créneau : matière de sa salle ou
  activité libre, jour, heure de début et de fin, lieu, note.
- Refus des créneaux qui se chevauchent le même jour.
- Bouton « Partir de l'emploi du temps de ma salle » : copie les créneaux de la salle.

## Limites
- Le catalogue est une base construite à partir de la structure des programmes MINESEC / GCE,
  sans document officiel officiellement validé ici : à relire par l'administration.
- Les spécialités techniques détaillées (électrotechnique, comptabilité de gestion, etc.)
  ne sont pas listées : l'admin les ajoute par salle.
- Le SDK Flutter n'est pas installé ici : rien n'a été compilé ni testé.
  `flutter analyze` dans GitHub Actions le fera au prochain push.
