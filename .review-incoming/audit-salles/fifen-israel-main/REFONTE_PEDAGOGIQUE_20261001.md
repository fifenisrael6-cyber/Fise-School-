# Refonte pédagogique Fise School — 2026-10-01

## Parcours enseignant
- La salle de classe est choisie avant la matière lors de la création d'un cours.
- Les matières proposées viennent uniquement de `class_subjects` pour la salle choisie.
- La salle et la matière sélectionnées restent visibles dans le formulaire du cours.
- Les QCM/exercices ne demandent plus d'UUID : **Salle → Cours → Leçon**.
- Les enseignants peuvent ouvrir directement **Documents / médias** depuis un cours.
- Les identifiants techniques restent gérés automatiquement par l'application et Supabase.

## Parcours cible
**Salle → Matière → Programme → Chapitre → Cours → Leçon / Documents / QCM / Exercices → Élève → Progression.**

## Sécurité serveur
La migration `202610010003_assignment_course_scope.sql` empêche également qu'un client contourne l'interface et associe un QCM à une autre salle, à un autre cours ou à une leçon étrangère au cours.

## 2026-10-01 — administration pédagogique
- L'administrateur peut créer un cours en choisissant Salle → Matière de la salle → Programme → Chapitre.
- L'administrateur peut ajouter un PDF, document, photo prise par la caméra ou photo de la galerie à un cours.
- Une fonction Supabase permet d'appliquer le catalogue de base des matières aux salles actives, puis l'administrateur peut ajuster chaque salle.
- Le site officiel du MINESEC publie séparément les programmes d'enseignement général et technique du sous-système francophone, ainsi que les syllabus général et technique du sous-système anglophone. Le catalogue de Fise School doit rester administrable pour suivre les options et mises à jour officielles.
