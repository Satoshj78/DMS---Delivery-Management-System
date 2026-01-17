import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  // ---------------------------
  // EMAIL / PASSWORD
  // ---------------------------
  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential> signUpWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  }

  /// ✅ Password reset (web-safe): se passi continueUrl -> redirect dopo reset.
  Future<void> sendPasswordReset(
      String email, {
        String? continueUrl,
      }) {
    final e = email.trim();

    if (continueUrl == null || continueUrl.trim().isEmpty) {
      return _auth.sendPasswordResetEmail(email: e);
    }

    final settings = ActionCodeSettings(
      url: continueUrl.trim(),
      handleCodeInApp: false,
    );

    return _auth.sendPasswordResetEmail(
      email: e,
      actionCodeSettings: settings,
    );
  }

  // ---------------------------
  // GOOGLE (v7+)
  // ---------------------------
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      try {
        return await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') {
          return null;
        }
        rethrow;
      }
    }

    final g = GoogleSignIn.instance;
    await g.initialize();

    try {
      final account = await g.authenticate();

      final googleAuth = account.authentication; // v7: sync
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;

      final msg = e.toString().toLowerCase();
      if (msg.contains('no credential')) return null;

      rethrow;
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('canceled') || code.contains('cancel')) return null;
      rethrow;
    }
  }

  /*


  // PER ABILITARE FACEBOOK TOGLI IL COMMENTO  qui e in AUTH PAGE e inserisci: flutter_facebook_auth: ^7.1.2 nel PUBSPEK.YAML

  // ---------------------------
  // FACEBOOK
  // ---------------------------
  Future<UserCredential> signInWithFacebook() async {
    if (kIsWeb) {
      final provider = FacebookAuthProvider()
        ..addScope('email')
        ..addScope('public_profile');
      return _auth.signInWithPopup(provider);
    }

    final result = await FacebookAuth.instance.login(
      permissions: const ['email', 'public_profile'],
    );

    if (result.status != LoginStatus.success || result.accessToken == null) {
      throw FirebaseAuthException(
        code: 'facebook-login-failed',
        message: 'Facebook login fallito: ${result.status}',
      );
    }

    final credential = FacebookAuthProvider.credential(
      result.accessToken!.tokenString,
    );

    return _auth.signInWithCredential(credential);
  }


   */

  // ---------------------------
  // APPLE
  // ---------------------------
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) => sha256.convert(utf8.encode(input)).toString();

  /// iOS: ok
  /// Web: popup (apple.com)
  /// Android: funziona SOLO se configuri webAuthenticationOptions (Service ID + Redirect)
  Future<UserCredential> signInWithApple({
    String? webClientId,
    Uri? webRedirectUri,
  }) async {
    if (kIsWeb) {
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
      return _auth.signInWithPopup(provider);
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
      webAuthenticationOptions: (webClientId != null && webRedirectUri != null)
          ? WebAuthenticationOptions(clientId: webClientId, redirectUri: webRedirectUri)
          : null,
    );

    final oauth = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
    );

    return _auth.signInWithCredential(oauth);
  }

  // ---------------------------
  // LOGOUT + reset activeLeagueId
  // ---------------------------

  /// ✅ Soluzione B: alias per compatibilità con chi chiama "logout()"
  Future<void> logout({bool clearActiveLeague = true}) {
    return signOut(clearActiveLeague: clearActiveLeague);
  }

  Future<void> signOut({bool clearActiveLeague = true}) async {
    final uid = _auth.currentUser?.uid;

    if (clearActiveLeague && uid != null) {
      await _db.collection('Users').doc(uid).set(
        {'activeLeagueId': null, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }

    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}

      // PER ABILITARE FACEBOOK TOGLIU IL COMMENTO
/*
      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {}

*/
    }

    await _auth.signOut();
  }




  /// Restituisce l'UID dell'utente autenticato corrente (o stringa vuota se non loggato)
  static String get currentUid {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? '';
  }




}
