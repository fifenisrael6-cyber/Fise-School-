import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'photo_service.dart';

/// Enregistre un court mémo vocal localement avant de l'envoyer dans le
/// stockage privé de la messagerie.
class VoiceNoteService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted.');
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/fise-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _recordingPath = path;
  }

  Future<PickedAttachment?> stop() async {
    final path = await _recorder.stop();
    final recordingPath = path ?? _recordingPath;
    _recordingPath = null;
    if (recordingPath == null) return null;

    final file = File(recordingPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {
      // Le fichier est dans le répertoire temporaire; son nettoyage n'est
      // pas une condition pour envoyer le mémo vocal.
    }
    if (bytes.isEmpty) return null;
    return PickedAttachment(
      bytes: Uint8List.fromList(bytes),
      name: 'message-vocal-${DateTime.now().millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
    );
  }

  Future<void> dispose() => _recorder.dispose();
}
