# Finalisation de la messagerie — 9 octobre 2026

## Périmètre de cette branche

La branche `fix/in-app-message-media-viewer` contient les changements suivants :

- lecteur intégré aux conversations pour les images (plein écran et zoom), PDF, audio et vidéo ;
- enregistrement et envoi de notes vocales dans les conversations privées et les groupes ;
- options de suppression de messages avec confirmation ;
- mode de consultation unique des pièces jointes, avec URL signée de courte durée et état conservé côté serveur ;
- accusés de livraison et de lecture pour les conversations privées et les groupes ;
- contrôle d'accès aux contacts privés via les règles existantes d'autorisation et le code unique de l'enseignant ;
- retrait de l'accès au forum dans les routes et les entrées d'interface remplacées par la messagerie ;
- retrait des dépendances aux anciens modèles/services du forum dans les écrans de notes.

## Migrations Supabase ajoutées

1. `202610090001_private_message_controls.sql`
2. `202610090002_message_view_once.sql`
3. `202610090003_retire_forum.sql`
4. `202610090004_group_message_receipts.sql`
5. `202610090005_group_attachment_delete.sql`

**Attention :** la migration `202610090003_retire_forum.sql` supprime les anciennes tables et pièces jointes du forum, ainsi que les notifications de type `forum`. Faire une sauvegarde avant de l'appliquer en production si les anciennes discussions doivent encore être conservées.

## Ordre de vérification avant publication

1. Lire et appliquer ces migrations sur un projet Supabase de test, dans l'ordre des numéros ; vérifier les politiques de stockage et l'accès aux RPC avec un compte élève, un compte enseignant et un compte membre de groupe.
2. Résoudre les dépendances Flutter avec `flutter pub get` afin de mettre également à jour `pubspec.lock` pour `record`.
3. Exécuter `flutter analyze`, puis la compilation Android dans GitHub Actions.
4. Sur un appareil, vérifier l'ouverture plein écran des photos, le zoom, la lecture de PDF/audio/vidéo, l'enregistrement vocal, la suppression, les accusés, le mode consultation unique et le retour à la conversation.
5. Vérifier l'ouverture de session et le chargement des matières/cours ainsi que le mode hors ligne après ces changements.

## Limites connues de validation

Cette branche n'a pas été compilée ni testée sur appareil dans le cadre de cette modification. Les migrations ne sont pas confirmées comme appliquées à la base Supabase. Le retrait du forum reste donc effectif dans le code de cette branche, mais le changement de schéma de production ne se fera qu'au déploiement de la migration correspondante.

L'icône, le splash screen et le code du mode hors ligne n'ont pas été volontairement modifiés.
