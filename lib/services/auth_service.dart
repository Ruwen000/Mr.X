import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';
import '../models/role.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _fs;

  AuthService(this._fs);

  User? get user => _auth.currentUser;
  String? _gameUsername;
  Role? role;

  bool get hasUsername => _gameUsername?.isNotEmpty ?? false;
  String get username => _gameUsername ?? '';
  String get uid => user?.uid ?? '';

  Future<void> loadGameUsername() async {
    _gameUsername = await _fs.getUsername();
    notifyListeners();
  }

  Future<void> setGameUsername(String name) async {
    await _fs.setUsername(name);
    _gameUsername = name;
    notifyListeners();
  }

  void clearGameUsername() {
    _gameUsername = null;
    notifyListeners();
  }

  Future<void> login(String email, String pass) async {
    await _auth.signInWithEmailAndPassword(email: email, password: pass);
    await loadGameUsername();
  }

  Future<void> register(String email, String pass) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: pass);
    _gameUsername = null;
    await loadGameUsername();
  }

  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      await _auth.signInWithPopup(provider);
    } else {
      final googleUser = await GoogleSignIn(scopes: ['email']).signIn();
      if (googleUser == null) throw Exception('Google Sign-In abgebrochen');
      final googleAuth = await googleUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(cred);
    }
    await loadGameUsername();
  }

  Future<void> logout({required bool deleteData}) async {
    try {
      print('🔄 Starte Logout-Prozess...');

      if (deleteData) {
        print('📝 Lösche ALLE User-Daten...');
        await _fs.deleteUserData(isHunter: role == Role.hunter);
      } else {
        print('📝 Lösche nur Standort-Daten...');
        await _fs.deleteLocationOnly(isHunter: role == Role.hunter);
      }

      // Lokale Daten KOMPLETT zurücksetzen
      role = null;
      _gameUsername = null; // WICHTIG: Username lokal löschen

      print('🚪 Firebase SignOut...');
      await _auth.signOut();

      if (!kIsWeb) {
        print('🔐 Google SignOut...');
        await GoogleSignIn().signOut();
      }

      notifyListeners();
      print('✅ Logout abgeschlossen - Alle Daten gelöscht');
    } catch (e) {
      print('❌ Kritischer Fehler im Logout: $e');
      // Sicherstellen dass zumindest lokal alles gelöscht wird
      role = null;
      _gameUsername = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setRole(Role r) async {
    role = r;
    // Rolle in Firestore speichern
    await _db.collection('users').doc(uid).set({
      'role': r == Role.mrx ? 'mrx' : 'hunter',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    notifyListeners();
  }

  /// Nur die Rolle löschen
  void clearRole() {
    role = null;
    notifyListeners();
  }
}
