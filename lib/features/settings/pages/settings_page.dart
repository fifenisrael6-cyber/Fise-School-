import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/services/push_service.dart';
import '../../../models/user_profile.dart';
import '../../notifications/pages/notifications_page.dart';
import 'offline_storage_page.dart';
import '../../teacher/pages/teacher_payment_code_page.dart';

class SettingsPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const SettingsPage({super.key, required this.locale, required this.profile});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool get isFrench => widget.locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          isFrench ? 'Réglages' : 'Settings',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProfileHeader(profile: profile, isFrench: isFrench),
          const SizedBox(height: 20),

          _SettingsSection(
            title: isFrench ? 'Compte' : 'Account',
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: isFrench ? 'Profil' : 'Profile',
                subtitle: isFrench
                    ? 'Consulter les informations de votre compte'
                    : 'View your account information',
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              _SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: isFrench ? 'Notifications' : 'Notifications',
                subtitle: isFrench
                    ? 'Consulter vos notifications'
                    : 'View your notifications',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(
                        locale: widget.locale,
                        userId: profile.id,
                      ),
                    ),
                  );
                },
              ),
              if (profile.role == 'teacher') ...[
                _SettingsTile(
                  icon: Icons.payments_outlined,
                  title: isFrench ? 'Code de paiement' : 'Payment code',
                  subtitle: isFrench
                      ? 'Votre code unique pour les paiements des élèves'
                      : 'Your unique code for student payments',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherPaymentCodePage(
                          locale: widget.locale,
                          profile: profile,
                        ),
                      ),
                    );
                  },
                ),
              ],

            ],
          ),

          const SizedBox(height: 16),

          _SettingsSection(
            title: isFrench
                ? 'Confidentialité et sécurité'
                : 'Privacy and security',
            children: [
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: isFrench ? 'Confidentialité' : 'Privacy',
                subtitle: isFrench
                    ? 'Comprendre comment vos informations sont protégées'
                    : 'Learn how your information is protected',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PrivacyPage(locale: widget.locale),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.security_outlined,
                title: isFrench ? 'Sécurité' : 'Security',
                subtitle: isFrench
                    ? 'Gérer les éléments de sécurité du compte'
                    : 'Manage your account security',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _SecurityPage(
                        locale: widget.locale,
                        profile: profile,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          _SettingsSection(
            title: isFrench ? 'Application' : 'Application',
            children: [
              _SettingsTile(
                icon: Icons.offline_bolt_rounded,
                title: isFrench ? 'Stockage hors ligne' : 'Offline storage',
                subtitle: isFrench
                    ? 'Gérer les cours téléchargés et l’espace utilisé'
                    : 'Manage downloaded courses and storage space',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OfflineStoragePage(
                        locale: widget.locale,
                        profile: profile,
                      ),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: isFrench
                    ? 'À propos de Fise School'
                    : 'About Fise School',
                subtitle: isFrench
                    ? 'Informations sur l’application'
                    : 'Information about the application',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _AboutPage(locale: widget.locale),
                    ),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: isFrench ? 'Se déconnecter' : 'Sign out',
                subtitle: isFrench
                    ? 'Fermer la session Fise School sur cet appareil'
                    : 'Sign out of Fise School on this device',
                destructive: true,
                onTap: () async {
                  // Local cleanup must never prevent the authentication
                  // session from being closed.
                  try {
                    await PushService.unregister();
                  } catch (_) {}

                  try {
                    await CourseOfflineService().deleteUserFiles(profile.id);
                  } catch (_) {}

                  try {
                    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isFrench
                                ? 'Impossible de fermer la session. Vérifiez votre connexion puis réessayez.'
                                : 'Unable to close the session. Check your connection and try again.',
                          ),
                        ),
                      );
                    }
                    return;
                  }

                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              )
            ],
          ),

          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.language_rounded, color: Color(0xFF166534)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFrench ? 'Langue actuelle' : 'Current language',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.preferredLanguage == 'en'
                            ? 'English'
                            : 'Français',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              'Fise School',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              isFrench
                  ? 'Plateforme éducative scolaire'
                  : 'School educational platform',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final bool isFrench;

  const _ProfileHeader({required this.profile, required this.isFrench});

  @override
  Widget build(BuildContext context) {
    final firstName = profile.firstName.trim();
    final lastName = profile.lastName.trim();
    final initials = [
      if (firstName.isNotEmpty) firstName[0],
      if (lastName.isNotEmpty) lastName[0],
    ].join().toUpperCase();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF166534),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(
                color: Color(0xFF166534),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName'.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email?.trim().isNotEmpty == true
                      ? profile.email!
                      : (isFrench
                            ? 'Compte Fise School'
                            : 'Fise School account'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF166534),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(children: _addDividers(children)),
        ),
      ],
    );
  }

  List<Widget> _addDividers(List<Widget> items) {
    final result = <Widget>[];

    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);

      if (i < items.length - 1) {
        result.add(const Divider(height: 1, indent: 70, endIndent: 16));
      }
    }

    return result;
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: destructive ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xFF166534)),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: destructive ? Colors.red : null),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: destructive ? Colors.red : Colors.grey),
      onTap: onTap,
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  final Locale locale;

  const _PrivacyPage({required this.locale});

  bool get isFrench => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          isFrench ? 'Confidentialité' : 'Privacy',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            icon: Icons.verified_user_outlined,
            title: isFrench ? 'Protection du compte' : 'Account protection',
            text: isFrench
                ? 'Votre compte est géré avec Supabase Auth. Le mot de passe n’est pas enregistré dans l’application Flutter.'
                : 'Your account is managed with Supabase Auth. Your password is not stored in the Flutter application.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.storage_outlined,
            title: isFrench ? 'Données scolaires' : 'School data',
            text: isFrench
                ? 'Les informations scolaires associées à votre profil sont utilisées pour déterminer votre espace, votre classe et les contenus auxquels vous avez accès.'
                : 'School information associated with your profile is used to determine your space, class, and the content you can access.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.admin_panel_settings_outlined,
            title: isFrench ? 'Accès contrôlé' : 'Controlled access',
            text: isFrench
                ? 'L’accès aux données doit être protégé par les règles de sécurité de Supabase et par les droits liés au rôle du compte.'
                : 'Access to data must be protected by Supabase security rules and by the permissions associated with the account role.',
          ),
        ],
      ),
    );
  }
}

class _SecurityPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const _SecurityPage({required this.locale, required this.profile});

  @override
  State<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<_SecurityPage> {
  bool _isLoading = false;

  bool get isFrench => widget.locale.languageCode == 'fr';

  Future<void> _sendPasswordReset() async {
    final email = widget.profile.email?.trim();

    if (email == null || email.isEmpty) {
      _showMessage(
        isFrench
            ? 'Aucune adresse e-mail n’est associée à ce compte.'
            : 'No email address is associated with this account.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      if (!mounted) {
        return;
      }

      _showMessage(
        isFrench
            ? 'Le lien de réinitialisation a été envoyé à votre adresse e-mail.'
            : 'The reset link has been sent to your email address.',
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        isFrench
            ? 'Impossible d’envoyer le lien de sécurité.'
            : 'Unable to send the security link.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.profile.email?.trim();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          isFrench ? 'Sécurité' : 'Security',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            icon: Icons.lock_outline_rounded,
            title: isFrench
                ? 'Réinitialiser le mot de passe'
                : 'Reset password',
            text: email == null || email.isEmpty
                ? (isFrench
                      ? 'Aucune adresse e-mail n’est disponible pour envoyer un lien de réinitialisation.'
                      : 'No email address is available to send a reset link.')
                : (isFrench
                      ? 'Un lien de réinitialisation sera envoyé à votre adresse e-mail.'
                      : 'A password reset link will be sent to your email address.'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading || email == null || email.isEmpty
                  ? null
                  : _sendPasswordReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF166534),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.email_outlined),
              label: Text(
                isFrench
                    ? 'Envoyer le lien de réinitialisation'
                    : 'Send reset link',
              ),
            ),
          ),
          const SizedBox(height: 20),
          _InfoCard(
            icon: Icons.account_circle_outlined,
            title: isFrench ? 'Identité du compte' : 'Account identity',
            text: isFrench
                ? 'Votre identité de connexion reste liée au compte Supabase actuellement connecté.'
                : 'Your sign-in identity remains linked to the currently authenticated Supabase account.',
          ),
        ],
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  final Locale locale;

  const _AboutPage({required this.locale});

  bool get isFrench => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          isFrench ? 'À propos' : 'About',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      backgroundColor: const Color(0xFFF5F8F6),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 48,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Fise School',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isFrench
                      ? 'Plateforme éducative scolaire'
                      : 'School educational platform',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _InfoCard(
            icon: Icons.school_outlined,
            title: isFrench ? 'Objectif' : 'Purpose',
            text: isFrench
                ? 'Fise School est conçue pour organiser les contenus, les cours, les leçons, les exercices et les échanges autour du parcours scolaire.'
                : 'Fise School is designed to organize content, courses, lessons, assignments, and communication around the school journey.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.language_rounded,
            title: isFrench ? 'Langues' : 'Languages',
            text: isFrench
                ? 'L’application prend en charge le français et l’anglais.'
                : 'The application supports French and English.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.public_outlined,
            title: isFrench ? 'Orientation scolaire' : 'School orientation',
            text: isFrench
                ? 'Les parcours sont organisés selon les sous-systèmes et secteurs scolaires configurés dans l’application.'
                : 'School paths are organized according to the sub-systems and sectors configured in the application.',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF166534)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.black54,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
