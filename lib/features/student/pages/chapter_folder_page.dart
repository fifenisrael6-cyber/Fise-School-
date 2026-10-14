import 'package:flutter/material.dart';

/// Liste indépendante d'un dossier. Les lecteurs existants sont fournis par
/// la page appelante afin de conserver les API et le fonctionnement hors ligne.
class ChapterFolderPage extends StatelessWidget {
  final String title;
  final List<Widget> items;
  final String emptyMessage;
  final String? subtitle;

  const ChapterFolderPage({
    super.key,
    required this.title,
    required this.items,
    required this.emptyMessage,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 58, color: Color(0xFF166534)),
                    const SizedBox(height: 14),
                    Text(emptyMessage, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (subtitle != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(subtitle!, style: const TextStyle(color: Colors.black54)),
                  ),
                ],
                ...items,
              ],
            ),
    );
  }
}
