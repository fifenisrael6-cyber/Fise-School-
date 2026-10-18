import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/pedagogy.dart';
import '../services/assignment_service.dart';
import '../services/pedagogy_service.dart';
import 'offline_repository.dart';
import 'app_database.dart';
import 'connectivity_service.dart';
import 'offline_settings.dart';

class OfflineDownloadProgress {
  final String resourceId;
  final int received;
  final int total;
  final String status;

  const OfflineDownloadProgress({required this.resourceId, required this.received, required this.total, required this.status});

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble();
}

class CourseOfflineService {
  factory CourseOfflineService({SupabaseClient? client, AppDatabase? database}) {
    if (client == null && database == null) {
      return shared;
    }
    return CourseOfflineService._internal(client: client, database: database);
  }

  static final CourseOfflineService shared = CourseOfflineService._internal();

  CourseOfflineService._internal({SupabaseClient? client, AppDatabase? database})
      : _client = client ?? Supabase.instance.client,
        _db = database ?? AppDatabase() {
    _connectionSubscription = _connectivity.connectionStream.listen((online) {
      if (online) {
        unawaited(_resumeQueuedDownloads());
      }
    });
  }

  final SupabaseClient _client;
  final AppDatabase _db;
  final ResourceService _resources = ResourceService();
  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineSettings _settings = OfflineSettings();
  StreamSubscription<bool>? _connectionSubscription;

  static const int _maxParallel = 2;
  static const int _maxVideoBytes = 25 * 1024 * 1024;
  final StreamController<OfflineDownloadProgress> _progress = StreamController.broadcast();
  int _active = 0;
  final List<_DownloadJob> _queue = [];
  final Set<String> _queuedIds = {};

  Stream<OfflineDownloadProgress> get progressStream => _progress.stream;

  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    // The app owns the database lifecycle; do not close it from a page.
  }

  Future<void> _resumeQueuedDownloads() async {
    if (!await _connectivity.isOnline()) {
      return;
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }
    try {
      final rows = await _db.getDownloadedFiles(userId: userId);
      for (final row in rows.where((item) => item.status == 'queued')) {
        if (_queuedIds.contains(row.resourceId)) {
          continue;
        }
        try {
          final resources = await _resources.listForCourse(row.courseId);
          final resource = resources.firstWhere((item) => item.id == row.resourceId);
          if (_queuedIds.add(resource.id)) {
            _queue.add(_DownloadJob(
              userId: row.userId,
              resource: resource,
              localPath: row.localPath,
              remoteUpdatedAt: row.remoteUpdatedAt,
            ));
          }
        } catch (_) {
          // The course may have been removed; the next online course open will reconcile it.
        }
      }
      _pump();
    } catch (_) {
      // Cache recovery must never block the UI/network path.
    }
  }

  Future<List<DownloadedFileRecord>> filesForCourse(String userId, String courseId) =>
      _db.getDownloadedFiles(userId: userId, courseId: courseId);

  Future<List<CourseResource>> resourcesForCourse(String userId, String courseId) async {
    try {
      final remote = await _resources.listForCourse(courseId);
      return remote;
    } catch (_) {
      final local = await _db.getDownloadedFiles(userId: userId, courseId: courseId);
      return local.map((file) {
        final type = _resourceType(file.mimeType, file.fileName);
        return CourseResource(
          id: file.resourceId, courseId: courseId, resourceType: type,
          storagePath: '', fileName: file.fileName, mimeType: file.mimeType,
          fileSize: file.sizeBytes, titleFr: file.fileName, titleEn: file.fileName,
        );
      }).toList(growable: false);
    }
  }

  String _resourceType(String? mime, String fileName) {
    final value = (mime ?? '').toLowerCase();
    if (value.contains('pdf') || fileName.toLowerCase().endsWith('.pdf')) {
      return 'pdf';
    }
    if (value.startsWith('image/')) {
      return 'image';
    }
    if (value.startsWith('audio/')) {
      return 'audio';
    }
    if (value.startsWith('video/')) {
      return 'video';
    }
    return 'document';
  }

  Future<DownloadedFileRecord?> getLocal(String userId, String resourceId) =>
      _db.getDownloadedFile(resourceId, userId);

  Future<int> usedBytes(String userId) => _db.downloadedFilesSize(userId);

  Future<void> enqueueCourse({required String userId, required Course course}) async {
    if (course.status != 'published') {
      return;
    }
    final online = await _connectivity.isOnline();
    if (!online) {
      return;
    }

    final resources = await _resources.listForCourse(course.id);
    final lessons = await LessonService().listCourseLessons(course.id);
    await OfflineRepository().saveLessons(lessons);
    // Cache the published QCM/devoirs attached to this course so the existing
    // offline repository can answer them without a network connection.
    try {
      await AssignmentService().listStudentAssignments(studentId: userId, courseId: course.id);
    } catch (_) {
      // Resource downloads and course caching must continue even if one QCM fails.
    }
    final remoteIds = resources.map((r) => r.id).toSet();
    for (final old in await _db.getDownloadedFiles(userId: userId, courseId: course.id)) {
      if (!remoteIds.contains(old.resourceId)) {
        try { await File(old.localPath).delete(); } catch (_) {}
        await _db.deleteDownloadedFile(old.resourceId, userId);
      }
    }
    for (final resource in resources) {
      await _enqueueResource(userId: userId, resource: resource);
    }
  }

  Future<void> queueResource({required String userId, required CourseResource resource, bool manual = false}) async {
    await _enqueueResource(userId: userId, resource: resource, force: manual);
  }

  Future<void> enqueueSubject({required String userId, required List<Course> courses}) async {
    for (final course in courses) {
      await enqueueCourse(userId: userId, course: course);
    }
  }

  Future<void> _enqueueResource({required String userId, required CourseResource resource, bool force = false}) async {
    if (!force && resource.resourceType == 'video' && (resource.fileSize ?? (_maxVideoBytes + 1)) > _maxVideoBytes) {
      return;
    }

    final existing = await _db.getDownloadedFile(resource.id, userId);
    final remoteUpdatedAt = await _remoteUpdatedAt(resource.id);
    final localValid = existing != null && existing.status == 'done' && File(existing.localPath).existsSync();
    final remoteChanged = existing?.remoteUpdatedAt != null && remoteUpdatedAt != null &&
        remoteUpdatedAt.isAfter(existing!.remoteUpdatedAt!);
    if (localValid && !remoteChanged) {
      return;
    }

    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'offline', userId, resource.courseId));
    await directory.create(recursive: true);
    final localPath = p.join(directory.path, _safeFileName(resource.fileName, resource.id));

    final record = DownloadedFileRecord(
      resourceId: resource.id,
      courseId: resource.courseId,
      userId: userId,
      fileName: resource.fileName,
      mimeType: resource.mimeType,
      localPath: localPath,
      sizeBytes: resource.fileSize ?? 0,
      remoteUpdatedAt: remoteUpdatedAt,
      downloadedAt: existing?.downloadedAt,
      lastOpenedAt: existing?.lastOpenedAt,
      status: 'queued',
    );
    await _db.upsertDownloadedFile(record);

    if (_queuedIds.add(resource.id)) {
      _queue.add(_DownloadJob(userId: userId, resource: resource, localPath: localPath, remoteUpdatedAt: remoteUpdatedAt));
      _pump();
    }
  }

  Future<DateTime?> _remoteUpdatedAt(String resourceId) async {
    try {
      final row = await _client.from('course_resources').select('updated_at,created_at').eq('id', resourceId).single();
      return DateTime.tryParse((row['updated_at'] ?? row['created_at']).toString())?.toUtc();
    } catch (_) {
      return null;
    }
  }

  void _pump() {
    while (_active < _maxParallel && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      _queuedIds.remove(job.resource.id);
      _download(job).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<void> _download(_DownloadJob job) async {
    final resource = job.resource;
    try {
      final wifiOnly = await _settings.wifiOnly();
      if (wifiOnly) {
        final connectivity = await Connectivity().checkConnectivity();
        if (!connectivity.contains(ConnectivityResult.wifi)) {
          await _db.updateDownloadedFileStatus(resource.id, job.userId, 'queued');
          _progress.add(OfflineDownloadProgress(resourceId: resource.id, received: 0, total: resource.fileSize ?? 0, status: 'queued'));
          return;
        }
      }

      if (!await _hasSpace(job.userId, resource.fileSize ?? 0)) {
        await enforceStorageLimit(job.userId, extraBytes: resource.fileSize ?? 0);
        if (!await _hasSpace(job.userId, resource.fileSize ?? 0)) {
          await _db.updateDownloadedFileStatus(resource.id, job.userId, 'failed');
          _progress.add(OfflineDownloadProgress(resourceId: resource.id, received: 0, total: resource.fileSize ?? 0, status: 'failed'));
          return;
        }
      }

      await _db.updateDownloadedFileStatus(resource.id, job.userId, 'downloading');
      final partPath = '${job.localPath}.part';
      final part = File(partPath);
      var received = part.existsSync() ? await part.length() : 0;

      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          if (!await _connectivity.isOnline()) {
            throw const SocketException('offline');
          }
          final signedUrl = await _resources.createSignedUrl(resource.storagePath, expiresIn: 3600);
          final headers = <String, String>{if (received > 0) 'Range': 'bytes=$received-'};
          final response = await http.get(Uri.parse(signedUrl), headers: headers);
          if (response.statusCode != 200 && response.statusCode != 206) {
            throw HttpException('HTTP ${response.statusCode}');
          }
          if (response.statusCode == 200 && received > 0) {
            received = 0;
            await part.writeAsBytes(const <int>[], flush: true);
          }
          final sink = part.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
          final bytes = response.bodyBytes;
          sink.add(bytes);
          await sink.close();
          received += bytes.length;
          final total = resource.fileSize ?? received;
          _progress.add(OfflineDownloadProgress(resourceId: resource.id, received: received, total: total, status: 'downloading'));

          final actual = await part.length();
          if (resource.fileSize != null && actual < resource.fileSize!) {
            throw const SocketException('incomplete download');
          }
          final destination = File(job.localPath);
          if (destination.existsSync()) {
            await destination.delete();
          }
          await part.rename(job.localPath);
          await _db.upsertDownloadedFile((await _db.getDownloadedFile(resource.id, job.userId) ?? DownloadedFileRecord(
            resourceId: resource.id, courseId: resource.courseId, userId: job.userId, fileName: resource.fileName,
            mimeType: resource.mimeType, localPath: job.localPath, sizeBytes: actual, status: 'done',
          )).copyWith(sizeBytes: actual, remoteUpdatedAt: job.remoteUpdatedAt, downloadedAt: DateTime.now().toUtc(), status: 'done'));
          _progress.add(OfflineDownloadProgress(resourceId: resource.id, received: actual, total: total, status: 'done'));
          return;
        } catch (_) {
          if (attempt == 3) {
            rethrow;
          }
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    } catch (_) {
      await _db.updateDownloadedFileStatus(resource.id, job.userId, 'failed');
      _progress.add(OfflineDownloadProgress(resourceId: resource.id, received: 0, total: resource.fileSize ?? 0, status: 'failed'));
    }
  }

  Future<bool> _hasSpace(String userId, int extraBytes) async {
    final limit = (await _settings.limitMb()) * 1024 * 1024;
    return (await usedBytes(userId)) + extraBytes <= limit;
  }

  Future<void> enforceStorageLimit(String userId, {int extraBytes = 0}) async {
    final limit = (await _settings.limitMb()) * 1024 * 1024;
    var used = await usedBytes(userId);
    if (used + extraBytes <= limit) {
      return;
    }
    final files = await _db.getDownloadedFiles(userId: userId);
    for (final file in files) {
      if (file.status != 'done') {
        continue;
      }
      try { await File(file.localPath).delete(); } catch (_) {}
      await _db.deleteDownloadedFile(file.resourceId, userId);
      used -= file.sizeBytes;
      if (used + extraBytes <= limit) {
        break;
      }
    }
  }

  Future<void> markOpened(String userId, String resourceId) => _db.markDownloadedFileOpened(resourceId, userId);

  Future<void> deleteUserFiles(String userId) async {
    final files = await _db.getDownloadedFiles(userId: userId);
    for (final file in files) {
      try { await File(file.localPath).delete(); } catch (_) {}
      try { await File('${file.localPath}.part').delete(); } catch (_) {}
    }
    await _db.deleteAllDownloadedFiles(userId);
    final base = await getApplicationDocumentsDirectory();
    try { await Directory(p.join(base.path, 'offline', userId)).delete(recursive: true); } catch (_) {}
  }

  Future<void> deleteCourseFiles(String userId, String courseId) async {
    final files = await _db.getDownloadedFiles(userId: userId, courseId: courseId);
    for (final file in files) {
      try { await File(file.localPath).delete(); } catch (_) {}
      try { await File('${file.localPath}.part').delete(); } catch (_) {}
      await _db.deleteDownloadedFile(file.resourceId, userId);
    }
    final base = await getApplicationDocumentsDirectory();
    try { await Directory(p.join(base.path, 'offline', userId, courseId)).delete(recursive: true); } catch (_) {}
  }

  Future<void> deleteAll(String userId) => deleteUserFiles(userId);

  String _safeFileName(String name, String id) {
    final clean = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${id}_$clean';
  }
}

class _DownloadJob {
  final String userId;
  final CourseResource resource;
  final String localPath;
  final DateTime? remoteUpdatedAt;
  const _DownloadJob({required this.userId, required this.resource, required this.localPath, required this.remoteUpdatedAt});
}
