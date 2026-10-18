import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class CachedCourses extends Table {
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get description => text().nullable()();

  TextColumn get subjectId => text().nullable()();

  TextColumn get classId => text().nullable()();

  TextColumn get dataJson => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedLessons extends Table {
  TextColumn get id => text()();

  TextColumn get courseId => text()();

  TextColumn get title => text()();

  TextColumn get content => text()();

  IntColumn get durationMinutes => integer().nullable()();

  TextColumn get dataJson => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalProgress extends Table {
  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get courseId => text().nullable()();

  TextColumn get lessonId => text().nullable()();

  IntColumn get progressPercent => integer()();

  BoolColumn get completed => boolean()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class DownloadedFiles extends Table {
  TextColumn get resourceId => text()();
  TextColumn get courseId => text()();
  TextColumn get userId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get localPath => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get remoteUpdatedAt => text().nullable()();
  TextColumn get downloadedAt => text().nullable()();
  TextColumn get lastOpenedAt => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('queued'))();

  @override
  Set<Column> get primaryKey => {resourceId};
}

@DriftDatabase(tables: [CachedCourses, CachedLessons, LocalProgress, DownloadedFiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createDownloadedFilesTable();
          await _createOfflineQcmTables();
          await _createSmartLearningTables();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _createDownloadedFilesTable();
            await _createOfflineQcmTables();
          }
          if (from < 3) {
            await _createSmartLearningTables();
          }
        },
      );

  Future<void> _createDownloadedFilesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS downloaded_files (
        resource_id TEXT PRIMARY KEY NOT NULL,
        course_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT,
        local_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        remote_updated_at TEXT,
        downloaded_at TEXT,
        last_opened_at TEXT,
        status TEXT NOT NULL DEFAULT 'queued'
          CHECK (status IN ('queued','downloading','done','failed'))
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS downloaded_files_course_idx ON downloaded_files(course_id, user_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS downloaded_files_status_idx ON downloaded_files(user_id, status)',
    );
  }

  Future<List<DownloadedFileRecord>> getDownloadedFiles({String? userId, String? courseId}) async {
    final where = <String>[];
    final variables = <Variable<Object>>[];
    if (userId != null) { where.add('user_id = ?'); variables.add(Variable(userId)); }
    if (courseId != null) { where.add('course_id = ?'); variables.add(Variable(courseId)); }
    final rows = await customSelect(
      'SELECT * FROM downloaded_files${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY COALESCE(last_opened_at, downloaded_at) ASC',
      variables: variables,
    ).get();
    return rows.map(DownloadedFileRecord.fromRow).toList(growable: false);
  }

  Future<DownloadedFileRecord?> getDownloadedFile(String resourceId, String userId) async {
    final rows = await customSelect(
      'SELECT * FROM downloaded_files WHERE resource_id = ? AND user_id = ? LIMIT 1',
      variables: [Variable(resourceId), Variable(userId)],
    ).get();
    return rows.isEmpty ? null : DownloadedFileRecord.fromRow(rows.first);
  }

  Future<void> upsertDownloadedFile(DownloadedFileRecord file) async {
    await customStatement(
      '''INSERT INTO downloaded_files(resource_id,course_id,user_id,file_name,mime_type,local_path,size_bytes,remote_updated_at,downloaded_at,last_opened_at,status)
      VALUES(?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(resource_id) DO UPDATE SET course_id=excluded.course_id,user_id=excluded.user_id,file_name=excluded.file_name,mime_type=excluded.mime_type,local_path=excluded.local_path,size_bytes=excluded.size_bytes,remote_updated_at=excluded.remote_updated_at,downloaded_at=excluded.downloaded_at,last_opened_at=excluded.last_opened_at,status=excluded.status''',
      [file.resourceId, file.courseId, file.userId, file.fileName, file.mimeType ?? '', file.localPath, file.sizeBytes, file.remoteUpdatedAt?.toIso8601String() ?? '', file.downloadedAt?.toIso8601String() ?? '', file.lastOpenedAt?.toIso8601String() ?? '', file.status],
    );
  }

  Future<void> updateDownloadedFileStatus(String resourceId, String userId, String status) async {
    await customStatement('UPDATE downloaded_files SET status = ? WHERE resource_id = ? AND user_id = ?',  [status, resourceId, userId]);
  }

  Future<void> markDownloadedFileOpened(String resourceId, String userId) async {
    await customStatement("UPDATE downloaded_files SET last_opened_at = ?, status = 'done' WHERE resource_id = ? AND user_id = ?",  [DateTime.now().toIso8601String(), resourceId, userId]);
  }

  Future<void> deleteDownloadedFile(String resourceId, String userId) async {
    await customStatement('DELETE FROM downloaded_files WHERE resource_id = ? AND user_id = ?',  [resourceId, userId]);
  }

  Future<void> deleteAllDownloadedFiles(String userId) async {
    await customStatement('DELETE FROM downloaded_files WHERE user_id = ?',  [userId]);
  }

  Future<int> downloadedFilesSize(String userId) async {
    final rows = await customSelect("SELECT COALESCE(SUM(size_bytes),0) AS total FROM downloaded_files WHERE user_id = ? AND status = 'done'", variables: [Variable(userId)]).get();
    return rows.first.read<int>('total');
  }

  Future<void> _createSmartLearningTables() async {
    await customStatement("""
      CREATE TABLE IF NOT EXISTS smart_lessons_cache (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    """);
    await customStatement("""
      CREATE TABLE IF NOT EXISTS smart_exercise_queue (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        lesson_id TEXT NOT NULL,
        answers_json TEXT NOT NULL,
        queued_at TEXT NOT NULL
      )
    """);
    await customStatement("""
      CREATE TABLE IF NOT EXISTS smart_exercise_results (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        lesson_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        saved_at TEXT NOT NULL
      )
    """);
    await customStatement(
      'CREATE INDEX IF NOT EXISTS smart_lessons_user_idx ON smart_lessons_cache(user_id, cached_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS smart_queue_user_idx ON smart_exercise_queue(user_id, queued_at)',
    );
  }

  Future<void> _createOfflineQcmTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_qcm (
        id TEXT NOT NULL, user_id TEXT NOT NULL, kind TEXT NOT NULL,
        assignment_id TEXT, data_json TEXT NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY (id, user_id, kind)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_qcm_queue (
        id TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL,
        submission_id TEXT NOT NULL, assignment_id TEXT NOT NULL,
        data_json TEXT NOT NULL, queued_at TEXT NOT NULL
      )
    ''');
    await customStatement('CREATE INDEX IF NOT EXISTS offline_qcm_user_idx ON offline_qcm(user_id, kind, assignment_id)');
    await customStatement('CREATE INDEX IF NOT EXISTS offline_qcm_queue_user_idx ON offline_qcm_queue(user_id, queued_at)');
  }

  Future<void> saveOfflineQcm({required String id, required String userId, required String kind, String? assignmentId, required String dataJson}) async {
    await customStatement(
      "INSERT INTO offline_qcm(id,user_id,kind,assignment_id,data_json,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(id,user_id,kind) DO UPDATE SET assignment_id=excluded.assignment_id,data_json=excluded.data_json,updated_at=excluded.updated_at",
       [id, userId, kind, assignmentId, dataJson, DateTime.now().toIso8601String()],
    );
  }

  Future<List<QueryRow>> getOfflineQcm(String userId, String kind, {String? assignmentId}) async {
    final filter = assignmentId == null ? '' : ' AND assignment_id = ?';
    final variables = <Variable<Object>>[Variable(userId), Variable(kind)];
    if (assignmentId != null) {
      variables.add(Variable(assignmentId));
    }
    return customSelect('SELECT * FROM offline_qcm WHERE user_id = ? AND kind = ?$filter ORDER BY updated_at', variables: variables).get();
  }

  Future<void> saveOfflineQcmQueue({required String id, required String userId, required String submissionId, required String assignmentId, required String dataJson}) async {
    await customStatement(
      "INSERT OR REPLACE INTO offline_qcm_queue(id,user_id,submission_id,assignment_id,data_json,queued_at) VALUES(?,?,?,?,?,?)",
       [id, userId, submissionId, assignmentId, dataJson, DateTime.now().toIso8601String()],
    );
  }

  Future<List<QueryRow>> getOfflineQcmQueue(String userId) => customSelect('SELECT * FROM offline_qcm_queue WHERE user_id = ? ORDER BY queued_at', variables: [Variable(userId)]).get();

  Future<void> deleteOfflineQcmQueue(String id, String userId) => customStatement('DELETE FROM offline_qcm_queue WHERE id = ? AND user_id = ?',  [id, userId]);

  Future<void> saveSmartLesson({required String userId, required String id, required String dataJson}) async {
    await customStatement(
      'INSERT INTO smart_lessons_cache(id,user_id,data_json,cached_at) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id,data_json=excluded.data_json,cached_at=excluded.cached_at',
       [id, userId, dataJson, DateTime.now().toIso8601String()],
    );
  }

  Future<QueryRow?> getSmartLesson(String userId, String id) async {
    final rows = await customSelect(
      'SELECT * FROM smart_lessons_cache WHERE user_id = ? AND id = ? LIMIT 1',
      variables: [Variable(userId), Variable(id)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<QueryRow?> latestSmartLesson(String userId) async {
    final rows = await customSelect(
      'SELECT * FROM smart_lessons_cache WHERE user_id = ? ORDER BY cached_at DESC LIMIT 1',
      variables: [Variable(userId)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<QueryRow>> getSmartLessons(String userId) => customSelect(
    'SELECT * FROM smart_lessons_cache WHERE user_id = ? ORDER BY cached_at DESC',
    variables: [Variable(userId)],
  ).get();

  Future<void> queueSmartExercise({required String id, required String userId, required String lessonId, required String answersJson}) async {
    await customStatement(
      'INSERT OR REPLACE INTO smart_exercise_queue(id,user_id,lesson_id,answers_json,queued_at) VALUES(?,?,?,?,?)',
       [id, userId, lessonId, answersJson, DateTime.now().toIso8601String()],
    );
  }

  Future<List<QueryRow>> getSmartExerciseQueue(String userId) => customSelect(
    'SELECT * FROM smart_exercise_queue WHERE user_id = ? ORDER BY queued_at',
    variables: [Variable(userId)],
  ).get();

  Future<void> deleteSmartExerciseQueue(String id, String userId) => customStatement(
    'DELETE FROM smart_exercise_queue WHERE id = ? AND user_id = ?',
     [id, userId],
  );

  Future<void> saveSmartExerciseResult({required String id, required String userId, required String lessonId, required String dataJson}) async {
    await customStatement(
      'INSERT OR REPLACE INTO smart_exercise_results(id,user_id,lesson_id,data_json,saved_at) VALUES(?,?,?,?,?)',
       [id, userId, lessonId, dataJson, DateTime.now().toIso8601String()],
    );
  }

  Future<QueryRow?> getSmartExerciseResult(String userId, String lessonId) async {
    final rows = await customSelect(
      'SELECT * FROM smart_exercise_results WHERE user_id = ? AND lesson_id = ? ORDER BY saved_at DESC LIMIT 1',
      variables: [Variable(userId), Variable(lessonId)],
    ).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<CachedCourse>> getAllCourses() {
    return select(cachedCourses).get();
  }

  Future<List<CachedLesson>> getAllLessons() {
    return select(cachedLessons).get();
  }

  Future<List<LocalProgressData>> getAllProgress() {
    return select(localProgress).get();
  }

  Future<void> saveCourse(CachedCoursesCompanion course) async {
    await into(cachedCourses).insertOnConflictUpdate(course);
  }

  Future<void> saveLesson(CachedLessonsCompanion lesson) async {
    await into(cachedLessons).insertOnConflictUpdate(lesson);
  }

  Future<void> saveProgress(LocalProgressCompanion progress) async {
    await into(localProgress).insertOnConflictUpdate(progress);
  }

  Future<void> deleteAllCourses() async {
    await delete(cachedCourses).go();
  }

  Future<void> deleteAllLessons() async {
    await delete(cachedLessons).go();
  }

  Future<void> deleteAllProgress() async {
    await delete(localProgress).go();
  }

  Future<void> closeDatabase() async {
    await close();
  }
}

class DownloadedFileRecord {
  final String resourceId, courseId, userId, fileName, localPath, status;
  final String? mimeType;
  final int sizeBytes;
  final DateTime? remoteUpdatedAt, downloadedAt, lastOpenedAt;

  const DownloadedFileRecord({
    required this.resourceId, required this.courseId, required this.userId,
    required this.fileName, required this.localPath, required this.status,
    required this.sizeBytes, this.mimeType, this.remoteUpdatedAt,
    this.downloadedAt, this.lastOpenedAt,
  });

  factory DownloadedFileRecord.fromRow(QueryRow row) => DownloadedFileRecord(
    resourceId: row.read<String>('resource_id'),
    courseId: row.read<String>('course_id'),
    userId: row.read<String>('user_id'),
    fileName: row.read<String>('file_name'),
    mimeType: row.readNullable<String>('mime_type'),
    localPath: row.read<String>('local_path'),
    sizeBytes: row.read<int>('size_bytes'),
    remoteUpdatedAt: DateTime.tryParse(row.readNullable<String>('remote_updated_at') ?? ''),
    downloadedAt: DateTime.tryParse(row.readNullable<String>('downloaded_at') ?? ''),
    lastOpenedAt: DateTime.tryParse(row.readNullable<String>('last_opened_at') ?? ''),
    status: row.read<String>('status'),
  );

  DownloadedFileRecord copyWith({String? localPath, int? sizeBytes, DateTime? remoteUpdatedAt, DateTime? downloadedAt, DateTime? lastOpenedAt, String? status}) => DownloadedFileRecord(
    resourceId: resourceId, courseId: courseId, userId: userId, fileName: fileName,
    mimeType: mimeType, localPath: localPath ?? this.localPath, sizeBytes: sizeBytes ?? this.sizeBytes,
    remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt, downloadedAt: downloadedAt ?? this.downloadedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt, status: status ?? this.status,
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();

    final file = File(p.join(directory.path, 'fise_school.sqlite'));

    return NativeDatabase.createInBackground(file);
  });
}
