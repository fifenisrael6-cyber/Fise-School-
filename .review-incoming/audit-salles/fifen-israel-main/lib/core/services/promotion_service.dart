import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/school_class.dart';
import '../../models/student_promotion.dart';
import '../../models/user_profile.dart';

class PromotionContext {
  final AcademicYear currentYear;
  final AcademicYear? nextYear;
  final SchoolClass? currentClass;
  final List<SchoolClass> destinationClasses;
  final StudentPromotion? request;

  const PromotionContext({
    required this.currentYear,
    required this.nextYear,
    required this.currentClass,
    required this.destinationClasses,
    required this.request,
  });
}

class PromotionService {
  final SupabaseClient _client;

  PromotionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<PromotionContext> loadContext(UserProfile profile) async {
    final currentYearMap = await _client
        .from('academic_years')
        .select()
        .eq('is_current', true)
        .maybeSingle();
    if (currentYearMap == null) {
      throw const PostgrestException(message: 'No current academic year.');
    }
    final currentYear = AcademicYear.fromMap(currentYearMap);

    final nextYearMap = currentYear.startDate == null
        ? null
        : await _client
              .from('academic_years')
              .select()
              .gt('start_date', currentYear.startDate!.toIso8601String())
              .order('start_date')
              .limit(1)
              .maybeSingle();
    final nextYear = nextYearMap == null
        ? null
        : AcademicYear.fromMap(nextYearMap);

    final membershipRows = await _client
        .from('class_students')
        .select('class_id, school_classes!inner(*)')
        .eq('student_id', profile.id)
        .eq('is_active', true);
    SchoolClass? currentClass;
    for (final row in membershipRows) {
      final schoolClass = SchoolClass.fromMap(
        Map<String, dynamic>.from(row['school_classes'] as Map),
      );
      if (schoolClass.academicYearId == currentYear.id) {
        currentClass = schoolClass;
        break;
      }
    }

    final destinationClasses = nextYear == null
        ? <SchoolClass>[]
        : await _loadCompatibleClasses(nextYear.id, profile);

    final requestMap = await _client
        .from('student_promotions')
        .select()
        .eq('student_id', profile.id)
        .inFilter('status', ['pending', 'approved'])
        .order('requested_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return PromotionContext(
      currentYear: currentYear,
      nextYear: nextYear,
      currentClass: currentClass,
      destinationClasses: destinationClasses,
      request: requestMap == null ? null : StudentPromotion.fromMap(requestMap),
    );
  }

  Future<List<SchoolClass>> _loadCompatibleClasses(
    String academicYearId,
    UserProfile profile,
  ) async {
    final rows = await _client
        .from('school_classes')
        .select()
        .eq('academic_year_id', academicYearId)
        .eq('is_active', true)
        .order('display_name');
    return rows
        .map((row) => SchoolClass.fromMap(Map<String, dynamic>.from(row)))
        .where((schoolClass) => _isCompatible(schoolClass, profile))
        .toList(growable: false);
  }

  bool _isCompatible(SchoolClass schoolClass, UserProfile profile) {
    if (schoolClass.subsystem.name != profile.subsystem ||
        schoolClass.sector.name != profile.sector) {
      return false;
    }
    if (schoolClass.seriesId != null &&
        schoolClass.seriesId != profile.seriesId) {
      return false;
    }
    if (schoolClass.specialtyId != null &&
        schoolClass.specialtyId != profile.specialtyId) {
      return false;
    }
    return true;
  }

  Future<StudentPromotion> requestPromotion({
    required UserProfile profile,
    required PromotionContext context,
    required SchoolClass destinationClass,
  }) async {
    final currentClass = context.currentClass;
    final nextYear = context.nextYear;
    if (currentClass == null || nextYear == null) {
      throw const PostgrestException(
        message: 'No valid promotion path is available.',
      );
    }

    final row = await _client
        .from('student_promotions')
        .insert({
          'student_id': profile.id,
          'source_class_id': currentClass.id,
          'destination_class_id': destinationClass.id,
          'source_academic_year_id': context.currentYear.id,
          'destination_academic_year_id': nextYear.id,
          'status': 'pending',
        })
        .select()
        .single();
    return StudentPromotion.fromMap(row);
  }

  Future<void> cancelPromotion(String promotionId) async {
    await _client
        .from('student_promotions')
        .update({'status': 'cancelled'})
        .eq('id', promotionId)
        .eq('status', 'pending');
  }

  Future<List<PromotionReviewItem>> getPendingPromotions() async {
    final rows = await _client
        .from('student_promotions')
        .select(
          '*, profiles!student_id(first_name,last_name), '
          'source_class:school_classes!source_class_id(display_name), '
          'destination_class:school_classes!destination_class_id(display_name)',
        )
        .eq('status', 'pending')
        .order('requested_at');
    return rows
        .map(
          (row) => PromotionReviewItem.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> reviewPromotion({
    required String promotionId,
    required StudentPromotionStatus status,
  }) async {
    if (status != StudentPromotionStatus.approved &&
        status != StudentPromotionStatus.rejected) {
      throw ArgumentError('An administrator can only approve or reject.');
    }
    await _client
        .from('student_promotions')
        .update({'status': status.name})
        .eq('id', promotionId)
        .eq('status', 'pending');
  }
}
