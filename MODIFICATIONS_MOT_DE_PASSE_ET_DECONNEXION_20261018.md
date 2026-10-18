# Fise School — mot de passe oublié + nettoyage à la déconnexion (18 octobre 2026)

- Écran de connexion : lien « Mot de passe oublié ? » (mode connexion uniquement).
- Paramètres : l'envoi du lien utilise la même adresse de retour `fiseschool://reset-password`.
- Supabase (à faire à la main) : Authentication → URL Configuration → Redirect URLs → ajouter `fiseschool://reset-password`.
- Déconnexion : nettoyage des caches de messages, contacts, groupes, catalogue, leçons intelligentes, QCM, cache JSON.

Fichiers : auth_page.dart, settings_page.dart, session_service.dart, app_database.dart.
Non compilé ici : `flutter analyze` sur GitHub Actions le vérifiera.
