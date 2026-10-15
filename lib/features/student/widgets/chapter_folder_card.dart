import 'package:flutter/material.dart';

/// Carte ouvrant un dossier du chapitre.
class ChapterFolderCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;
  final String countLabel;

  const ChapterFolderCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
    required this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF166534);
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: green, size: 27),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count $countLabel',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(width: 7),
            const Icon(Icons.chevron_right_rounded, color: green),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
