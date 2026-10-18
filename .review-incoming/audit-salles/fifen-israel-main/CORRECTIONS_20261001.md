# Fise School — corrections du 1er octobre 2026

## Corrections principales

- Renforcement RLS du forum : seuls les membres d'une classe peuvent lire les discussions.
- Création/modification/suppression des discussions réservées à l'administrateur ou aux enseignants affectés à la classe.
- Réponses interdites dans une discussion verrouillée pour les élèves ; les enseignants affectés et l'administrateur restent autorisés à intervenir.
- Suppression des anciennes politiques trop permissives du forum dans une nouvelle migration corrective.
- Pièces jointes du forum mieux alignées sur les droits de la classe.
- Nettoyage automatique d'un message si l'envoi de sa pièce jointe échoue.
- Ouverture des PDF/audio/vidéo du forum avec l'application externe appropriée au lieu d'afficher seulement l'URL.
- Cache hors ligne utilisé comme secours pour les cours et les leçons déjà synchronisés.
- Le cache local des cours/leçons est supprimé lors de la déconnexion afin d'éviter qu'un autre compte sur le même appareil récupère les contenus précédents.
- GitHub Actions exécute désormais `flutter analyze` avant la compilation APK.

## Important pour les enseignants

Un enseignant doit toujours être affecté à une classe dans `class_teachers` par l'administration avant de pouvoir gérer le forum et les cours de cette classe. Cette restriction est volontaire : elle empêche un enseignant de publier dans une classe à laquelle il n'appartient pas.

## Migration Supabase à appliquer

La nouvelle migration est :

`supabase/migrations/202610010002_forum_rls_and_teacher_scope.sql`

Elle doit être poussée après les migrations déjà présentes.

## Vérification

Le SDK Flutter n'est pas installé dans l'environnement ayant produit cette archive. Le code n'a donc pas été présenté comme compilé ici. Le workflow GitHub ajoute `flutter analyze` afin que la prochaine exécution GitHub bloque la compilation en cas d'erreur d'analyse.
