import 'package:flutter/material.dart';

/// Garde une page en vie dans un [PageView] : son état (défilement, texte saisi,
/// données chargées) n'est pas perdu quand on balaie vers un autre onglet.
class KeepAlivePage extends StatefulWidget {
  final Widget child;

  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin<KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Coque de navigation « façon WhatsApp » : on passe d'un onglet à l'autre
/// en balayant l'écran ou en touchant la barre du bas, les deux restent
/// synchronisés et aucune page n'est reconstruite ni écrasée.
class SwipeTabsShell extends StatefulWidget {
  /// Construit les pages. [goToTab] permet à une page d'ouvrir un autre onglet.
  final List<Widget> Function(ValueChanged<int> goToTab) pagesBuilder;
  final List<NavigationDestination> destinations;
  final NavigationDestinationLabelBehavior labelBehavior;
  final int initialIndex;

  const SwipeTabsShell({
    super.key,
    required this.pagesBuilder,
    required this.destinations,
    this.labelBehavior = NavigationDestinationLabelBehavior.alwaysShow,
    this.initialIndex = 0,
  });

  @override
  State<SwipeTabsShell> createState() => _SwipeTabsShellState();
}

class _SwipeTabsShellState extends State<SwipeTabsShell> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int target) {
    if (!mounted || target == _index) return;
    setState(() => _index = target);
    if (!_controller.hasClients) return;
    final current = _controller.page?.round() ?? _index;
    if ((target - current).abs() == 1) {
      // Onglet voisin : glissement animé, comme un balayage.
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Onglet éloigné : saut direct pour ne pas charger les pages intermédiaires.
      _controller.jumpToPage(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pagesBuilder(_goTo);
    return PopScope(
      // Retour système : on revient d'abord à l'onglet d'accueil.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(0);
      },
      child: Scaffold(
        body: PageView(
          controller: _controller,
          onPageChanged: (value) {
            if (value != _index) setState(() => _index = value);
          },
          children: [
            for (var i = 0; i < pages.length; i++)
              KeepAlivePage(key: ValueKey('swipe-tab-$i'), child: pages[i]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          labelBehavior: widget.labelBehavior,
          onDestinationSelected: _goTo,
          destinations: widget.destinations,
        ),
      ),
    );
  }
}
