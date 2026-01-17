import 'package:flutter/material.dart';

/// Specifica di una tab (id stabile + tab widget + view widget)
class DmsTabSpec {
  final String id;
  final Widget tab;
  final Widget view;

  const DmsTabSpec({
    required this.id,
    required this.tab,
    required this.view,
  });
}

/// Wrapper per mantenere vivo lo stato delle tab (scroll, liste, ecc.)
class DmsKeepAlive extends StatefulWidget {
  final Widget child;
  const DmsKeepAlive({super.key, required this.child});

  @override
  State<DmsKeepAlive> createState() => _DmsKeepAliveState();
}

class _DmsKeepAliveState extends State<DmsKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Sezione tabs standard: TabBar + TabBarView.
/// - key interna “stabile” ricostruita quando cambia lista tab (ids)
/// - keepAlive true di default
class DmsTabbedSection extends StatelessWidget {
  final List<DmsTabSpec> tabs;
  final bool isScrollable;
  final bool keepAlive;
  final Color? tabBarBackground;

  const DmsTabbedSection({
    super.key,
    required this.tabs,
    this.isScrollable = false,
    this.keepAlive = true,
    this.tabBarBackground,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    // ✅ forza TabController nuovo quando cambiano le tab (utile per tab dinamiche)
    final controllerKey = ValueKey('dms_tabs_${tabs.map((t) => t.id).join("|")}');

    return DefaultTabController(
      key: controllerKey,
      length: tabs.length,
      child: Column(
        children: [
          Material(
            color: tabBarBackground ?? Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: isScrollable,
              tabs: [for (final t in tabs) t.tab],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in tabs)
                  keepAlive
                      ? DmsKeepAlive(
                    child: KeyedSubtree(
                      // ✅ preserva anche PageStorage (scroll) per tab
                      key: PageStorageKey('tab_${t.id}'),
                      child: t.view,
                    ),
                  )
                      : t.view,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
