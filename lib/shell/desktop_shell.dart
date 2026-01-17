// lib/shell/desktop_shell.dart
// (sidebar collassabile + scorciatoie globali)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dms_app/core/widgets/shortcuts_help_dialog.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.pages,
    required this.destinations,
    required this.initialDesktopPrefs,
    required this.onDesktopPrefsChanged,
    this.initialIndex = 0,
  });

  final List<Widget> pages;
  final List<NavigationRailDestination> destinations;

  /// Deve contenere: leftW, centerW, leftCollapsed (e altri se vuoi)
  final Map<String, dynamic> initialDesktopPrefs;

  /// Chiamata debounced: salva su Firestore
  final ValueChanged<Map<String, dynamic>> onDesktopPrefsChanged;

  final int initialIndex;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _ToggleLeftNavIntent extends Intent {
  const _ToggleLeftNavIntent();
}

class _OpenHelpIntent extends Intent {
  const _OpenHelpIntent();
}

class _GoToNavIndexIntent extends Intent {
  const _GoToNavIndexIntent(this.index);
  final int index;
}

class _DesktopShellState extends State<DesktopShell> {
  static const double _collapsedRailW = 72;
  static const double _minLeftW = 180;
  static const double _maxLeftW = 380;

  late bool _leftCollapsed;
  late double _leftW;
  late double _centerW;

  late int _index;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _leftCollapsed = widget.initialDesktopPrefs['leftCollapsed'] == true;
    _leftW = (widget.initialDesktopPrefs['leftW'] ?? 200).toDouble();
    _centerW = (widget.initialDesktopPrefs['centerW'] ?? 867).toDouble();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      widget.onDesktopPrefsChanged({
        'leftCollapsed': _leftCollapsed,
        'leftW': _leftW.round(),
        'centerW': _centerW.round(),
      });
    });
  }

  void _toggleLeft() {
    setState(() => _leftCollapsed = !_leftCollapsed);
    _scheduleSave();
  }

  void _openHelp() {
    showShortcutsHelp(context);
  }

  void _goToIndex(int i) {
    if (i < 0 || i >= widget.pages.length) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Shortcuts globali
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.f1): const _OpenHelpIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.slash): const _OpenHelpIntent(),

      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB): const _ToggleLeftNavIntent(),

      // Alt+1..9
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit1): const _GoToNavIndexIntent(0),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit2): const _GoToNavIndexIntent(1),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit3): const _GoToNavIndexIntent(2),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit4): const _GoToNavIndexIntent(3),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit5): const _GoToNavIndexIntent(4),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit6): const _GoToNavIndexIntent(5),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit7): const _GoToNavIndexIntent(6),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit8): const _GoToNavIndexIntent(7),
      LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.digit9): const _GoToNavIndexIntent(8),
    };

    final actions = <Type, Action<Intent>>{
      _OpenHelpIntent: CallbackAction<_OpenHelpIntent>(onInvoke: (_) {
        _openHelp();
        return null;
      }),
      _ToggleLeftNavIntent: CallbackAction<_ToggleLeftNavIntent>(onInvoke: (_) {
        _toggleLeft();
        return null;
      }),
      _GoToNavIndexIntent: CallbackAction<_GoToNavIndexIntent>(onInvoke: (i) {
        _goToIndex(i.index);
        return null;
      }),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, c) {
              final railW = _leftCollapsed
                  ? _collapsedRailW
                  : _leftW.clamp(_minLeftW, _maxLeftW);

              return Row(
                children: [
                  // LEFT NAV
                  SizedBox(
                    width: railW,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: _leftCollapsed ? 'Espandi (Ctrl+B)' : 'Riduci (Ctrl+B)',
                                onPressed: _toggleLeft,
                                icon: Icon(_leftCollapsed ? Icons.chevron_right : Icons.chevron_left),
                              ),
                              if (!_leftCollapsed)
                                const Expanded(
                                  child: Text('DMS', style: TextStyle(fontWeight: FontWeight.w800)),
                                ),
                              IconButton(
                                tooltip: 'Guida (F1)',
                                onPressed: _openHelp,
                                icon: const Icon(Icons.help_outline),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: NavigationRail(
                            extended: !_leftCollapsed, // <-- qui: solo icone se false
                            selectedIndex: _index,
                            onDestinationSelected: (i) => _goToIndex(i),
                            destinations: widget.destinations,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // DRAG RESIZE (solo se espanso)
                  if (!_leftCollapsed)
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) {
                          setState(() {
                            _leftW = (_leftW + d.delta.dx).clamp(_minLeftW, _maxLeftW);
                            // centerW lo puoi usare se fai un layout a colonne multiple.
                            _centerW = _centerW;
                          });
                          _scheduleSave();
                        },
                        child: const SizedBox(width: 6),
                      ),
                    ),

                  // PAGE
                  Expanded(
                    child: IndexedStack(
                      index: _index,
                      children: widget.pages,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
