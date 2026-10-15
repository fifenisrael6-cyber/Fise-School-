import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Lecteur vocal compact, lisible et intégré aux bulles de messagerie.
class VoiceMessageBubble extends StatefulWidget {
  final String url;
  final bool isFrench;

  const VoiceMessageBubble({
    super.key,
    required this.url,
    required this.isFrench,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((value) {
      if (mounted) setState(() => _state = value);
    });
    _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  String _time(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggle() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (_state == PlayerState.playing) {
        await _player.pause();
      } else {
        if (_state == PlayerState.stopped || _state == PlayerState.completed) {
          await _player.setSourceUrl(widget.url);
          await _player.resume();
        } else {
          await _player.resume();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = widget.isFrench
            ? 'Lecture vocale indisponible. Vérifiez la connexion.'
            : 'Voice playback unavailable. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final progress = totalMs <= 0
        ? 0.0
        : (_position.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
    final playing = _state == PlayerState.playing;
    return Container(
      width: 250,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _starting ? null : _toggle,
            icon: _starting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
            iconSize: 34,
            color: const Color(0xFF166534),
            tooltip: playing
                ? (widget.isFrench ? 'Mettre en pause' : 'Pause')
                : (widget.isFrench ? 'Lire le message vocal' : 'Play voice message'),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic_rounded, size: 15, color: Color(0xFF166534)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.isFrench ? 'Message vocal' : 'Voice message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF17452A),
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: totalMs <= 0
                        ? null
                        : (value) => _player.seek(Duration(
                              milliseconds: (totalMs * value).round(),
                            )),
                    activeColor: const Color(0xFF166534),
                    inactiveColor: const Color(0xFFB7D6BF),
                  ),
                ),
                Text(
                  '${_time(_position)} / ${_time(_duration)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF315B3C)),
                ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(fontSize: 10, color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
