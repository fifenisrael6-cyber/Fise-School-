import 'package:supabase_flutter/supabase_flutter.dart';

/// Transforme les erreurs techniques de Supabase (en anglais) en messages
/// simples, dans la langue de l'utilisateur.
class AuthMessages {
  const AuthMessages._();

  static String from(
    AuthException error, {
    required bool english,
    bool registering = false,
  }) {
    final code = (error.code ?? '').toLowerCase();
    final text = error.message.toLowerCase();
    bool has(String part) => text.contains(part) || code.contains(part);

    String t(String fr, String en) => english ? en : fr;

    if (has('already registered') ||
        has('already been registered') ||
        has('user_already_exists') ||
        has('email_exists')) {
      return t(
        'Cet e-mail est déjà utilisé. Connectez-vous ou utilisez une autre adresse.',
        'This email is already in use. Log in or use another address.',
      );
    }
    if (has('weak_password') ||
        has('at least 6') ||
        has('password should be')) {
      return t(
        'Mot de passe trop faible : utilisez au moins 6 caractères.',
        'Password too weak: use at least 6 characters.',
      );
    }
    if (has('email_address_invalid') ||
        has('invalid email') ||
        has('unable to validate email') ||
        has('validation_failed')) {
      return t(
        'Adresse e-mail invalide. Vérifiez-la et réessayez.',
        'Invalid email address. Check it and try again.',
      );
    }
    if (has('invalid_credentials') || has('invalid login credentials')) {
      return t('Mot de passe incorrect', 'Incorrect password');
    }
    if (has('email_not_confirmed') || has('email not confirmed')) {
      return t(
        'Confirmez d’abord votre e-mail : ouvrez le lien reçu dans votre boîte de réception.',
        'Please confirm your email first: open the link sent to your inbox.',
      );
    }
    if (has('rate limit') ||
        has('rate_limit') ||
        has('too many') ||
        has('over_email_send_rate_limit') ||
        has('over_request_rate_limit')) {
      return t(
        'Trop de tentatives. Patientez quelques minutes avant de réessayer.',
        'Too many attempts. Please wait a few minutes before trying again.',
      );
    }
    if (has('signup_disabled') || has('signups not allowed')) {
      return t(
        'Les inscriptions sont momentanément fermées.',
        'Sign-ups are temporarily closed.',
      );
    }
    if (has('same_password') || has('different from the old')) {
      return t(
        'Le nouveau mot de passe doit être différent de l’ancien.',
        'The new password must be different from the old one.',
      );
    }
    if (has('otp_expired') || has('expired') || has('invalid_token')) {
      return t(
        'Ce lien a expiré ou n’est plus valide. Demandez-en un nouveau.',
        'This link has expired or is no longer valid. Request a new one.',
      );
    }
    if (has('database error') ||
        has('unexpected_failure') ||
        error.statusCode == '500') {
      return registering
          ? t(
              'Votre compte n’a pas pu être créé pour le moment. Vérifiez vos choix (classe, série) puis réessayez dans un instant.',
              'Your account could not be created right now. Check your choices (class, series) and try again shortly.',
            )
          : t(
              'Le service est momentanément indisponible. Réessayez dans un instant.',
              'The service is temporarily unavailable. Please try again shortly.',
            );
    }
    if (has('network') ||
        has('socket') ||
        has('failed host lookup') ||
        has('retryable')) {
      return t(
        'Pas de connexion internet. Vérifiez votre réseau et réessayez.',
        'No internet connection. Check your network and try again.',
      );
    }
    return t(
      'Une erreur est survenue. Veuillez réessayer.',
      'Something went wrong. Please try again.',
    );
  }
}
