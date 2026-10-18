import 'package:flutter/material.dart';

import 'admin_courses_page.dart';

class AdminPedagogyPage extends StatelessWidget {
  final Locale locale;

  const AdminPedagogyPage({super.key, required this.locale});

  bool get _isFrench => locale.languageCode == 'fr';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Gestion pédagogique' : 'Academic management',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeader(context),

          const SizedBox(height: 22),

          _buildModule(
            context,
            icon: Icons.menu_book_rounded,
            title: _isFrench ? 'Cours' : 'Courses',
            subtitle: _isFrench
                ? 'Créer, modifier, organiser et publier les cours dans les salles.'
                : 'Create, edit, organize and publish courses to classrooms.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminCoursesPage(locale: locale),
                ),
              );
            },
          ),

          _buildModule(
            context,
            icon: Icons.assignment_rounded,
            title: _isFrench
                ? 'Exercices et évaluations'
                : 'Exercises and assessments',
            subtitle: _isFrench
                ? 'Créer les exercices, questions, barèmes et choisir les salles.'
                : 'Create exercises, questions, scoring and choose classrooms.',
            onTap: () {
              _showComingSoon(
                context,
                _isFrench ? 'Gestion des exercices' : 'Exercise management',
              );
            },
          ),

          _buildModule(
            context,
            icon: Icons.photo_library_rounded,
            title: _isFrench ? 'Photos, PDF et ressources' : 'Photos, PDF and resources',
            subtitle: _isFrench
                ? 'Ajouter des photos, documents et autres ressources pédagogiques.'
                : 'Add photos, documents and other educational resources.',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminCoursesPage(locale: locale)));
            },
          ),

          _buildModule(
            context,
            icon: Icons.meeting_room_rounded,
            title: _isFrench
                ? 'Diffusion dans les salles'
                : 'Classroom publishing',
            subtitle: _isFrench
                ? 'Choisir exactement les salles qui doivent recevoir un contenu.'
                : 'Choose exactly which classrooms should receive content.',
            onTap: () {
              _showComingSoon(
                context,
                _isFrench
                    ? 'Diffusion dans les salles'
                    : 'Classroom publishing',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF166534), Color(0xFF21844A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              _isFrench
                  ? 'Centre de gestion des contenus pédagogiques'
                  : 'Central educational content management',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModule(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5EC),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFF166534), size: 27),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            subtitle,
            style: const TextStyle(height: 1.35, color: Colors.black54),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 17),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFrench ? '$title : ce module sera activé après la configuration du catalogue.' : '$title: this module will be enabled after catalog configuration.',
        ),
      ),
    );
  }
}
