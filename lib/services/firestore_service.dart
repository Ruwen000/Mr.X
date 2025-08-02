import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> setUsername(String username) async {
    await _db.collection('users').doc(_uid).set({
      'username': username,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> getUsername() async {
    final snap = await _db.collection('users').doc(_uid).get();
    if (!snap.exists) return null;
    return (snap.data()?['username'] as String?)?.trim();
  }

  Future<void> deleteUsername() async {
    await _db.collection('users').doc(_uid).delete();
  }

  Future<List<String>> getAllUsernames() async {
    final snap = await _db.collection('users').get();
    return snap.docs
        .map((d) => (d.data()['username'] ?? '') as String)
        .where((u) => u.isNotEmpty)
        .toList();
  }

  Future<void> sendLocation({
    required double lat,
    required double lng,
    required bool isHunter,
  }) async {
    final role = isHunter ? 'hunter' : 'mrx';
    final docId = isHunter ? _uid : 'mrx';
    await _db
        .collection('games')
        .doc('current')
        .collection(role)
        .doc(docId)
        .set({
      'lat': lat,
      'lng': lng,
      'ts': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendPing(double lat, double lng) async {
    await _db
        .collection('games')
        .doc('current')
        .collection('pings')
        .doc('latest')
        .set({
      'location': GeoPoint(lat, lng),
      'ts': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> pingStream() {
    return _db
        .collection('games')
        .doc('current')
        .collection('pings')
        .doc('latest')
        .snapshots();
  }

  Future<void> deleteUserData({required bool isHunter}) async {
    final role = isHunter ? 'hunter' : 'mrx';
    final docId = isHunter ? _uid : 'mrx';
    await _db
        .collection('games')
        .doc('current')
        .collection(role)
        .doc(docId)
        .delete();
    await deleteUsername();
  }

  Future<Map<String, LocationData>> getAllHunterLocations() async {
    final snap =
        await _db.collection('games').doc('current').collection('hunter').get();
    return {
      for (var doc in snap.docs)
        doc.id: LocationData.fromMap({
          'latitude': doc['lat'],
          'longitude': doc['lng'],
        })
    };
  }

  Future<LocationData?> getMrXLocation() async {
    final doc = await _db
        .collection('games')
        .doc('current')
        .collection('mrx')
        .doc('mrx')
        .get();
    if (!doc.exists) return null;
    return LocationData.fromMap({
      'latitude': doc['lat'],
      'longitude': doc['lng'],
    });
  }

  Future<void> deleteAllGameData() async {
    final batch = _db.batch();

    // 1) Alle Hunter-Dokumente löschen
    final hunterSnap =
        await _db.collection('games').doc('current').collection('hunter').get();
    for (var doc in hunterSnap.docs) {
      batch.delete(doc.reference);
    }

    // 2) Mr.X-Dokument löschen
    final mrxRef =
        _db.collection('games').doc('current').collection('mrx').doc('mrx');
    batch.delete(mrxRef);

    // 3) Alle Ping-Dokumente löschen
    final pingsSnap =
        await _db.collection('games').doc('current').collection('pings').get();
    for (var doc in pingsSnap.docs) {
      batch.delete(doc.reference);
    }

    // 4) Alle User-Profile löschen
    final usersSnap = await _db.collection('users').get();
    for (var doc in usersSnap.docs) {
      batch.delete(doc.reference);
    }

    // 5) Alle Lösch-Operationen in einem Rutsch ausführen
    await batch.commit();
  }

  Future<Map<String, Map<String, dynamic>>>
      getAllHunterLocationsWithNames() async {
    final hunterSnap =
        await _db.collection('games').doc('current').collection('hunter').get();
    final batch = await Future.wait(
        hunterSnap.docs.map((d) => _db.collection('users').doc(d.id).get()));
    final result = <String, Map<String, dynamic>>{};
    for (var doc in hunterSnap.docs) {
      final uid = doc.id;
      final lat = doc['lat'] as double?;
      final lng = doc['lng'] as double?;
      final userDoc = batch.firstWhere((u) => u.id == uid);
      final username = userDoc.data()?['username'] as String? ?? '—';
      if (lat != null && lng != null) {
        result[uid] = {
          'latitude': lat,
          'longitude': lng,
          'username': username,
        };
      }
    }
    return result;
  }

  Future<Map<String, dynamic>?> getMrXWithName() async {
    final doc = await _db
        .collection('games')
        .doc('current')
        .collection('mrx')
        .doc('mrx')
        .get();
    if (!doc.exists) return null;
    final lat = doc['lat'] as double?;
    final lng = doc['lng'] as double?;
    final userSnap = await _db.collection('users').doc('mrx').get();
    final username = userSnap.data()?['username'] as String? ?? 'Mr.X';
    if (lat != null && lng != null) {
      return {
        'latitude': lat,
        'longitude': lng,
        'username': username,
      };
    }
    return null;
  }

  Future<void> deleteLocationOnly({required bool isHunter}) async {
    final role = isHunter ? 'hunter' : 'mrx';
    final docId = isHunter ? _uid : 'mrx';
    await _db
        .collection('games')
        .doc('current')
        .collection(role)
        .doc(docId)
        .delete();
  }
}
