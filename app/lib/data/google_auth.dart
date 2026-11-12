import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Login Google → Firebase Auth.
///
/// - Web: popup dari Firebase Auth (tidak butuh package google_sign_in).
/// - Android: pemilih akun native (Credential Manager). Butuh SHA-1/SHA-256 keystore
///   terdaftar di Firebase dan `google-services.json` yang berisi OAuth client web.
class GoogleAuth {
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// Mengembalikan null kalau pengguna membatalkan pemilihan akun.
  static Future<User?> signIn() async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
      try {
        return (await auth.signInWithPopup(provider)).user;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') return null;
        rethrow;
      }
    }

    await _init();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw Exception('Login Google gagal (${e.code.name}). ${e.description ?? ''}'.trim());
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Login Google gagal: token kosong.');
    return (await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))).user;
  }

  /// Keluar dari Firebase dan lupakan akun Google terpilih, supaya pemilih akun muncul lagi.
  static Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _init();
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
  }
}
