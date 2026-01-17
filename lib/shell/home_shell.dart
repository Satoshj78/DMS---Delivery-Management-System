// lib/shell/home_shell.dart
// HomeShell: layout desktop 3-pannelli resizable + sidebar collassabile + scorciatoie tastiera (F1, Ctrl+B, Ctrl/Alt+1..)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/service/auth/auth_service.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/settings/settings_page.dart';
import '../features/users/users_page.dart';
import '../features/users/join_requests_page.dart';
import 'package:dms_app/core/ui/dms_badge_icon_button.dart';
import '../features/users/users_detail_page.dart';

class HomeShell extends StatefulWidget {
  final String leagueId;
  const HomeShell({super.key, required this.leagueId});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

// -------------------------------
// INTENTS (Shortcuts)
// -------------------------------
class _ToggleLeftCollapsedIntent extends Intent {
  const _ToggleLeftCollapsedIntent();
}

class _OpenKeyboardHelpIntent extends Intent {
  const _OpenKeyboardHelpIntent();
}

class _GoToTabIntent extends Intent {
  const _GoToTabIntent(this.index);
  final int index;
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  // ✅ selezione per pannello destro (Users)
  String? _selectedUserId;

  // ✅ layout prefs (persistenti in Firestore)
  bool _prefsLoaded = false;
  bool _didSeedPrefs = false;

  // ✅ DEFAULT come nello screenshot (se non esistono preferenze)
  // larghezze “expanded” (in px)
  double _leftW = 200;
  double _centerW = 867;

  // sidebar “solo icone”
  bool _leftCollapsed = false;

  Timer? _saveDebounce;

  bool _isPrivilegedRole(String? roleId) {
    final r = (roleId ?? '').toLowerCase().trim();
    return r == 'owner' || r == 'admin' || r == 'coo' || r == 'manager';
  }

  double _asDouble(dynamic v, double def) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? def;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  DocumentReference<Map<String, dynamic>>? _userRefOrNull() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('Users').doc(uid);
  }

  // -------------------------------
  // PREFERENZE LAYOUT (LOAD/SEED/SAVE)
  // -------------------------------
  Future<void> _loadLayoutPrefsOnce() async {
    if (_prefsLoaded) return;

    final userRef = _userRefOrNull();
    if (userRef == null) {
      setState(() => _prefsLoaded = true);
      return;
    }

    try {
      final snap = await userRef.get();
      final data = snap.data() ?? {};

      final uiPrefs = _asMap(data['uiPrefs']);
      final leaguePrefs = _asMap(uiPrefs[widget.leagueId]);
      final desktopShell = _asMap(leaguePrefs['desktopShell']);

      final hasAnyPrefs = desktopShell.isNotEmpty;

      // ✅ se esistono prefs → applico
      if (hasAnyPrefs) {
        setState(() {
          _leftW = _asDouble(desktopShell['leftW'], _leftW);
          _centerW = _asDouble(desktopShell['centerW'], _centerW);
          _leftCollapsed = (desktopShell['leftCollapsed'] == true);
          _prefsLoaded = true;
        });
        return;
      }

      // ✅ se NON esistono prefs → uso default (già impostati sopra) e SEED su Firestore (una sola volta)
      setState(() => _prefsLoaded = true);

      if (!_didSeedPrefs) {
        _didSeedPrefs = true;
        await _saveLayoutPrefs(); // scrive default
      }
    } catch (_) {
      setState(() => _prefsLoaded = true);
    }
  }

  Future<void> _saveLayoutPrefs() async {
    final userRef = _userRefOrNull();
    if (userRef == null) return;

    await userRef.set(
      {
        'uiPrefs': {
          widget.leagueId: {
            'desktopShell': {
              'leftW': _leftW,
              'centerW': _centerW,
              'leftCollapsed': _leftCollapsed,
              'updatedAt': FieldValue.serverTimestamp(),
              'platform': kIsWeb ? 'web' : 'app',
            }
          }
        }
      },
      SetOptions(merge: true),
    );
  }

  void _saveLayoutPrefsDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      _saveLayoutPrefs();
    });
  }

  void _toggleLeftCollapsed() {
    setState(() => _leftCollapsed = !_leftCollapsed);
    _saveLayoutPrefsDebounced();
  }

  void _goToTab(int index) {
    if (index < 0 || index > 2) return;
    setState(() {
      _i = index;
      if (_i != 1) _selectedUserId = null; // se esco da Users, chiudo il dettaglio a dx
    });
  }

  void _handleEscape() {
    // ✅ comportamento utile: se sei su Users e hai selezionato un utente, ESC lo “chiude”
    if (_i == 1 && _selectedUserId != null && _selectedUserId!.isNotEmpty) {
      setState(() => _selectedUserId = null);
    } else {
      // opzionale: Navigator.maybePop(context);
      // (lo lascio neutro per non rompere flussi esistenti)
    }
  }

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1100;

  // -------------------------------
  // HELP DIALOG (in-app)
  // -------------------------------
  Future<void> _showKeyboardHelp() async {
    const rows = <Map<String, String>>[
      {'keys': 'F1', 'action': 'Apri guida tastiera'},
      {'keys': 'Ctrl + /', 'action': 'Apri guida tastiera'},
      {'keys': 'Ctrl + B', 'action': 'Collassa/Espandi barra sinistra'},
      {'keys': 'Ctrl + 1 / 2 / 3', 'action': 'Vai a Home / Users / Impostazioni'},
      {'keys': 'Alt + 1 / 2 / 3', 'action': 'Vai a Home / Users / Impostazioni'},
      {'keys': 'Esc', 'action': 'Chiudi dettaglio utente (in Users) / chiudi dialog'},
      {'keys': 'Tab / Shift+Tab', 'action': 'Vai al campo successivo/precedente (nei form)'},
      {'keys': '↑ / ↓', 'action': 'Naviga le liste (se implementi KeyboardSelectableList)'},
      {'keys': 'Enter', 'action': 'Apri/Attiva elemento selezionato (se implementi KeyboardSelectableList)'},
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Guida tastiera'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Scorciatoie principali (Desktop)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              r['keys'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(r['action'] ?? ''),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Suggerimento',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Per avere navigazione completa delle card senza mouse (↑ ↓ Enter), '
                        'usa il widget KeyboardSelectableList nelle pagine lista (es. UsersPage).',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Chiudi (Esc)'),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------
  // PAGES
  // -------------------------------
  Widget _centerPage() {
    if (_i == 0) return DashboardPage(leagueId: widget.leagueId);
    if (_i == 1) {
      return UsersPage(
        leagueId: widget.leagueId,
        embedded: true,
        selectedUserId: _selectedUserId,
        onSelectUser: (uid) => setState(() => _selectedUserId = uid),
      );
    }
    return SettingsPage(leagueId: widget.leagueId);
  }

  Widget _rightPane() {
    // pannello destro: dettaglio user se siamo su Users
    if (_i == 1) {
      if (_selectedUserId == null || _selectedUserId!.isEmpty) {
        return const Center(
          child: Text('Seleziona un utente per vedere il dettaglio.'),
        );
      }
      return UserDetailPage(
        leagueId: widget.leagueId,
        userId: _selectedUserId!,
        embedded: true,
      );
    }
    return const Center(child: Text(''));
  }

  Widget _leftNavRail() {
    final rail = NavigationRail(
      extended: !_leftCollapsed,
      selectedIndex: _i,
      onDestinationSelected: (v) {
        setState(() {
          _i = v;
          if (_i != 1) _selectedUserId = null;
        });
      },
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Users'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Impostazioni'),
        ),
      ],
    );


    final w = MediaQuery.of(context).size.width;
    final isPcLike = kIsWeb && w >= 1100;

    return Material(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: rail,
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              if (isPcLike)
                IconButton(
                  tooltip: 'Guida tastiera (F1)',
                  icon: const Icon(Icons.help_outline),
                  onPressed: _showKeyboardHelp,
                ),
              const Spacer(),
              IconButton(
                tooltip: _leftCollapsed ? 'Espandi menu (Ctrl+B)' : 'Comprimi menu (Ctrl+B)',
                icon: Icon(_leftCollapsed ? Icons.chevron_right : Icons.chevron_left),
                onPressed: _toggleLeftCollapsed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------
  // DESKTOP LAYOUT 3-PANE RESIZABLE
  // -------------------------------
  Widget _buildDesktopThreePane() {
    const dividerW = 8.0;

    // minimi
    const leftMinExpanded = 200.0;
    const leftCollapsedW = 76.0;
    const centerMin = 360.0;
    const rightMin = 420.0;

    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth;

        // left effettivo
        var leftW = _leftCollapsed ? leftCollapsedW : _leftW;

        // clamp left per lasciare spazio a center + right
        final leftMax = (total - centerMin - rightMin - 2 * dividerW);
        leftW = leftW.clamp(_leftCollapsed ? leftCollapsedW : leftMinExpanded, leftMax);

        // clamp center
        final centerMax = (total - leftW - rightMin - 2 * dividerW);
        var centerW = _centerW.clamp(centerMin, centerMax);

        // right è il resto
        final rightW = total - leftW - centerW - 2 * dividerW;

        // se per qualche rounding right scende sotto min, riallineo
        if (rightW < rightMin) {
          centerW = (centerW - (rightMin - rightW)).clamp(centerMin, centerMax);
        }

        void dragLeft(double dx) {
          setState(() {
            if (_leftCollapsed) {
              _leftCollapsed = false;
              _leftW = leftMinExpanded;
            }
            _leftW = (_leftW + dx).clamp(leftMinExpanded, leftMax);
          });
        }

        void dragCenter(double dx) {
          setState(() {
            _centerW = (_centerW + dx).clamp(centerMin, centerMax);
          });
        }

        return Row(
          children: [
            SizedBox(
              width: leftW,
              child: _paneFrame(_leftNavRail()),
            ),
            _ResizeDivider(
              width: dividerW,
              onDelta: dragLeft,
              onEnd: _saveLayoutPrefsDebounced,
            ),
            SizedBox(
              width: centerW,
              child: _paneFrame(_centerPage()),
            ),
            _ResizeDivider(
              width: dividerW,
              onDelta: dragCenter,
              onEnd: _saveLayoutPrefsDebounced,
            ),
            Expanded(
              child: _paneFrame(_rightPane()),
            ),
          ],
        );
      },
    );
  }

  Widget _paneFrame(Widget child) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLayoutPrefsOnce());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // -------------------------------
    // SHORTCUTS GLOBALI (root)
    // -------------------------------
    final shortcuts = <LogicalKeySet, Intent>{
      // Help
      LogicalKeySet(LogicalKeyboardKey.f1): const _OpenKeyboardHelpIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.slash): const _OpenKeyboardHelpIntent(),

      // Toggle sidebar
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB): const _ToggleLeftCollapsedIntent(),

      // Nav tabs: Ctrl+1..3
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1): const _GoToTabIntent(0),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2): const _GoToTabIntent(1),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3): const _GoToTabIntent(2),

      // Nav tabs: Alt+1..3 (utile se preferisci)
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit1): const _GoToTabIntent(0),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit2): const _GoToTabIntent(1),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit3): const _GoToTabIntent(2),

      // ESC
      LogicalKeySet(LogicalKeyboardKey.escape): const _EscapeIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _OpenKeyboardHelpIntent: CallbackAction<_OpenKeyboardHelpIntent>(onInvoke: (_) {
        _showKeyboardHelp();
        return null;
      }),
      _ToggleLeftCollapsedIntent: CallbackAction<_ToggleLeftCollapsedIntent>(onInvoke: (_) {
        _toggleLeftCollapsed();
        return null;
      }),
      _GoToTabIntent: CallbackAction<_GoToTabIntent>(onInvoke: (i) {
        _goToTab(i.index);
        return null;
      }),
      _EscapeIntent: CallbackAction<_EscapeIntent>(onInvoke: (_) {
        _handleEscape();
        return null;
      }),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          autofocus: true,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('Leagues')
                .doc(widget.leagueId)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Scaffold(
                  body: Center(child: Text('Errore nel caricamento della League')),
                );
              }

              if (!snap.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final leagueName = snap.data!.data()?['nome']?.toString().trim();
              final titleName =
              (leagueName == null || leagueName.isEmpty) ? 'League' : leagueName;

              final Stream<DocumentSnapshot<Map<String, dynamic>>> memberStream = (uid == null)
                  ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
                  : FirebaseFirestore.instance
                  .collection('Leagues')
                  .doc(widget.leagueId)
                  .collection('members')
                  .doc(uid)
                  .snapshots();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: memberStream,
                builder: (context, memberSnap) {
                  final roleId = memberSnap.data?.data()?['roleId']?.toString();
                  final canManageRequests = _isPrivilegedRole(roleId);

                  final Stream<QuerySnapshot<Map<String, dynamic>>> reqStream = canManageRequests
                      ? FirebaseFirestore.instance
                      .collection('Leagues')
                      .doc(widget.leagueId)
                      .collection('joinRequests')
                      .where('status', isEqualTo: 'pending')
                      .snapshots()
                      : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();


                  final isPcLike = MediaQuery.of(context).size.width >= 1100;
                  return Scaffold(

                  appBar: AppBar(
                    title: Text('DMS • $titleName'),
                    actions: [
                      if (isPcLike)
                        IconButton(
                          tooltip: 'Guida tastiera (F1)',
                          onPressed: _showKeyboardHelp,
                          icon: const Icon(Icons.help_outline),
                        ),

                      if (canManageRequests)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: reqStream,
                          builder: (context, reqSnap) {
                            final count = reqSnap.data?.size ?? 0;

                            return DmsBadgeIconButton(
                              icon: Icons.how_to_reg,
                              count: count,
                              tooltip: 'Richieste accesso',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => JoinRequestsPage(
                                      leagueId: widget.leagueId,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),

                      IconButton(
                        tooltip: 'Cambia League',
                        onPressed: () async {
                          final u = FirebaseAuth.instance.currentUser;
                          if (u == null) return;
                          await FirebaseFirestore.instance
                              .collection('Users')
                              .doc(u.uid)
                              .set(
                            {
                              'activeLeagueId': null,
                              'updatedAt': FieldValue.serverTimestamp()
                            },
                            SetOptions(merge: true),
                          );
                        },
                        icon: const Icon(Icons.swap_horiz),
                      ),
                      IconButton(
                        tooltip: 'Logout',
                        onPressed: () async {
                          await AuthService().signOut(clearActiveLeague: true);
                        },
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),


                  // ✅ DESKTOP: 3 colonne resizable
                    // ✅ MOBILE: comportamento originale
                    body: _isDesktop
                        ? _buildDesktopThreePane()
                        : IndexedStack(
                      index: _i,
                      children: [
                        DashboardPage(leagueId: widget.leagueId),
                        UsersPage(leagueId: widget.leagueId),
                        SettingsPage(leagueId: widget.leagueId),
                      ],
                    ),

                    bottomNavigationBar: _isDesktop
                        ? null
                        : NavigationBar(
                      selectedIndex: _i,
                      onDestinationSelected: (v) => setState(() => _i = v),
                      destinations: const [
                        NavigationDestination(
                            icon: Icon(Icons.dashboard), label: 'Home'),
                        NavigationDestination(
                            icon: Icon(Icons.people), label: 'Users'),
                        NavigationDestination(
                            icon: Icon(Icons.settings), label: 'Impostazioni'),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ResizeDivider extends StatelessWidget {
  final double width;
  final ValueChanged<double> onDelta;
  final VoidCallback onEnd;

  const _ResizeDivider({
    required this.width,
    required this.onDelta,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(
              width: 1,
              height: double.infinity,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
