import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActiveLeagueService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  ActiveLeagueService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('Users').doc(uid);

  Future<void> ensureUserDocForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _userRef(user.uid);
    final snap = await ref.get();

    final email = (user.email ?? '').trim();
    final emailLower = email.toLowerCase();
    final providerUrl = (user.photoURL ?? '').trim();

    final existing = snap.data() ?? {};
    final existingPhoto = (existing['photoUrl'] ?? '').toString().trim();
    final hasUserPhoto = existingPhoto.isNotEmpty;

    if (!snap.exists) {
      // Primo ingresso: puoi inizializzare photoUrl col provider (fallback iniziale),
      // ma resta sempre modificabile dall’upload utente.
      await ref.set({
        'uid': user.uid,
        'email': email,
        'emailLower': emailLower,
        'displayName': user.displayName ?? '',
        if (providerUrl.isNotEmpty) 'providerPhotoUrl': providerUrl,
        if (providerUrl.isNotEmpty) 'photoUrl': providerUrl, // fallback solo alla creazione
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'activeLeagueId': '',
      }, SetOptions(merge: true));
    } else {
      // ✅ Login successivi: MAI sovrascrivere photoUrl se già c’è una foto utente
      final patch = <String, dynamic>{
        'email': email,
        'emailLower': emailLower,
        'displayName': (user.displayName ?? '').trim().isNotEmpty
            ? (user.displayName ?? '')
            : (existing['displayName'] ?? ''),
        'updatedAt': FieldValue.serverTimestamp(),
        if (providerUrl.isNotEmpty) 'providerPhotoUrl': providerUrl,
      };

      // ✅ Solo se NON esiste una foto profilo salvata dall’utente
      if (!hasUserPhoto && providerUrl.isNotEmpty) {
        patch['photoUrl'] = providerUrl;
      }

      await ref.set(patch, SetOptions(merge: true));
    }
  }


  Future<void> ensureActiveLeagueIsValid() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uSnap = await _userRef(user.uid).get();
    final data = uSnap.data() ?? {};
    final raw = data['activeLeagueId'];
    final activeLeagueId = (raw is String) ? raw.trim() : '';

    if (activeLeagueId.isEmpty) return;

    final leagueRef = _db.collection('Leagues').doc(activeLeagueId);
    final leagueSnap = await leagueRef.get();
    if (!leagueSnap.exists) {
      await clearActiveLeagueId();
      return;
    }

    final memRef = leagueRef.collection('members').doc(user.uid);
    final memSnap = await memRef.get();
    if (!memSnap.exists) {
      await clearActiveLeagueId();
      return;
    }
  }

  Future<void> setActiveLeagueId(String leagueId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userRef(user.uid).set({
      'activeLeagueId': leagueId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearActiveLeagueId() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userRef(user.uid).set({
      'activeLeagueId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ✅ Imposta activeLeagueId SOLO se l'utente è membro della lega.
  Future<bool> setActiveLeagueIfMember(String leagueId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final id = leagueId.trim();
    if (id.isEmpty) return false;

    final memRef = _db.collection('Leagues').doc(id).collection('members').doc(user.uid);
    final memSnap = await memRef.get();
    if (!memSnap.exists) return false;

    await setActiveLeagueId(id);
    return true;
  }




  /// Restituisce l'ID della lega attiva (o stringa vuota se non impostata)
  Future<String> getActiveLeagueId() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    final snap = await _userRef(user.uid).get();
    final data = snap.data();
    if (data == null) return '';

    final raw = data['activeLeagueId'];
    return (raw is String) ? raw.trim() : '';
  }

  static Future<String> getActiveLeagueIdStatic() async {
    final service = ActiveLeagueService();
    return await service.getActiveLeagueId();
  }




}
