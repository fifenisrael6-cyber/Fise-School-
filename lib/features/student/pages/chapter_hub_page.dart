import 'package:flutter/material.dart';

/// Page d'accueil de navigation pour un chapitre (ou la liste des chapitres).
/// Le contenu est fourni par SubjectChannelPage afin de réutiliser les services
/// et les lecteurs existants sans modifier la base de données ni l'API.
class ChapterHubPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;

  const ChapterHubPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: actions,
      ),
      body: body,
    );
  }
}
