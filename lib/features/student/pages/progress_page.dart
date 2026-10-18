import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/smart_course_service.dart';
import '../../../models/smart_learning.dart';
import '../../../models/user_profile.dart';

class ProgressPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;

  const ProgressPage({super.key, required this.locale, required this.profile});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final SupabaseClient _client = Supabase.instance.client;
  final SmartCourseService _smart = SmartCourseService();

  bool _loading = true;
  String? _error;

  int _totalLessons = 0;
  int _completedLessons = 0;
  int _inProgressLessons = 0;

  double _overallProgress = 0;

  List<_CourseProgressData> _courses = const [];
  ClassProgressSummary? _classSummary;
  List<Map<String, dynamic>> _weekly = const [];

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final memberships = await _client
          .from('class_students')
          .select('class_id')
          .eq('student_id', widget.profile.id)
          .eq('is_active', true);

      final classIds = memberships
          .map((row) => row['class_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();

      if (classIds.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _totalLessons = 0;
          _completedLessons = 0;
          _inProgressLessons = 0;
          _overallProgress = 0;
          _courses = const [];
          _loading = false;
        });

        return;
      }

      unawaited(_loadSmartComparison(classIds.first));

      final courseRows = await _client
          .from('courses')
          .select()
          .eq('status', 'published')
          .inFilter('class_id', classIds)
          .order('updated_at', ascending: false);

      final List<_CourseProgressData> courseResults = [];

      int totalLessons = 0;
      int completedLessons = 0;
      int inProgressLessons = 0;
      double progressSum = 0;
      int progressCount = 0;

      for (final rawCourse in courseRows) {
        final course = Map<String, dynamic>.from(rawCourse);
        final courseId = course['id']?.toString();

        if (courseId == null || courseId.isEmpty) {
          continue;
        }

        final lessonsRows = await _client
            .from('lessons')
            .select()
            .eq('course_id', courseId)
            .eq('is_published', true)
            .order('position');

        final lessonIds = lessonsRows
            .map((row) => row['id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();

        if (lessonIds.isEmpty) {
          continue;
        }

        final progressRows = await _client
            .from('lesson_progress')
            .select()
            .eq('student_id', widget.profile.id)
            .inFilter('lesson_id', lessonIds);

        final progressByLesson = <String, Map<String, dynamic>>{};

        for (final rawProgress in progressRows) {
          final progress = Map<String, dynamic>.from(rawProgress);
          final lessonId = progress['lesson_id']?.toString();

          if (lessonId != null && lessonId.isNotEmpty) {
            progressByLesson[lessonId] = progress;
          }
        }

        int courseCompleted = 0;
        int courseInProgress = 0;
        double courseProgressSum = 0;

        for (final rawLesson in lessonsRows) {
          final lesson = Map<String, dynamic>.from(rawLesson);
          final lessonId = lesson['id']?.toString();

          if (lessonId == null || lessonId.isEmpty) {
            continue;
          }

          final progress = progressByLesson[lessonId];

          final percent = _readProgressPercent(progress);

          courseProgressSum += percent;

          totalLessons++;
          progressSum += percent;
          progressCount++;

          if (percent >= 100) {
            courseCompleted++;
            completedLessons++;
          } else if (percent > 0) {
            courseInProgress++;
            inProgressLessons++;
          }
        }

        final courseProgress = lessonIds.isEmpty
            ? 0.0
            : courseProgressSum / lessonIds.length;

        courseResults.add(
          _CourseProgressData(
            id: courseId,
            titleFr: _readString(course['title_fr']),
            titleEn: _readString(course['title_en']),
            lessonCount: lessonIds.length,
            completedLessons: courseCompleted,
            inProgressLessons: courseInProgress,
            progressPercent: courseProgress,
          ),
        );
      }

      final overallProgress = progressCount == 0
          ? 0.0
          : progressSum / progressCount;

      if (!mounted) {
        return;
      }

      setState(() {
        _totalLessons = totalLessons;
        _completedLessons = completedLessons;
        _inProgressLessons = inProgressLessons;
        _overallProgress = overallProgress;
        _courses = courseResults;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = _isFrench
            ? 'Impossible de charger votre progression.'
            : 'Unable to load your progress.';
      });
    }
  }

  Future<void> _loadSmartComparison(String classId) async {
    try {
      final summary = await _smart.getClassProgressSummary(classId);
      final weekly = await _smart.getWeeklyProgress(classId);
      if (!mounted) {
        return;
      }
      setState(() {
        _classSummary = summary;
        _weekly = weekly;
      });
    } catch (_) {
      // Existing progress remains available if the comparison RPC is not ready.
    }
  }

  double _readProgressPercent(Map<String, dynamic>? progress) {
    if (progress == null) {
      return 0;
    }

    final rawValue = progress['progress_percent'];

    if (rawValue is num) {
      return rawValue.toDouble().clamp(0, 100);
    }

    if (rawValue is String) {
      return (double.tryParse(rawValue) ?? 0).clamp(0, 100);
    }

    return 0;
  }

  String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _courseTitle(_CourseProgressData course) {
    if (_isFrench) {
      if (course.titleFr.isNotEmpty) {
        return course.titleFr;
      }

      if (course.titleEn.isNotEmpty) {
        return course.titleEn;
      }

      return 'Cours';
    }

    if (course.titleEn.isNotEmpty) {
      return course.titleEn;
    }

    if (course.titleFr.isNotEmpty) {
      return course.titleFr;
    }

    return 'Course';
  }

  String _formatPercent(double value) {
    final rounded = value.round();
    return '$rounded%';
  }

  String _progressDescription(_CourseProgressData course) {
    if (_isFrench) {
      return '${course.completedLessons}/${course.lessonCount} leçons terminées';
    }

    return '${course.completedLessons}/${course.lessonCount} lessons completed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isFrench ? 'Ma progression' : 'My progress',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProgress,
          child: _loading
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 220),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 70),
                    const Icon(Icons.error_outline_rounded, size: 60),
                    const SizedBox(height: 18),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _loadProgress,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(_isFrench ? 'Réessayer' : 'Try again'),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildOverallCard(theme),
                    const SizedBox(height: 16),
                    _buildStats(),
                    if (_classSummary != null || _weekly.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildSmartProgressSection(),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      _isFrench
                          ? 'Progression par cours'
                          : 'Progress by course',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_courses.isEmpty)
                      _buildEmptyCourses()
                    else
                      ..._courses.map(_buildCourseCard),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSmartProgressSection() {
    final summary = _classSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isFrench ? 'Votre évolution' : 'Your progress over time', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              height: 150,
              child: _weekly.isEmpty
                  ? Center(child: Text(_isFrench ? 'Pas encore assez de données.' : 'Not enough data yet.'))
                  : CustomPaint(painter: _WeeklyProgressPainter(_weekly)),
            ),
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: summary.comparisonAvailable
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_isFrench ? 'Position dans la salle' : 'Position in your class', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_frTop(summary.topPercent)),
                      const SizedBox(height: 8),
                      Text(_isFrench
                          ? 'Votre moyenne : ${summary.ownAverageScore.toStringAsFixed(1)} % • moyenne de la salle : ${summary.classAverageScore.toStringAsFixed(1)} %'
                          : 'Your average: ${summary.ownAverageScore.toStringAsFixed(1)}% • class average: ${summary.classAverageScore.toStringAsFixed(1)}%'),
                      const SizedBox(height: 10),
                      ...summary.subjects.map((subject) {
                        final own = (subject['own_score'] as num?)?.toDouble() ?? 0;
                        final average = (subject['class_average'] as num?)?.toDouble() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('${subject['subject_name'] ?? ''}: ${own.toStringAsFixed(0)} % / ${average.toStringAsFixed(0)} %'),
                        );
                      }),
                    ])
                  : Text(_isFrench
                      ? 'La comparaison est masquée pour les salles de moins de 5 élèves actifs.'
                      : 'Comparison is hidden for classes with fewer than 5 active students.'),
            ),
          ),
        ],
      ],
    );
  }

  String _frTop(int? topPercent) {
    if (topPercent == null) {
      return _isFrench ? 'Continuez à progresser à votre rythme.' : 'Keep progressing at your own pace.';
    }
    if (topPercent > 50) {
      return _isFrench
          ? 'Votre progression continue : utilisez les leçons et exercices pour avancer.'
          : 'Your progress can keep growing: use the lessons and exercises to move forward.';
    }
    if (_isFrench) {
      return 'Vous êtes dans les $topPercent % meilleurs élèves de la salle.';
    }
    return 'You are in the top $topPercent% of students in the class.';
  }

  Widget _buildOverallCard(ThemeData theme) {
    final progress = (_overallProgress / 100).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF166534),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isFrench ? 'Votre progression générale' : 'Your overall progress',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatPercent(_overallProgress),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isFrench
                ? 'Progression calculée à partir des leçons suivies.'
                : 'Progress calculated from the lessons you study.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.menu_book_rounded,
            value: _totalLessons.toString(),
            label: _isFrench ? 'Leçons' : 'Lessons',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_rounded,
            value: _completedLessons.toString(),
            label: _isFrench ? 'Terminées' : 'Completed',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.play_circle_fill_rounded,
            value: _inProgressLessons.toString(),
            label: _isFrench ? 'En cours' : 'In progress',
          ),
        ),
      ],
    );
  }

  Widget _buildCourseCard(_CourseProgressData course) {
    final progress = (course.progressPercent / 100).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFF166534),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _courseTitle(course),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatPercent(course.progressPercent),
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF166534),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _progressDescription(course),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                if (course.inProgressLessons > 0)
                  Text(
                    _isFrench
                        ? '${course.inProgressLessons} en cours'
                        : '${course.inProgressLessons} in progress',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCourses() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(
              Icons.insights_outlined,
              size: 64,
              color: Color(0xFF166534),
            ),
            const SizedBox(height: 14),
            Text(
              _isFrench
                  ? 'Aucune progression disponible pour le moment.'
                  : 'No progress is available yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _isFrench
                  ? 'Votre progression apparaîtra lorsque des cours et des leçons seront disponibles pour votre classe.'
                  : 'Your progress will appear when courses and lessons are available for your class.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseProgressData {
  final String id;
  final String titleFr;
  final String titleEn;
  final int lessonCount;
  final int completedLessons;
  final int inProgressLessons;
  final double progressPercent;

  const _CourseProgressData({
    required this.id,
    required this.titleFr,
    required this.titleEn,
    required this.lessonCount,
    required this.completedLessons,
    required this.inProgressLessons,
    required this.progressPercent,
  });
}

class _WeeklyProgressPainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  const _WeeklyProgressPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final line = Paint()..strokeWidth = 3..style = PaintingStyle.stroke;
    final dot = Paint()..style = PaintingStyle.fill;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final score = ((points[i]['average_score'] as num?)?.toDouble() ?? 0).clamp(0, 100);
      final x = points.length == 1 ? size.width / 2 : i * size.width / (points.length - 1);
      final y = size.height - (score / 100) * (size.height - 10);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, dot);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _WeeklyProgressPainter oldDelegate) => oldDelegate.points != points;
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
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
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
