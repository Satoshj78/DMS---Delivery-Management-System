// lib/core/service/ui/client_id_store.dart
// Serve a creare una chiave stabile “per dispositivo” (così le uiPrefs restano separate per PC/browser diversi).

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ClientIdStore {
  static const _kKey = 'dms_client_id_v1';
  static const _uuid = Uuid();

  Future<String> getOrCreate() async {
    final sp = await SharedPreferences.getInstance();
    final existing = sp.getString(_kKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = _uuid.v4();
    await sp.setString(_kKey, id);
    return id;
  }
}
