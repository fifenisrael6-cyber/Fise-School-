# Fise School — audit et corrections (30 septembre 2026)

## Corrections intégrées
- Caméra Android déclarée (`CAMERA`) et microphone (`RECORD_AUDIO`).
- Messagerie privée: caméra, galerie/fichiers, envoi de pièces jointes, stockage Supabase privé et affichage des images.
- IA Fise School: caméra/galerie dans les deux écrans IA et transmission d'image à Gemini via une Edge Function sécurisée.
- Clé Gemini conservée côté serveur (`GEMINI_API_KEY`), jamais dans Flutter.
- Catalogue scolaire: 7 niveaux général francophone, 7 général anglophone, 7 technique francophone et 7 technique anglophone pour la base des 28 salles 2026-2027.
- Classes techniques francophones corrigées vers Année 1 à 4, 2nde T, 1ère T, Tle T; CAP lié à la 4e année et Probatoire/Baccalauréat au second cycle.
- Catalogue des séries générales francophones et groupes Arts/Science du GCE.
- Catalogue de spécialités techniques MINESEC ajouté et lié aux niveaux techniques du second cycle.
- Les salles sont créées automatiquement pour l'année académique 2026-2027 et restent administrables.
- Les classes d'examen sont reliées au catalogue d'examens; les classes sans examen restent utilisables pour la progression scolaire.

## Vérification officielle utilisée
- MINESEC: sous-système francophone et structure 7 ans général.
- MINESEC: enseignement secondaire technique et professionnel.
- Cameroon GCE Board: GCE Ordinary Level et Advanced Level.
- Cameroon GCE Board: structure TVEE.

## Déploiement
1. Pousser les migrations vers Supabase.
2. Déployer `supabase/functions/gemini-chat`.
3. Dans Supabase, définir le secret `GEMINI_API_KEY`.
4. Pour GitHub Actions de fonction, ajouter `SUPABASE_ACCESS_TOKEN` et `SUPABASE_PROJECT_REF`.
5. Refaire l'APK avec les secrets Supabase déjà utilisés par le projet.

## Limitation de l'audit
L'environnement d'analyse actuel ne contient pas Flutter/Dart, donc je n'ai pas pu exécuter `flutter analyze` ni produire un APK ici. Le code a été contrôlé structurellement; le build GitHub reste l'étape de validation finale.
