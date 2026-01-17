// lib/core/widgets/keyboard_selectable_list.dart
// KeyboardSelectableList: ListView navigabile da tastiera (↑ ↓ Enter) con autoscroll e focus automatico.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef KeyboardSelectableItemBuilder = Widget Function(
    BuildContext context,
    int index,
    bool kbdSelected,
    );

class KeyboardSelectableList extends StatefulWidget {
  final FocusNode focusNode;
  final ScrollController scrollController;
  final int itemCount;
  final KeyboardSelectableItemBuilder itemBuilder;

  /// Chiamata quando premi Enter sull’elemento selezionato.
  final Future<void> Function(int index)? onActivate;

  /// Altezza stimata (px) per autoscroll “a stima”.
  final double estimatedItemExtent;

  /// Se true, prova a prendere focus subito.
  final bool autofocus;

  /// Indice iniziale selezionato.
  final int initialIndex;

  const KeyboardSelectableList({
    super.key,
    required this.focusNode,
    required this.scrollController,
    required this.itemCount,
    required this.itemBuilder,
    this.onActivate,
    this.estimatedItemExtent = 96,
    this.autofocus = false,
    this.initialIndex = 0,
  });

  @override
  State<KeyboardSelectableList> createState() => _KeyboardSelectableListState();
}

class _KeyboardSelectableListState extends State<KeyboardSelectableList> {
  int _selected = 0;

  int _clampIndex(int i) {
    if (widget.itemCount <= 0) return 0;
    return i.clamp(0, widget.itemCount - 1);
  }

  @override
  void initState() {
    super.initState();
    _selected = _clampIndex(widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant KeyboardSelectableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) {
      setState(() => _selected = _clampIndex(_selected));
    }
  }

  void _requestFocusIfNeeded() {
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }
  }

  void _setSelected(int next) {
    final clamped = _clampIndex(next);
    if (clamped == _selected) return;
    setState(() => _selected = clamped);
    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!widget.scrollController.hasClients) return;

    final pos = widget.scrollController.position;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;

    final itemH = widget.estimatedItemExtent;
    final itemTop = _selected * itemH;
    final itemBottom = itemTop + itemH;

    double? target;
    if (itemTop < viewTop) {
      target = itemTop;
    } else if (itemBottom > viewBottom) {
      target = itemBottom - pos.viewportDimension;
    }

    if (target == null) return;

    final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    widget.scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  Future<void> _activateSelected() async {
    final cb = widget.onActivate;
    if (cb == null) return;
    if (widget.itemCount <= 0) return;
    await cb(_selected);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.itemCount <= 0) return KeyEventResult.ignored;

    // gestiamo pressioni e repeat
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _setSelected(_selected + 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _setSelected(_selected - 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _activateSelected();
      return KeyEventResult.handled;
    }

    // opzionali utili
    if (key == LogicalKeyboardKey.home) {
      _setSelected(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _setSelected(widget.itemCount - 1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _requestFocusIfNeeded(),
        child: ListView.builder(
          controller: widget.scrollController,
          itemCount: widget.itemCount,
          itemBuilder: (context, i) {
            final selected = i == _selected;
            return widget.itemBuilder(context, i, selected);
          },
        ),
      ),
    );
  }
}
