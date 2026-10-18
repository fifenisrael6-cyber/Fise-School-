import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/exam_catalog.dart';

class ExamCatalogService {
  final SupabaseClient _client;

  ExamCatalogService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<ExamSubsystem>> getSubsystems() async {
    final rows = await _client
        .from('exam_levels')
        .select('subsystem')
        .eq('active', true);
    final values = rows
        .map((row) => examSubsystemFromValue(row['subsystem']))
        .whereType<ExamSubsystem>()
        .toSet()
        .toList();
    values.sort((a, b) => a.name.compareTo(b.name));
    return values;
  }

  Future<List<ExamSector>> getSectors(ExamSubsystem subsystem) async {
    final rows = await _client
        .from('exam_levels')
        .select('sector')
        .eq('subsystem', subsystem.name)
        .eq('active', true);
    final values = rows
        .map((row) => examSectorFromValue(row['sector']))
        .whereType<ExamSector>()
        .toSet()
        .toList();
    values.sort((a, b) => a.name.compareTo(b.name));
    return values;
  }

  Future<List<ExamDefinition>> getExams() async {
    final rows = await _client
        .from('exams')
        .select()
        .eq('active', true)
        .order('name_fr');
    return rows
        .map((row) => ExamDefinition.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ExamLevel>> getExamLevels({
    required ExamSubsystem subsystem,
    required ExamSector sector,
  }) async {
    final rows = await _client
        .from('exam_levels')
        // Jointure gauche : les classes sans examen (6ème, Form 1...) sont incluses.
        .select('*, exams(*)')
        .eq('subsystem', subsystem.name)
        .eq('sector', sector.name)
        .eq('active', true)
        .order('level_order')
        .order('level_name_fr');
    return rows
        .map((row) => ExamLevel.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ExamCatalogEntry>> getSeriesForLevel(String examLevelId) async {
    final rows = await _client
        .from('exam_level_series')
        .select('series!inner(*)')
        .eq('exam_level_id', examLevelId)
        .eq('active', true)
        .eq('series.active', true);
    return rows
        .map(
          (row) => ExamCatalogEntry.fromMap(
            Map<String, dynamic>.from(row['series'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ExamCatalogEntry>> getSeries() async {
    final rows = await _client
        .from('series')
        .select()
        .eq('active', true)
        .order('name_fr');
    return rows
        .map((row) => ExamCatalogEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ExamCatalogEntry>> getSpecialtiesForLevel(
    String examLevelId,
  ) async {
    final rows = await _client
        .from('exam_level_specialties')
        .select('specialties!inner(*)')
        .eq('exam_level_id', examLevelId)
        .eq('active', true)
        .eq('specialties.active', true);
    return rows
        .map(
          (row) => ExamCatalogEntry.fromMap(
            Map<String, dynamic>.from(row['specialties'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ExamCatalogEntry>> getSpecialties() async {
    final rows = await _client
        .from('specialties')
        .select()
        .eq('active', true)
        .order('name_fr');
    return rows
        .map((row) => ExamCatalogEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}
