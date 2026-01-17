import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class DeepLinkService {
  static const _pendingLeagueIdKey = 'pending_league_id';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  String? extractLeagueIdFromUri(Uri uri) {
    final seg = uri.pathSegments;
    if (seg.length >= 2 && seg[0] == 'l') {
      final id = seg[1].trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  /// ✅ Start listening (mobile). Su web ci pensa RootGate via Uri.base.
  Future<void> startListening(void Function(String leagueId) onLeagueLink) async {
    if (kIsWeb) return;

    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      final id = extractLeagueIdFromUri(initial);
      if (id != null) onLeagueLink(id);
    }

    _sub = _appLinks.uriLinkStream.listen((uri) {
      final id = extractLeagueIdFromUri(uri);
      if (id != null) onLeagueLink(id);
    });
  }

  void dispose() => _sub?.cancel();

  Future<void> setPendingLeagueId(String leagueId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pendingLeagueIdKey, leagueId);
  }

  Future<String?> consumePendingLeagueId() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(_pendingLeagueIdKey);
    if (id != null) await sp.remove(_pendingLeagueIdKey);
    return id;
  }
}
