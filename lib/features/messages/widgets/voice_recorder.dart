import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/services/photo_service.dart';

/// Bouton micro : ouvre un enregistreur de note vocale et renvoie la pièce jointe prête à envoyer.
class VoiceRecorderButton extends StatelessWidget {
  const VoiceRecorderButton({super.key, required this.onRecorded, this.enabled = true, this.french = true});

  final void Function(PickedAttachment attachment) onRecorded;
  final bool enabled;
  final bool french;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: french ? 'Message vocal' : 'Voice message',
      onPressed: !enabled
          ? null
          : () async {
              final result = await showModalBottomSheet<PickedAttachment>(
                context: context,
                isDismissible: false,
                enableDrag: false,
                builder: (_) => _RecorderSheet(french: french),
              );
              if (result != null) onRecorded(result);
            },
      icon: const Icon(Icons.mic_rounded),
    );
  }
}

class _RecorderSheet extends StatefulWidget {
  const _RecorderSheet({required this.french});
  final bool french;

  @override
  State<_RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<_RecorderSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  String? _path;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), path: _path!);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    } catch (_) {
      if (mounted) setState(() => _denied = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try { await _recorder.stop(); } catch (_) {}
    final p = _path;
    if (p != null) { try { await File(p).delete(); } catch (_) {} }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    _timer?.cancel();
    try {
      final out = await _recorder.stop() ?? _path;
      if (out == null) { if (mounted) Navigator.of(context).pop(); return; }
      final bytes = await File(out).readAsBytes();
      if (bytes.isEmpty || _seconds < 1) { if (mounted) Navigator.of(context).pop(); return; }
      if (!mounted) return;
      Navigator.of(context).pop(PickedAttachment(
        bytes: bytes,
        name: 'vocal_${DateTime.now().millisecondsSinceEpoch}.m4a',
        mimeType: 'audio/aac',
      ));
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.french;
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _denied
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fr ? 'Autorise le micro pour enregistrer un message vocal.' : 'Allow the microphone to record a voice message.'),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(fr ? 'Fermer' : 'Close')),
              ])
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.fiber_manual_record, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text('$mm:$ss', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(fr ? 'Enregistrement en cours…' : 'Recording…', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.delete_outline), label: Text(fr ? 'Annuler' : 'Cancel')),
                  FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.send_rounded), label: Text(fr ? 'Envoyer' : 'Send')),
                ]),
              ]),
      ),
    );
  }
}
