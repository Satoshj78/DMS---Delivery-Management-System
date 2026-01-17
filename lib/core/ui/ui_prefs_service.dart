// lib/core/service/ui/ui_prefs_service.dart
// (preferenze di default delle 3 finestre a schermo largo: 'centerW': 867, 'leftCollapsed': false, 'leftW': 200, 'platform': 'web',)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UiPrefsService {
  UiPrefsService(this.db);
  final FirebaseFirestore db;

  static const defaultDesktopShell = <String, dynamic>{
    'centerW': 867,
    'leftCollapsed': false,
    'leftW': 200,
    'platform': 'web',
  };

  Future<Map<String, dynamic>> loadOrSeedDesktopShell({
    required String uid,
    required String clientId,
  }) async {
    final ref = db.collection('Users').doc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};

    final uiPrefs = (data['uiPrefs'] as Map?)?.cast<String, dynamic>() ?? {};
    final client = (uiPrefs[clientId] as Map?)?.cast<String, dynamic>() ?? {};
    final desktopShell = (client['desktopShell'] as Map?)?.cast<String, dynamic>();

    if (desktopShell == null) {
      final seeded = {
        ...defaultDesktopShell,
        'platform': kIsWeb ? 'web' : 'other',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await ref.set({
        'uiPrefs': {
          clientId: {
            'desktopShell': seeded,
          }
        }
      }, SetOptions(merge: true));

      return Map<String, dynamic>.from(seeded);
    }

    return Map<String, dynamic>.from(desktopShell);
  }

  Future<void> saveDesktopShell({
    required String uid,
    required String clientId,
    required Map<String, dynamic> desktopShell,
  }) async {
    final ref = db.collection('Users').doc(uid);

    await ref.set({
      'uiPrefs': {
        clientId: {
          'desktopShell': {
            ...desktopShell,
            'platform': kIsWeb ? 'web' : 'other',
            'updatedAt': FieldValue.serverTimestamp(),
          }
        }
      }
    }, SetOptions(merge: true));
  }
}
