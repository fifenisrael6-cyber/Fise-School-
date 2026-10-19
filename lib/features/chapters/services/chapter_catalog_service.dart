import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Dossiers logiques disponibles dans chaque chapitre.
/// Les clés sont stables pour la base de données et le stockage existants.
enum ChapterFolderKind {
  cours('cours', 'Cours écrit'),
  pdf('pdf', 'PDF'),
  video('video', 'Vidéo'),
  audio('audio', 'Audio'),
  image('image', 'Image'),
  exercices('exercices', 'Exercices');

  const ChapterFolderKind(this.key, this.labelFr);

  final String key;
  final String labelFr;

  static ChapterFolderKind? fromKey(String key) {
    for (final folder in values) {
      if (folder.key == key) return folder;
    }
    return null;
  }
}

/// Représente un dossier logique, même si aucun fichier n'y est publié.
class ChapterFolder {
  const ChapterFolder({required this.kind, this.itemCount = 0});

  final ChapterFolderKind kind;
  final int itemCount;

  bool get isEmpty => itemCount == 0;

  String get emptyMessage => 'Pas encore de contenu';
}

/// Une entrée de chapitre issue du catalogue JSON, sans dépendance Supabase.
class ChapterCatalogEntry {
  const ChapterCatalogEntry({
    required this.subsystem,
    required this.education,
    required this.className,
    required this.stream,
    required this.subject,
    required this.language,
    required this.number,
    required this.title,
    required this.verificationStatus,
  });

  final String subsystem;
  final String education;
  final String className;
  final String stream;
  final String subject;
  final String language;
  final int number;
  final String title;
  final String verificationStatus;

  bool get needsVerification =>
      verificationStatus.toLowerCase() == 'a_verifier' ||
      title.toUpperCase().contains('À VÉRIFIER');

  String get displayTitle => language == 'en'
      ? 'Chapter $number: $title'
      : 'Chapitre $number : $title';

  /// Les six dossiers existent dans l'interface même sans contenu.
  List<ChapterFolder> createEmptyFolders() => ChapterFolderKind.values
      .map((kind) => ChapterFolder(kind: kind))
      .toList(growable: false);

  factory ChapterCatalogEntry.fromMap(
    Map<String, dynamic> programme,
    Map<String, dynamic> chapter,
  ) {
    final number = chapter['numero'];
    if (number is! int || number < 1) {
      throw const FormatException('Le numéro du chapitre doit être positif.');
    }

    final title = (chapter['titre'] as String? ?? '').trim();
    if (title.isEmpty) {
      throw const FormatException('Le titre du chapitre est obligatoire.');
    }

    return ChapterCatalogEntry(
      subsystem: programme['sous_systeme'] as String? ?? '',
      education: programme['enseignement'] as String? ?? '',
      className: programme['classe'] as String? ?? '',
      stream: programme['filiere'] as String? ?? 'commun',
      subject: programme['matiere'] as String? ?? '',
      language: programme['langue'] as String? ?? 'fr',
      number: number,
      title: title,
      verificationStatus: chapter['statut'] as String? ?? 'a_verifier',
    );
  }
}

/// Charge le catalogue depuis un JSON séparé du code Dart.
class ChapterCatalogService {
  static const String assetPath = 'assets/data/chapter_catalog.json';

  Future<List<ChapterCatalogEntry>> loadCatalog() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('La racine du catalogue doit être un objet JSON.');
      }

      final programmes = decoded['programmes'];
      if (programmes is! List) {
        throw const FormatException('Le catalogue doit contenir une liste programmes.');
      }

      final entries = <ChapterCatalogEntry>[];
      final seen = <String>{};
      for (final rawProgramme in programmes) {
        if (rawProgramme is! Map) continue;
        final programme = Map<String, dynamic>.from(rawProgramme);
        final rawChapters = programme['chapitres'];
        if (rawChapters is! List) continue;

        for (final rawChapter in rawChapters) {
          if (rawChapter is! Map) continue;
          final entry = ChapterCatalogEntry.fromMap(
            programme,
            Map<String, dynamic>.from(rawChapter),
          );
          final uniqueKey = [
            entry.subsystem,
            entry.education,
            entry.className,
            entry.stream,
            entry.subject,
            entry.number,
          ].join('|').toLowerCase();

          if (!seen.add(uniqueKey)) {
            throw FormatException('Chapitre dupliqué dans le catalogue : $uniqueKey');
          }
          entries.add(entry);
        }
      }
      return List.unmodifiable(entries);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Impossible de charger le catalogue des chapitres : $error');
    }
  }
}
