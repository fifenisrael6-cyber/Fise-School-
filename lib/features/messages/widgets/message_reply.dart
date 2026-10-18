import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Texte court affiché dans une citation (message cité ou bandeau « Répondre à »).
String replySnippet({
  required String body,
  required bool hasAttachment,
  String? attachmentName,
  String? attachmentType,
  required bool french,
}) {
  if (body == '__PREMIUM_LOCKED__') {
    return french ? '🔒 Message verrouillé' : '🔒 Locked message';
  }
  final text = body.trim();
  if (text.isNotEmpty) return text;
  if (!hasAttachment) {
    return french ? 'Message supprimé' : 'Deleted message';
  }
  final type = attachmentType ?? '';
  if (type.startsWith('image/')) return '📷 Photo';
  if (type.startsWith('audio/')) {
    return french ? '🎤 Message vocal' : '🎤 Voice message';
  }
  if (type.startsWith('video/')) return french ? '🎥 Vidéo' : '🎥 Video';
  if (attachmentName != null && attachmentName.isNotEmpty) {
    return '📎 $attachmentName';
  }
  return french ? '📎 Pièce jointe' : '📎 Attachment';
}

/// Glisser un message vers la droite (ou appui long) pour y répondre, comme sur WhatsApp.
class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const double _trigger = 56;
  static const double _max = 72;
  double _dx = 0;

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    setState(() => _dx = (_dx + details.delta.dx).clamp(0.0, _max));
  }

  void _onEnd(DragEndDetails details) {
    final triggered = widget.enabled && _dx >= _trigger;
    setState(() => _dx = 0);
    if (triggered) {
      HapticFeedback.selectionClick();
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      onLongPress: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onReply();
            }
          : null,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 8,
            child: Opacity(
              opacity: (_dx / _trigger).clamp(0.0, 1.0),
              child: const Icon(Icons.reply_rounded, color: Colors.black45),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Citation affichée en haut d'une bulle de message.
class QuotedMessage extends StatelessWidget {
  final String author;
  final String snippet;
  final Color accent;

  const QuotedMessage({
    super.key,
    required this.author,
    required this.snippet,
    this.accent = const Color(0xFF166534),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color(0x14000000),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (author.isNotEmpty)
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        Text(
                          snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau « Répondre à … » affiché au-dessus de la zone d'écriture.
class ReplyComposerBar extends StatelessWidget {
  final String author;
  final String snippet;
  final VoidCallback onCancel;
  final bool french;
  final Color accent;

  const ReplyComposerBar({
    super.key,
    required this.author,
    required this.snippet,
    required this.onCancel,
    required this.french,
    this.accent = const Color(0xFF166534),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: const Color(0xFFF1F5F4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        Text(
                          snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: french ? 'Annuler la réponse' : 'Cancel reply',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
