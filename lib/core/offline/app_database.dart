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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createDownloadedFilesTable();
          await _createOfflineQcmTables();
          await _createSmartLearningTables();
          await _createMessageOfflineTables();
          await _createOfflineCatalogCacheTable();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _createDownloadedFilesTable();
            await _createOfflineQcmTables();
          }
          if (from < 3) {
            await _createSmartLearningTables();
          }
          if (from < 4) {
            await _createMessageOfflineTables();
          }
          if (from < 5) {
            await _createOfflineCatalogCacheTable();
          }
          if (from < 6) {
            await _addMessageReplyColumns();
          }
        },
      );

  Future<void> _createOfflineCatalogCacheTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_catalog_cache (
        user_id TEXT NOT NULL,
        cache_key TEXT NOT NULL,
        data_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(user_id, cache_key)
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS offline_catalog_cache_updated_idx ON offline_catalog_cache(user_id, updated_at)',
    );
  }

  Future<String?> getOfflineCatalogCache(String userId, String cacheKey) async {
    final rows = await customSelect(
      'SELECT data_json FROM offline_catalog_cache WHERE user_id = ? AND cache_key = ? LIMIT 1',
      variables: [Variable(userId), Variable(cacheKey)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('data_json');
  }

  Future<void> saveOfflineCatalogCache(
    String userId,
    String cacheKey,
    String dataJson,
  ) async {
    await customStatement(
      '''INSERT INTO offline_catalog_cache(user_id, cache_key, data_json, updated_at)
      VALUES(?,?,?,?)
      ON CONFLICT(user_id, cache_key) DO UPDATE SET
        data_json=excluded.data_json, updated_at=excluded.updated_at''',
      [userId, cacheKey, dataJson, DateTime.now().toUtc().toIso8601String()],
    );
  }

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


  Future<void> _addMessageReplyColumns() async {
    for (final table in const ['message_cache', 'message_outbox']) {
      try {
        await customStatement('ALTER TABLE $table ADD COLUMN reply_to_id TEXT');
      } catch (_) {
        // La colonne existe déjà (table créée avec la nouvelle version).
      }
    }
  }

  Future<void> _createMessageOfflineTables() async {
    await customStatement("""
      CREATE TABLE IF NOT EXISTS message_cache (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('private','group')),
        thread_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_name TEXT NOT NULL DEFAULT '',
        sender_role TEXT NOT NULL DEFAULT '',
        recipient_id TEXT,
        body TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        read_at TEXT,
        attachment_path TEXT,
        attachment_name TEXT,
        attachment_type TEXT,
        local_attachment_path TEXT,
        reply_to_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'sent'
      )
    """);
    await customStatement("""
      CREATE INDEX IF NOT EXISTS message_cache_thread_idx
      ON message_cache(user_id, kind, thread_id, created_at)
    """);
    await customStatement("""
      CREATE TABLE IF NOT EXISTS message_outbox (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('private','group')),
        thread_id TEXT NOT NULL,
        recipient_id TEXT,
        body TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        attachment_local_path TEXT,
        attachment_name TEXT,
        attachment_type TEXT,
        reply_to_id TEXT,
        attempts INTEGER NOT NULL DEFAULT 0
      )
    """);
    await customStatement("""
      CREATE INDEX IF NOT EXISTS message_outbox_user_idx
      ON message_outbox(user_id, kind, created_at)
    """);
    await customStatement("""
      CREATE TABLE IF NOT EXISTS message_contacts_cache (
        user_id TEXT NOT NULL,
        contact_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        PRIMARY KEY(user_id, contact_id)
      )
    """);
    await customStatement("""
      CREATE TABLE IF NOT EXISTS message_groups_cache (
        user_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        PRIMARY KEY(user_id, group_id)
      )
    """);
  }

  Future<void> cacheMessage(Map<String, Object?> message) async {
    await customStatement(
      '''INSERT INTO message_cache(id,user_id,kind,thread_id,sender_id,sender_name,sender_role,recipient_id,body,created_at,read_at,attachment_path,attachment_name,attachment_type,local_attachment_path,reply_to_id,sync_status)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        sender_name=CASE WHEN excluded.sender_name<>'' THEN excluded.sender_name ELSE message_cache.sender_name END,
        sender_role=CASE WHEN excluded.sender_role<>'' THEN excluded.sender_role ELSE message_cache.sender_role END,
        body=excluded.body, read_at=COALESCE(excluded.read_at,message_cache.read_at),
        attachment_path=COALESCE(excluded.attachment_path,message_cache.attachment_path),
        attachment_name=COALESCE(excluded.attachment_name,message_cache.attachment_name),
        attachment_type=COALESCE(excluded.attachment_type,message_cache.attachment_type),
        local_attachment_path=COALESCE(excluded.local_attachment_path,message_cache.local_attachment_path),
        reply_to_id=COALESCE(excluded.reply_to_id,message_cache.reply_to_id),
        sync_status=CASE WHEN message_cache.sync_status='pending' AND excluded.sync_status='sent' THEN 'sent' ELSE excluded.sync_status END''',
      [message['id'], message['user_id'], message['kind'], message['thread_id'], message['sender_id'], message['sender_name'] ?? '', message['sender_role'] ?? '', message['recipient_id'], message['body'] ?? '', message['created_at'], message['read_at'], message['attachment_path'], message['attachment_name'], message['attachment_type'], message['local_attachment_path'], message['reply_to_id'], message['sync_status'] ?? 'sent'],
    );
  }


  Future<void> beginMessageCacheRefresh(String userId, String kind, String threadId) =>
      customStatement(
        "DELETE FROM message_cache WHERE user_id=? AND kind=? AND thread_id=? AND sync_status<>'pending'",
        [userId, kind, threadId],
      );

  Future<List<QueryRow>> getCachedMessages(String userId, String kind, String threadId) =>
      customSelect(
        'SELECT * FROM message_cache WHERE user_id=? AND kind=? AND thread_id=? ORDER BY created_at ASC',
        variables: [Variable(userId), Variable(kind), Variable(threadId)],
      ).get();

  Future<void> queueMessage(Map<String, Object?> message) async {
    await transaction(() async {
      await cacheMessage({...message, 'sync_status': 'pending'});
      await customStatement(
        '''INSERT OR REPLACE INTO message_outbox(id,user_id,kind,thread_id,recipient_id,body,created_at,attachment_local_path,attachment_name,attachment_type,reply_to_id,attempts)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,COALESCE((SELECT attempts FROM message_outbox WHERE id=?),0))''',
        [message['id'], message['user_id'], message['kind'], message['thread_id'], message['recipient_id'], message['body'] ?? '', message['created_at'], message['attachment_local_path'], message['attachment_name'], message['attachment_type'], message['reply_to_id'], message['id']],
      );
    });
  }

  Future<List<QueryRow>> getQueuedMessages(String userId, String kind) => customSelect(
    'SELECT * FROM message_outbox WHERE user_id=? AND kind=? ORDER BY created_at ASC',
    variables: [Variable(userId), Variable(kind)],
  ).get();

  Future<void> markMessageSent(String id, {String? attachmentPath}) async {
    await transaction(() async {
      await customStatement(
        "UPDATE message_cache SET sync_status='sent', attachment_path=COALESCE(?,attachment_path) WHERE id=?",
        [attachmentPath, id],
      );
      await customStatement('DELETE FROM message_outbox WHERE id=?', [id]);
    });
  }

  /// Message refusé définitivement par le serveur (quota ou Premium requis) : on le retire
  /// de la file d'envoi et du cache local pour ne pas le rejouer indéfiniment.
  Future<void> discardRejectedMessage(String id) async {
    await transaction(() async {
      await customStatement('DELETE FROM message_outbox WHERE id=?', [id]);
      await customStatement("DELETE FROM message_cache WHERE id=? AND sync_status='pending'", [id]);
    });
  }

  Future<void> incrementMessageAttempts(String id) =>
      customStatement('UPDATE message_outbox SET attempts=attempts+1 WHERE id=?', [id]);

  /// Déconnexion : efface les copies locales lisibles (messages, contacts, groupes, catalogue,
  /// leçons intelligentes, QCM). Les envois non terminés (files d'attente) sont conservés
  /// pour être envoyés à la prochaine connexion du même compte.
  Future<void> clearUserReadCaches(String userId) async {
    // customStatement binds raw Dart values; Variable wrappers are only for customSelect.
    final values = [userId];
    await customStatement("DELETE FROM message_cache WHERE user_id=? AND sync_status<>'pending'", values);
    await customStatement('DELETE FROM message_contacts_cache WHERE user_id=?', values);
    await customStatement('DELETE FROM message_groups_cache WHERE user_id=?', values);
    await customStatement('DELETE FROM offline_catalog_cache WHERE user_id=?', values);
    await customStatement('DELETE FROM smart_lessons_cache WHERE user_id=?', values);
    await customStatement('DELETE FROM smart_exercise_results WHERE user_id=?', values);
    await customStatement('DELETE FROM offline_qcm WHERE user_id=?', values);
  }

  Future<void> cacheMessageContact(String userId, String contactId, String dataJson) =>
      customStatement('INSERT OR REPLACE INTO message_contacts_cache(user_id,contact_id,data_json) VALUES(?,?,?)', [userId, contactId, dataJson]);

  Future<List<QueryRow>> getCachedMessageContacts(String userId) => customSelect(
    'SELECT data_json FROM message_contacts_cache WHERE user_id=? ORDER BY contact_id',
    variables: [Variable(userId)],
  ).get();

  Future<void> cacheMessageGroup(String userId, String groupId, String dataJson) =>
      customStatement('INSERT OR REPLACE INTO message_groups_cache(user_id,group_id,data_json) VALUES(?,?,?)', [userId, groupId, dataJson]);

  Future<List<QueryRow>> getCachedMessageGroups(String userId) => customSelect(
    'SELECT data_json FROM message_groups_cache WHERE user_id=? ORDER BY group_id',
    variables: [Variable(userId)],
  ).get();

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
