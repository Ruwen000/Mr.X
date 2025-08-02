import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firestore_service.dart';
import '../models/role.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
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

  /// Logout und Daten löschen
  Future<void> logout({required bool deleteData}) async {
    if (deleteData && role != null) {
      // löscht Spiel-Location und User-Dokument
      await _fs.deleteUserData(isHunter: role == Role.hunter);
    } else {
      // nur Username-Dokument löschen
      await _fs.deleteUsername();
    }
    role = null;
    _gameUsername = null;
    await _auth.signOut();
    if (!kIsWeb) await GoogleSignIn().signOut();
    notifyListeners();
  }

  void setRole(Role r) {
    role = r;
    notifyListeners();
  }

  /// Neu: Nur die Rolle löschen, Username/UID bleiben erhalten
  void clearRole() {
    role = null;
    notifyListeners();
  }
}
