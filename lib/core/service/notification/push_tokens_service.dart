import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushTokensService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseMessaging _msg;

  StreamSubscription<String>? _tokenSub;

  PushTokensService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FirebaseMessaging? messaging,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _msg = messaging ?? FirebaseMessaging.instance;

  Future<void> ensurePermissionsAndSaveToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _msg.requestPermission(alert: true, badge: true, sound: true);

    final token = await _msg.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(user.uid, token);
    }

    // evita doppi listener
    await _tokenSub?.cancel();
    _tokenSub = _msg.onTokenRefresh.listen((t) async {
      final u = _auth.currentUser; // <-- prende sempre quello corrente
      if (u == null) return;
      if (t.isNotEmpty) await _saveToken(u.uid, t);
    });
  }

  Future<void> removeCurrentTokenForLogout() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // stop listener prima
    await _tokenSub?.cancel();
    _tokenSub = null;

    final token = await _msg.getToken();
    if (token != null && token.isNotEmpty) {
      await _db.doc('Users/${user.uid}/fcmTokens/$token').delete().catchError((_) {});
    }

    // invalida token sul device (consigliato)
    await _msg.deleteToken().catchError((_) {});
  }

  Future<void> _saveToken(String uid, String token) async {
    final ref = _db.doc('Users/$uid/fcmTokens/$token');
    await ref.set({
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'flutter',
      'lastSeenAt': FieldValue.serverTimestamp(), // utile in debug / cleanup
    }, SetOptions(merge: true));
  }
}
