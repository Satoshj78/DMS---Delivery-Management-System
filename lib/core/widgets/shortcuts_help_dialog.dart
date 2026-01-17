// lib/core/widgets/shortcuts_help_dialog.dart
// (guida in-app)

import 'package:flutter/material.dart';

class ShortcutItem {
  final String keys;
  final String action;
  const ShortcutItem(this.keys, this.action);
}

const kShortcuts = <String, List<ShortcutItem>>{
  'Globali': [
    ShortcutItem('F1', 'Apri guida scorciatoie'),
    ShortcutItem('Ctrl + /', 'Apri guida scorciatoie'),
    ShortcutItem('Ctrl + B', 'Collassa/Espandi barra sinistra'),
    ShortcutItem('Alt + 1..9', 'Vai alle sezioni principali'),
    ShortcutItem('Esc', 'Indietro / chiudi dialog'),
  ],
  'Liste (card)': [
    ShortcutItem('↑ / ↓', 'Seleziona card precedente/successiva'),
    ShortcutItem('Enter / Space', 'Apri card selezionata'),
    ShortcutItem('PageUp / PageDown', 'Scorrimento veloce'),
    ShortcutItem('Home / End', 'Prima/ultima card'),
  ],
  'Form / campi': [
    ShortcutItem('Tab / Shift+Tab', 'Campo successivo/precedente'),
    ShortcutItem('Enter', 'Prossimo campo (se configurato)'),
    ShortcutItem('Ctrl + Enter', 'Salva / conferma (azione principale)'),
  ],
};

Future<void> showShortcutsHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Guida tastiera'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final section in kShortcuts.entries) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(
                        section.key,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  for (final item in section.value)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              item.keys,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(child: Text(item.action)),
                        ],
                      ),
                    ),
                ],
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
