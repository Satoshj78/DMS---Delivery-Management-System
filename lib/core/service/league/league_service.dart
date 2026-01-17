import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:dms_app/core/service/league/dms_league_api.dart';

class LeagueService {
  static final _db = FirebaseFirestore.instance;
  static final _api = DmsLeagueApi(region: 'europe-west1'); // <-- qui


  static Future<DocumentReference<Map<String, dynamic>>> _ensureUserDoc() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('User null');

    final ref = _db.collection('Users').doc(u.uid);
    await ref.set({
      'uid': u.uid,
      'email': u.email,
      'emailLower': (u.email ?? '').toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref;
  }

  /// ✅ CREA LEGA via Cloud Function
  /// Ritorna (leagueId, joinCode) come prima
  static Future<({String leagueId, String joinCode})> createLeague({
    required String leagueName,
    Uint8List? logoBytes,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('Not logged');

    final userRef = await _ensureUserDoc();

    final res = await _api.createLeague(
      nome: leagueName.trim(),
      logoBytes: logoBytes,
    );

    final leagueId = (res['leagueId'] ?? res['id'] ?? '').toString().trim();
    final joinCode = (res['joinCode'] ?? res['code'] ?? '').toString().trim().toUpperCase();

    if (leagueId.isEmpty) {
      throw StateError('createLeague: leagueId mancante nella risposta function');
    }


    // la function di solito lo fa già, ma è ok ribadirlo lato client su Users/{uid}
    await userRef.set({
      'activeLeagueId': leagueId,
      'leagueIds': FieldValue.arrayUnion([leagueId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return (leagueId: leagueId, joinCode: joinCode);
  }

  /// ✅ MODALITÀ 2: NON entra subito, invia richiesta
  /// ritorna la response della function (es: alreadyMember, alreadyRequested, leagueId, ...)
  static Future<Map<String, dynamic>> requestJoinByCode(String joinCode) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('Not logged');

    await _ensureUserDoc();

    final code = joinCode.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('Codice vuoto');

    final res = await _api.requestJoinByCode(joinCode: code, notifyOwnersVia: 'push');
    return res;
  }

  /// ✅ Se sei già membro, puoi SOLO impostare activeLeagueId sul tuo Users/{uid}
  /// (non tocchiamo members o league doc)
  static Future<void> enterLeagueById(String leagueId) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('Not logged');

    final userRef = await _ensureUserDoc();

    final id = leagueId.trim();
    if (id.isEmpty) throw ArgumentError('leagueId vuoto');

    await userRef.set({
      'activeLeagueId': id,
      'leagueIds': FieldValue.arrayUnion([id]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ✅ Accetta invito da:
  /// - "leagueId:inviteId"
  /// - "dms://invite?leagueId=...&inviteId=..."
  /// - "leagueId inviteId" (spazi / separatori)
  static Future<String> acceptInviteCode({required String code}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('Not logged');

    final userRef = await _ensureUserDoc();

    final raw = code.trim();
    if (raw.isEmpty) throw ArgumentError('Codice invito vuoto');

    final parsed = _parseInvite(code: raw);
    if (parsed == null) {
      throw ArgumentError(
        'Formato invito non valido.\n'
            'Usa "leagueId:inviteId" oppure un link tipo "dms://invite?leagueId=...&inviteId=...".',
      );
    }

    final leagueId = parsed.$1;
    final inviteId = parsed.$2;

    final res = await _api.acceptInvite(leagueId: leagueId, inviteId: inviteId);
    final outLeagueId = (res['leagueId'] ?? leagueId).toString().trim();
    if (outLeagueId.isEmpty) throw StateError('acceptInvite: leagueId mancante');

    await userRef.set({
      'activeLeagueId': outLeagueId,
      'leagueIds': FieldValue.arrayUnion([outLeagueId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return outLeagueId;
  }

  /// Ritorna (leagueId, inviteId) oppure null
  static (String, String)? _parseInvite({required String code}) {
    final t = code.trim();
    if (t.isEmpty) return null;

    // 1) URI: dms://invite?leagueId=...&inviteId=...
    final uri = Uri.tryParse(t);
    if (uri != null) {
      final qp = uri.queryParameters;
      final leagueId = (qp['leagueId'] ?? qp['league'] ?? '').trim();
      final inviteId = (qp['inviteId'] ?? qp['invite'] ?? qp['viteId'] ?? '').trim();
      if (leagueId.isNotEmpty && inviteId.isNotEmpty) {
        return (leagueId, inviteId);
      }
    }

    // 2) "leagueId:inviteId"
    if (t.contains(':') && !t.contains('://')) {
      final parts = t.split(':').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length >= 2) {
        final leagueId = parts[0];
        final inviteId = parts[1];
        if (leagueId.isNotEmpty && inviteId.isNotEmpty) return (leagueId, inviteId);
      }
    }

    // 3) fallback: "leagueId inviteId" / separatori vari
    final parts = t
        .split(RegExp(r'[\|\;\,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.length >= 2) {
      final leagueId = parts[0];
      final inviteId = parts[1];
      if (leagueId.isNotEmpty && inviteId.isNotEmpty) return (leagueId, inviteId);
    }

    return null;
  }


  static Future<void> clearActiveLeague() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    await _db.collection('Users').doc(u.uid).set(
      {'activeLeagueId': null},
      SetOptions(merge: true),
    );
  }
}
