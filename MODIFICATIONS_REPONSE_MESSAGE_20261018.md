# Fise School — répondre à un message précis (18 octobre 2026)

## À appliquer
1. Migration Supabase : `supabase/migrations/20261019100000_message_reply_to.sql`
   (à pousser après les migrations existantes, comme les autres).
2. Remplacer les fichiers Flutter listés plus bas, puis compiler (GitHub Actions ou `flutter run`).

## Fonctionnement (messages privés ET groupes)
- **Glisser un message vers la droite** (ou **appui long**) : un bandeau « Répondre à … »
  apparaît au-dessus de la zone d'écriture (bouton ✕ pour annuler).
- À l'envoi, le message est affiché avec la **citation** du message d'origine en haut de la bulle.
- Marche aussi **hors ligne** : la réponse part avec la file d'attente et se synchronise.
- Un message en cours d'envoi (◷) ne peut pas encore être cité.
- Si le message cité n'est plus visible (supprimé, ou antérieur à l'arrivée dans le groupe) :
  « Message indisponible ».

## Fichiers
- `supabase/migrations/20261019100000_message_reply_to.sql` (nouveau)
  colonne `reply_to_id`, contrôle « même conversation », fonction des groupes mise à jour.
- `lib/features/messages/widgets/message_reply.dart` (nouveau)
- `lib/features/messages/pages/group_chat_page.dart`
- `lib/features/messages/pages/private_messages_page.dart`
- `lib/core/services/group_message_service.dart`
- `lib/core/services/private_message_service.dart`
- `lib/core/offline/app_database.dart` (base locale passée en version 6)
- `lib/models/message_group.dart`, `lib/models/private_message.dart`

## Vérification
Le SDK Flutter n'est pas installé ici : le code n'a pas été compilé (seulement relu).
`flutter analyze` dans GitHub Actions le fera au prochain push.
