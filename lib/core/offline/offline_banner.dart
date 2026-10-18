import 'dart:async';

import 'package:flutter/material.dart';

import 'connectivity_service.dart';
import 'pending_progress.dart';

/// Enveloppe l'application : affiche une barre « mode hors ligne » en haut
/// quand l'appareil n'a plus de réseau.
///
/// La structure de l'arbre de widgets reste identique en ligne et hors ligne
/// (aucun widget ajouté/retiré autour de [child]) pour ne jamais réinitialiser
/// la navigation ni l'état des écrans.
class OfflineAwareShell extends StatefulWidget {
  const OfflineAwareShell({
    super.key,
    required this.languageCode,
    required this.child,
  });

  final String languageCode;
  final Widget child;

  @override
  State<OfflineAwareShell> createState() => _OfflineAwareShellState();
}

class _OfflineAwareShellState extends State<OfflineAwareShell> {
  final ConnectivityService _connectivity = ConnectivityService();
  StreamSubscription<bool>? _subscription;
  bool _offline = false;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _connectivity.isOnline().then((online) {
      if (mounted) _setOnline(online);
    }).catchError((Object _) {});
    _subscription = _connectivity.connectionStream.listen(_setOnline);
  }

  Future<void> _setOnline(bool online) async {
    final pending = online ? 0 : await PendingProgress.instance.count();
    if (!mounted) return;
    setState(() {
      _offline = !online;
      _pending = pending;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fr = widget.languageCode != 'en';
    final base = fr
        ? 'Mode hors ligne — vos cours téléchargés restent disponibles'
        : 'Offline mode — your downloaded courses remain available';
    final waiting = fr ? "en attente d'envoi" : 'waiting to sync';
    final message = _pending > 0 ? '$base ($_pending $waiting)' : base;

    return Column(
      children: [
        if (_offline)
          Material(
            color: const Color(0xFFB45309),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: _offline,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
