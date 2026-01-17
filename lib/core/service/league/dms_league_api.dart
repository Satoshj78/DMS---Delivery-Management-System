import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DmsLeagueApi {
  final FirebaseFunctions _fnPrimary;
  final FirebaseFunctions _fnFallback;

  DmsLeagueApi({
    String region = 'europe-west1',
    String fallbackRegion = 'us-central1',
  })  : _fnPrimary = FirebaseFunctions.instanceFor(region: region),
        _fnFallback = FirebaseFunctions.instanceFor(region: fallbackRegion);

  Future<Map<String, dynamic>> _call(
      String name, [
        Map<String, dynamic>? data,
      ]) async {
    data ??= <String, dynamic>{};

    try {
      final res = await _fnPrimary.httpsCallable(name).call(data);
      final out = res.data;
      if (out is Map) return Map<String, dynamic>.from(out);
      return {'data': out};
    } on FirebaseFunctionsException catch (e) {
      // se la funzione non esiste in quella region, provo l’altra
      if (e.code == 'not-found') {
        final res = await _fnFallback.httpsCallable(name).call(data);
        final out = res.data;
        if (out is Map) return Map<String, dynamic>.from(out);
        return {'data': out};
      }
      rethrow;
    }
  }

  // ----------- API CALLABLES -----------
  Future<Map<String, dynamic>> listLeaguesForUser() {
    return _call('listLeaguesForUser');
  }

  Future<Map<String, dynamic>> requestJoinByCode({
    required String joinCode,
    String? notifyOwnersVia, // <-- aggiunto
  }) {
    final payload = <String, dynamic>{
      'joinCode': joinCode,
    };

    final v = (notifyOwnersVia ?? '').trim();
    if (v.isNotEmpty) {
      payload['notifyOwnersVia'] = v; // <-- lo invio solo se presente
    }

    return _call('requestJoinByCode', payload);
  }


  Future<Map<String, dynamic>> acceptInvite({
    required String leagueId,
    required String inviteId,
  }) {
    return _call('acceptInvite', {'leagueId': leagueId, 'inviteId': inviteId});
  }

  Future<Map<String, dynamic>> respondToJoinRequest({
    required String leagueId,
    required String requestId,
    required bool accept,
  }) {
    return _call('respondToJoinRequest', {
      'leagueId': leagueId,
      'requestId': requestId,
      'accept': accept,
    });
  }

  Future<Map<String, dynamic>> createLeague({
    required String nome,
    Uint8List? logoBytes,
  }) {
    return _call('createLeague', {
      'nome': nome,
      if (logoBytes != null) 'logoBase64': base64Encode(logoBytes),
    });
  }

  // ----------- HELPERS (Firestore) -----------
  Future<void> setActiveLeague({required String leagueId}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw Exception('Not signed in');

    await FirebaseFirestore.instance.collection('Users').doc(u.uid).set({
      'activeLeagueId': leagueId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
