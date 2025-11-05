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
    try {
      // Lösche das gesamte User-Dokument, nicht nur das username Feld
      await _db.collection('users').doc(_uid).delete();
      print('✅ User-Dokument komplett gelöscht: $_uid');
    } catch (e) {
      print('❌ Fehler beim Löschen des User-Dokuments: $e');
      throw e;
    }
  }

  Future<List<String>> getAllUsernames() async {
    try {
      final snap = await _db.collection('users').get();
      final usernames = snap.docs
          .map((d) => (d.data()['username'] ?? '') as String)
          .where((u) => u.isNotEmpty)
          .toList();

      print('📊 Gefundene Usernamen: $usernames');
      return usernames;
    } catch (e) {
      print('❌ Fehler beim Abrufen der Usernamen: $e');
      return [];
    }
  }

  Future<void> _deleteCollection(String collectionPath) async {
    try {
      final snapshot = await _db.collection(collectionPath).get();
      final batch = _db.batch();

      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print(
          '✅ Collection gelöscht: $collectionPath (${snapshot.docs.length} Dokumente)');
    } catch (e) {
      print('❌ Fehler beim Löschen der Collection $collectionPath: $e');
      rethrow;
    }
  }

  Future<void> sendLocation({
    required double lat,
    required double lng,
    required bool isHunter,
  }) async {
    try {
      final field = isHunter ? 'hunters' : 'mrx';
      final username = await getUsername() ?? 'Unknown';

      print(
          '🔄 Sende Location an Firebase: $lat, $lng für ${isHunter ? "Hunter" : "Mr.X"}');

      await _db.collection('games').doc('current').set({
        field: {
          _uid: {
            'lat': lat,
            'lng': lng,
            'username': username,
            'userId': _uid,
            'ts': FieldValue.serverTimestamp(),
          }
        }
      }, SetOptions(merge: true));

      print('✅ Location erfolgreich an Firebase gesendet für $field/$_uid');
    } catch (e) {
      print('❌ Fehler beim Senden der Location an Firebase: $e');
      throw e;
    }
  }

// Einmaliges Lesen aller Positionen
  Future<Map<String, dynamic>> getAllPositions() async {
    final doc = await _db.collection('games').doc('current').get();
    if (!doc.exists) return {};
    return doc.data() ?? {};
  }

  Future<void> sendPing(double lat, double lng) async {
    try {
      await _db
          .collection('games')
          .doc('current')
          .collection('pings')
          .doc('latest')
          .set({
        'location': GeoPoint(lat, lng),
        'userId': _uid,
        'timestamp':
            FieldValue.serverTimestamp(), // Konsistent mit getLatestValidPing
        'isValid': true,
      });
    } catch (e) {
      print('❌ Fehler beim Senden des Pings: $e');
      throw e;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> pingStream() {
    return _db
        .collection('games')
        .doc('current')
        .collection('pings')
        .doc('latest')
        .snapshots();
  }

  Future<Map<String, dynamic>?> getLatestValidPing() async {
    try {
      final doc = await _db
          .collection('games')
          .doc('current')
          .collection('pings')
          .doc('latest')
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final timestamp = data['timestamp'] as Timestamp?; // Korrektes Feld
      final location = data['location'] as GeoPoint?;

      if (timestamp == null || location == null) return null;

      final now = DateTime.now();
      final pingTime = timestamp.toDate();

      // Nur Pings der letzten 10 Minuten zurückgeben
      if (now.difference(pingTime).inMinutes <= 1) {
        return {'location': location, 'timestamp': timestamp, 'isValid': true};
      }

      return null;
    } catch (e) {
      print('❌ Fehler in getLatestValidPing: $e');
      return null;
    }
  }

  Future<void> deleteUserData({required bool isHunter}) async {
    try {
      print(
          '🗑️ Lösche ALLE User-Daten für ${isHunter ? 'Hunter' : 'Mr.X'}...');

      // 1. Lösche Standort-Daten
      await deleteLocationOnly(isHunter: isHunter);

      // 2. Lösche User-Dokument KOMPLETT (nicht nur Username)
      await _db.collection('users').doc(_uid).delete();

      // 3. Lösche auch aus der Auth-Service Liste (falls vorhanden)
      print('✅ User-Dokument komplett gelöscht: $_uid');
    } catch (e) {
      print('❌ Fehler beim Löschen der User-Daten: $e');

      // Fallback: Versuche zumindest Username zu löschen
      try {
        await _db.collection('users').doc(_uid).delete();
      } catch (e2) {
        print('❌ Auch Fallback-Löschung fehlgeschlagen: $e2');
      }

      throw e;
    }
  }

  Future<bool> isMrXActive() async {
    try {
      final gameDoc = await _db.collection('games').doc('current').get();
      if (!gameDoc.exists) return false;

      final gameData = gameDoc.data()!;
      final mrxData = gameData['mrx'] as Map<String, dynamic>?;

      final isActive = mrxData != null && mrxData.isNotEmpty;
      print('🎯 Mr.X Aktivitätsprüfung: $isActive (Daten: $mrxData)');

      return isActive;
    } catch (e) {
      print('❌ Fehler in isMrXActive: $e');
      return false;
    }
  }

  Future<String?> getMrXUsername() async {
    try {
      // Finde den Mr.X User und gebe seinen Username zurück
      final usersSnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'mrx')
          .limit(1)
          .get();

      if (usersSnap.docs.isEmpty) return null;

      return usersSnap.docs.first.data()['username'] as String?;
    } catch (e) {
      print('Fehler beim Abrufen des Mr.X Usernames: $e');
      return null;
    }
  }

  Future<Map<String, LocationData>> getAllHunterLocations() async {
    try {
      final gameDoc = await _db.collection('games').doc('current').get();
      if (!gameDoc.exists) return {};

      final gameData = gameDoc.data()!;
      final huntersData = gameData['hunters'] as Map<String, dynamic>? ?? {};

      final result = <String, LocationData>{};

      for (var entry in huntersData.entries) {
        final hunterId = entry.key;
        final hunterData = entry.value as Map<String, dynamic>;

        final lat = hunterData['lat'] as double?;
        final lng = hunterData['lng'] as double?;

        if (lat != null && lng != null) {
          result[hunterId] = LocationData.fromMap({
            'latitude': lat,
            'longitude': lng,
          });
        }
      }

      print('📍 Gefundene Hunter-Positionen: ${result.length}');
      return result;
    } catch (e) {
      print('❌ Fehler in getAllHunterLocations: $e');
      return {};
    }
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
    try {
      print('🔄 Starte Löschvorgang für ALLE Spieldaten...');

      // 1. Lösche zuerst alle Subcollections unter 'games/current'
      await _deleteSubcollections('games/current');

      // 2. Lösche das gesamte Spiel-Dokument
      await _db.collection('games').doc('current').delete();
      print('✅ Spiel-Dokument gelöscht');

      // 3. Setze alle User-Rollen zurück (aber lösche nicht die User!)
      final usersSnap = await _db.collection('users').get();
      final batch = _db.batch();

      for (var doc in usersSnap.docs) {
        batch.update(doc.reference, {
          'role': FieldValue.delete(),
        });
      }

      await batch.commit();
      print('✅ User-Rollen zurückgesetzt: ${usersSnap.docs.length} User');

      print('✅ ALLE Spieldaten erfolgreich gelöscht!');
    } catch (e) {
      print('❌ Fehler beim Löschen aller Daten: $e');

      // Fallback: Einzelne Löschvorgänge
      try {
        await _deleteSubcollections('games/current');
        await _db.collection('games').doc('current').delete();
        print('✅ Fallback-Löschung erfolgreich');
      } catch (e2) {
        print('❌ Auch Fallback fehlgeschlagen: $e2');
      }

      rethrow;
    }
  }

  Future<void> _deleteSubcollections(String documentPath) async {
    try {
      print('🗑️ Lösche Subcollections unter: $documentPath');

      // Hole alle Collections unter diesem Dokument
      final collections = await _db.doc(documentPath).collection('pings').get();

      // Lösche alle Dokumente in der pings Subcollection
      final batch = _db.batch();
      for (var doc in collections.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print(
          '✅ Subcollections gelöscht: ${collections.docs.length} Pings unter $documentPath');
    } catch (e) {
      print('❌ Fehler beim Löschen der Subcollections: $e');
      // Wir werfen den Fehler nicht weiter, da das Hauptdokument trotzdem gelöscht werden soll
    }
  }

  Future<Map<String, Map<String, dynamic>>>
      getAllHunterLocationsWithNames() async {
    try {
      final gameDoc = await _db.collection('games').doc('current').get();
      if (!gameDoc.exists) {
        print('❌ Kein Spiel-Dokument gefunden');
        return {};
      }

      final gameData = gameDoc.data()!;
      final huntersData = gameData['hunters'] as Map<String, dynamic>? ?? {};

      print('📍 Raw Hunters Data: $huntersData');

      final result = <String, Map<String, dynamic>>{};

      for (var entry in huntersData.entries) {
        final hunterId = entry.key;
        final hunterData = entry.value as Map<String, dynamic>;

        final lat = hunterData['lat'] as double?;
        final lng = hunterData['lng'] as double?;
        final username = hunterData['username'] as String? ?? 'Unknown';

        if (lat != null && lng != null) {
          result[hunterId] = {
            'latitude': lat,
            'longitude': lng,
            'username': username,
          };
          print('🎯 Hunter gefunden: $username ($lat, $lng)');
        } else {
          print('⚠️ Ungültige Hunter-Daten für $hunterId: lat=$lat, lng=$lng');
        }
      }

      print('✅ Hunter-Positionen mit Namen: ${result.length} gefunden');
      return result;
    } catch (e) {
      print('❌ Fehler in getAllHunterLocationsWithNames: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>?> getMrXWithName() async {
    try {
      final gameDoc = await _db.collection('games').doc('current').get();
      if (!gameDoc.exists) return null;

      final gameData = gameDoc.data()!;
      final mrxData = gameData['mrx'] as Map<String, dynamic>?;

      if (mrxData == null) return null;

      // Nehme den ersten Mr.X Eintrag (sollte nur einen geben)
      final mrxEntry = mrxData.entries.first;
      final mrxUserData = mrxEntry.value as Map<String, dynamic>;

      final lat = mrxUserData['lat'] as double?;
      final lng = mrxUserData['lng'] as double?;
      final username = mrxUserData['username'] as String? ?? 'Mr.X';

      if (lat != null && lng != null) {
        return {
          'latitude': lat,
          'longitude': lng,
          'username': username,
        };
      }
      return null;
    } catch (e) {
      print('❌ Fehler in getMrXWithName: $e');
      return null;
    }
  }

  Future<void> deleteLocationOnly({required bool isHunter}) async {
    try {
      final field = isHunter ? 'hunters' : 'mrx';

      await _db.collection('games').doc('current').set({
        field: {_uid: FieldValue.delete()}
      }, SetOptions(merge: true));

      print('✅ Location gelöscht für $field/$_uid');
    } catch (e) {
      print('❌ Fehler beim Löschen der Location: $e');
      throw e;
    }
  }
}
