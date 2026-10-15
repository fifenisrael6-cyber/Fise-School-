# Mode hors ligne façon WhatsApp — 15 octobre 2026

Limite : aucun SDK Flutter n'était disponible, le code n'a pas été compilé ni testé sur téléphone.
À faire : `flutter pub get`, `flutter analyze`, puis essai en mode avion.

## Constat
Le projet contenait des briques hors ligne non branchées (bandeau, file de progression, nettoyage
à la déconnexion) : l'app ne s'ouvrait pas sans réseau (profil relu sur le serveur) et la messagerie
échouait. Le mode de paiement n'a pas été modifié.

## Ajouté
- `lib/core/offline/message_outbox.dart` : file d'envoi des messages (privés et groupes), pièces
  jointes comprises. Message visible tout de suite (horloge), envoyé dans l'ordre au retour du
  réseau, sans doublon (identifiant UUID choisi par l'appareil), échec marqué sans bloquer la suite.
- `lib/core/widgets/swipe_tabs_shell.dart` : navigation par balayage entre onglets.

## Branché / corrigé
- Profil mis en cache (l'app s'ouvre sans réseau, profil du même compte uniquement).
- Bandeau « mode hors ligne » affiché dans toute l'app (`app.dart`), avec le nombre d'éléments en attente.
- Envoi automatique de la file et de la progression au retour du réseau et au démarrage (`auth_gate.dart`).
- Messages privés et de groupe : contacts, groupes, conversations, membres lisibles hors ligne ;
  messages en attente avec horloge ; appui long = renvoyer / supprimer.
- Progression des leçons : ouverture et « terminer la leçon » enregistrées localement puis envoyées.
- Copies locales : documents d'un cours/leçon, emploi du temps, notifications, annales,
  périodes et bulletins, écran Progression.
- Toutes les déconnexions passent par `clearLocalUserData()` (efface aussi la file des messages).
- Variables `catch` inutilisées supprimées (avertissements bloquants de `flutter analyze`).

## Sans réseau, ça reste impossible
Ouvrir un PDF/vidéo non téléchargé, l'IA, supprimer un message, valider un code enseignant,
paiement.
