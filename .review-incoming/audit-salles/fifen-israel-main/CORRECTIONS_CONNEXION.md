# Connexion / inscription par e-mail uniquement

Code Flutter : téléphone supprimé (inscription, connexion, profil, listes admin, recherche).
Base Supabase : migration 202610010001_remove_phone_email_only.sql
  - déclencheur de création de profil sans téléphone
  - e-mail unique par profil
  - colonne profiles.phone supprimée
Fonction notchpay-payment : n'utilise plus le téléphone.
Écran d'accueil après connexion : corrigé (session_service.dart, auth_gate.dart, auth_page.dart).
Tableau de bord admin : 8 écrans d'administration.

DANS SUPABASE (Authentication) : désactiver "Confirm email" et "Confirm phone",
puis supprimer l'ancien compte de test (Authentication > Users).
