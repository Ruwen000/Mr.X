import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:mr_x_app/services/background_service.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Vibe {
  static const MethodChannel _channel = MethodChannel('app.channel.vibration');
  static Future<void> vibrate({int duration = 500}) async {
    try {
      await _channel.invokeMethod('vibrate', {'duration': duration});
    } on PlatformException {
      // ignore
    }
  }
}

class BackgroundService {
  static Future<void> startMrXBackgroundService() async {
    try {
      const MethodChannel channel =
          MethodChannel('com.example.mr_x_app/background');
      await channel.invokeMethod('startMrXBackgroundService');
      print('✅ Mr.X Background Service gestartet');
    } catch (e) {
      print('⚠️ Background Service nicht verfügbar: $e');
      // Kein Fehler werfen - App soll trotzdem funktionieren
    }
  }

  static Future<void> stopMrXBackgroundService() async {
    try {
      const MethodChannel channel =
          MethodChannel('com.example.mr_x_app/background');
      await channel.invokeMethod('stopMrXBackgroundService');
      print('✅ Mr.X Background Service gestoppt');
    } catch (e) {
      print('⚠️ Background Service nicht verfügbar: $e');
    }
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FirestoreService _fs = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final List<Marker> _markers = [];
  LatLng? _center;
  late final MapController _mapController;

  LatLng? _lastSentPosition;
  Timer? _refreshTimer;

  Timer? _countdownTimer;
  Duration _timeUntilNextPing = Duration.zero;
  DateTime? _nextPingTime;

  DateTime? _lastSuccessfulPingMrX;
  int _failedAttemptsMrX = 0;

  Timer? _timerMyLoc, _timerHunters, _timerMrXNotify, _cooldownTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pingSub;

  late final Role _role;
  late final String _uid;

  bool _isMrXActive = false;
  Timer? _mrXStatusTimer;

  DateTime? _lastPingTime;
  LatLng? _lastPingPos;
  bool _showPulse = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  bool _abilityUsed = false;
  int _cooldown = 0;

  bool _backgroundServiceRunning = false;

  // Berechne nächsten Ping-Zeitpunkt
// KORRIGIERT: _calculateNextPingTime
  void _calculateNextPingTime() {
    if (_lastPingTime == null || !_isMrXActive) {
      _nextPingTime = null;
      _timeUntilNextPing = Duration.zero;
      return;
    }

    // ✅ KORREKT: Nächster Ping ist 1 Minute nach letztem Ping
    _nextPingTime = _lastPingTime!.add(const Duration(minutes: 1));
    final now = DateTime.now();

    if (_nextPingTime!.isAfter(now)) {
      _timeUntilNextPing = _nextPingTime!.difference(now);
    } else {
      _timeUntilNextPing = Duration.zero;
      // ✅ Ping ist überfällig - prüfe ob Mr.X noch aktiv
      if (_role == Role.hunter && mounted) {
        _checkMrXActivity();
      }
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _calculateNextPingTime();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_timeUntilNextPing.inSeconds > 0) {
          _timeUntilNextPing = _timeUntilNextPing - const Duration(seconds: 1);
        } else {
          _timeUntilNextPing = Duration.zero;
          // Wenn Countdown abgelaufen, neu berechnen (falls Ping noch nicht kam)
          _calculateNextPingTime();
        }
      });
    });
  }

  Future<void> _checkMrXActivity() async {
    try {
      final mrxData = await _fs.getMrXWithName();
      if (mrxData == null) {
        // Mr.X ist nicht mehr aktiv
        if (mounted) {
          setState(() {
            _nextPingTime = null;
            _timeUntilNextPing = Duration.zero;
          });
        }
      }
    } catch (e) {
      debugPrint('Fehler beim Prüfen der Mr.X Aktivität: $e');
    }
  }

  Future<void> _checkInitialPing() async {
    try {
      final pingData = await _fs.getLatestValidPing();
      if (pingData != null) {
        final geo = pingData['location'] as GeoPoint;
        final timestamp = pingData['timestamp'] as Timestamp;
        final isValid = pingData['isValid'] as bool;
        final pos = LatLng(geo.latitude, geo.longitude);
        final pingTime = timestamp.toDate();

        // ✅ Nur anzeigen wenn gültig
        if (isValid) {
          _updateMrXMarker(pos);

          if (mounted) {
            setState(() {
              _lastPingTime = pingTime;
              _lastPingPos = pos;
            });
            _startCountdownTimer();
          }
        }
      }
    } catch (e) {
      debugPrint("Fehler beim Laden des initialen Pings: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    print('🎯 INIT STATE STARTED - Mr.X Map Screen');

    _mapController = MapController();
    final auth = context.read<AuthService>();
    _role = auth.role!;
    _uid = auth.uid;

    print('🔐 Rolle: $_role, UID: $_uid');

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // ✅ VERBESSERT: Timer SOFORT starten (nicht erst nach _initializeMap)
    print('🔄 Starte Systeme...');

    // 1. Mr.X Status Checker für ALLE Rollen starten
    _startMrXStatusChecker();
    print('✅ Mr.X Status Checker gestartet');

    // 2. Rollenspezifische Systeme SOFORT starten
    if (_role == Role.hunter) {
      print('🎯 Starte Hunter-Systeme...');
      _setupPingStream();
    } else if (_role == Role.mrx) {
      print('🎭 Starte Mr.X-Systeme...');
      _startMrXTimer(); // ✅ WICHTIG: Timer SOFORT starten
      _startBackgroundService();
    }

    // 3. Dann Map initialisieren (asynchron)
    print('🗺️ Starte Map-Initialisierung...');
    _initializeMap().then((_) {
      if (mounted) {
        print('✅ Map-Initialisierung abgeschlossen');

        // 4. Nach Map-Init: Zusätzliche Hunter-Checks
        if (_role == Role.hunter) {
          _checkInitialPing();
        }

        // ✅ SICHERHEITS-FALLBACK: Prüfe ob Mr.X Timer wirklich läuft
        if (_role == Role.mrx &&
            (_timerMrXNotify == null || !_timerMrXNotify!.isActive)) {
          print('🔄 SICHERHEIT: Starte Mr.X Timer in Callback...');
          _startMrXTimer();
        }
      }
    }).catchError((e) {
      print('❌ Fehler in Map-Initialisierung: $e');
      // ✅ SICHERHEITS-FALLBACK: Stelle sicher, dass Timer laufen
      if (mounted && _role == Role.mrx) {
        print('🔄 Fallback: Starte Mr.X Timer nach Fehler...');
        _startMrXTimer();
      }
    });
  }

  void _startBackgroundService() async {
    try {
      await BackgroundService.startMrXBackgroundService();
      if (mounted) {
        setState(() {
          _backgroundServiceRunning = true;
        });
      }
      print('✅ Mr.X Background Service aktiv');
    } catch (e) {
      print('❌ Background Service konnte nicht gestartet werden: $e');
    }
  }

  void _stopBackgroundService() async {
    try {
      await BackgroundService.stopMrXBackgroundService();
      if (mounted) {
        setState(() {
          _backgroundServiceRunning = false;
        });
      }
      print('✅ Mr.X Background Service gestoppt');
    } catch (e) {
      print('❌ Background Service konnte nicht gestoppt werden: $e');
    }
  }

  void _setupPingStream() {
    _pingSub = _fs.pingStream().listen((docSnap) {
      if (!docSnap.exists) return;

      final data = docSnap.data();
      final geo = data?['location'] as GeoPoint?;
      final timestamp = data?['timestamp'] as Timestamp?;

      if (geo == null || timestamp == null) return;

      final pingTime = timestamp.toDate();
      final now = DateTime.now();

      // ✅ KONSISTENT: Gleiche Validitätsprüfung wie in getLatestValidPing
      if (now.difference(pingTime).inMinutes <= 1) {
        // 10 Minuten wie in FirestoreService
        final pos = LatLng(geo.latitude, geo.longitude);

        if (mounted) {
          setState(() {
            _lastPingTime = pingTime;
            _lastPingPos = pos;
            _isMrXActive = true; // ✅ Mr.X ist aktiv wenn gültiger Ping kommt
          });
          _startCountdownTimer();
        }

        _updateMrXMarker(pos);
        _handleVibeAndPing(pos);
      }
    });
  }

  void _startMrXStatusChecker() {
    _mrXStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;

      try {
        final isActive = await _fs.isMrXActive();
        if (mounted) {
          setState(() {
            _isMrXActive = isActive;
          });
        }

        // ✅ WICHTIG: Wenn Mr.X inaktiv, alle Mr.X Daten zurücksetzen
        if (!isActive && _role == Role.hunter) {
          if (mounted) {
            setState(() {
              _nextPingTime = null;
              _timeUntilNextPing = Duration.zero;
              _lastPingTime = null;
              _lastPingPos = null;
            });
            // Mr.X Marker entfernen
            _markers.removeWhere((m) => m.key == const ValueKey('mrx'));
          }
        }

        // ✅ Für Mr.X: Prüfen ob Rolle noch aktiv
        if (_role == Role.mrx) {
          final auth = context.read<AuthService>();
          if (auth.role != Role.mrx) {
            _timerMrXNotify?.cancel();
          }
        }
      } catch (e) {
        print('❌ Fehler im Mr.X Status Check: $e');
      }
    });
  }

  // Formatierung für die Ping-Zeit
  String _formatPingTime(DateTime pingTime) {
    return DateFormat('HH:mm:ss').format(pingTime); // z.B. "14:30:25"
  }

  // Formatierung für Countdown
  String _formatCountdown(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _checkLastPingTime() async {
    try {
      final pingData = await _fs.getLatestValidPing();
      if (pingData != null && pingData['isValid'] == true) {
        final timestamp = pingData['timestamp'] as Timestamp;
        final geo = pingData['location'] as GeoPoint;
        final pos = LatLng(geo.latitude, geo.longitude);

        if (mounted) {
          setState(() {
            _lastPingTime = timestamp.toDate();
            _lastPingPos = pos;
          });
        }
        debugPrint('🔄 Ping-Zeit synchronisiert: ${_lastPingTime}');
      }
    } catch (e) {
      debugPrint('Fehler beim Synchronisieren der Ping-Zeit: $e');
    }
  }

  void _startMrXTimer() {
    print('🔄 _startMrXTimer: Starte Timer...');

    // ✅ Zuerst alten Timer stoppen
    _timerMrXNotify?.cancel();

    print('🎯 Mr.X User ID: $_uid');
    print('📱 Widget mounted: $mounted');

    _timerMrXNotify = Timer.periodic(
      const Duration(minutes: 1), // 1 Minute
      (Timer timer) async {
        try {
          print('⏰ Mr.X Timer CALLBACK aufgerufen um ${DateTime.now()}');

          if (!mounted) {
            print('❌ Timer: Widget nicht mounted, breche ab');
            timer.cancel();
            return;
          }

          // ✅ Sicherheitsprüfung: Nur wenn Mr.X noch aktiv
          final auth = Provider.of<AuthService>(context, listen: false);
          if (auth.role != Role.mrx) {
            print('❌ Timer: Mr.X Rolle nicht aktiv, breche ab');
            timer.cancel();
            return;
          }

          print('🔄 Mr.X Timer AUSGEFÜHRT um ${DateTime.now()}');
          await _sendMrXPingWithRetry();
        } catch (e) {
          print('❌ Unerwarteter Fehler im Mr.X Timer: $e');
        }
      },
    );

    print('✅ Mr.X Timer GESTARTET - nächster Ping in 1 Minute');
    print('📊 Timer aktiv: ${_timerMrXNotify?.isActive}');

    // ✅ Zusätzliche Sicherheitsprüfung nach 3 Sekunden
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _role == Role.mrx) {
        print('🔍 Timer Status Check: Aktiv = ${_timerMrXNotify?.isActive}');
        if (_timerMrXNotify == null || !_timerMrXNotify!.isActive) {
          print('🔄 Timer war nicht aktiv - starte neu...');
          _startMrXTimer();
        }
      }
    });
  }

  Future<void> _sendMrXPingWithRetry() async {
    bool pingSuccessful = false;
    int retryCount = 0;
    final maxRetries = 3;

    while (!pingSuccessful && retryCount < maxRetries) {
      try {
        final currentPos = await LocationService.getCurrent();
        if (currentPos.latitude == null || currentPos.longitude == null) {
          debugPrint('❌ Standortdaten sind null');
          retryCount++;
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        final currentLatLng =
            LatLng(currentPos.latitude!, currentPos.longitude!);

        debugPrint('📍 Versuche Ping zu senden...');
        await _fs.sendPing(currentLatLng.latitude, currentLatLng.longitude);

        pingSuccessful = true;
        _lastSuccessfulPingMrX = DateTime.now();
        _failedAttemptsMrX = 0;

        if (mounted) {
          setState(() {
            _lastPingTime = DateTime.now();
            _lastPingPos = currentLatLng;
          });
          _handleVibeAndPing(currentLatLng);
          _startCountdownTimer();
        }

        debugPrint('✅ Ping erfolgreich gesendet um ${DateTime.now()}');
      } catch (e) {
        retryCount++;
        debugPrint('❌ Ping Versuch $retryCount/$maxRetries fehlgeschlagen: $e');

        // OFFLINE-FALLBACK: Lokal speichern
        if (retryCount == maxRetries) {
          try {
            final currentPos = await LocationService.getCurrent();
            if (currentPos.latitude != null && currentPos.longitude != null) {
              _savePingForLater(currentPos.latitude!, currentPos.longitude!);
            }
          } catch (e) {
            debugPrint('❌ Fehler beim Speichern für später: $e');
          }
        }

        if (retryCount < maxRetries) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    if (!pingSuccessful) {
      _failedAttemptsMrX++;
      debugPrint('❌ Alle Ping-Versuche fehlgeschlagen');
    }
  }

  void _savePingForLater(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingPings = prefs.getStringList('pending_pings') ?? [];

      final pingData = {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      pendingPings.add(json.encode(pingData));
      await prefs.setStringList('pending_pings', pendingPings);

      debugPrint('💾 Ping lokal gespeichert für späteren Versand: $lat, $lng');
    } catch (e) {
      debugPrint('❌ Fehler beim Speichern des Pings: $e');
    }
  }

  void _sendPendingPings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingPings = prefs.getStringList('pending_pings') ?? [];

      if (pendingPings.isEmpty) return;

      debugPrint('🔄 Sende ${pendingPings.length} ausstehende Pings...');

      final successfulPings = <String>[];

      for (final pingJson in pendingPings) {
        try {
          final pingData = json.decode(pingJson);
          final lat = double.parse(pingData['lat']);
          final lng = double.parse(pingData['lng']);

          await _fs.sendPing(lat, lng);
          successfulPings.add(pingJson);
          debugPrint('✅ Ausstehender Ping gesendet: $lat, $lng');

          // Kurze Pause zwischen Pings
          await Future.delayed(const Duration(seconds: 1));
        } catch (e) {
          debugPrint('❌ Fehler beim Senden eines ausstehenden Pings: $e');
          // Breche nicht ab, versuche nächsten Ping
        }
      }

      // Entferne erfolgreiche Pings
      final remainingPings = pendingPings
          .where((ping) => !successfulPings.contains(ping))
          .toList();
      await prefs.setStringList('pending_pings', remainingPings);

      debugPrint(
          '✅ ${successfulPings.length} ausstehende Pings erfolgreich gesendet');
    } catch (e) {
      debugPrint('❌ Fehler in _sendPendingPings: $e');
    }
  }

  @override
  void dispose() {
    if (_role == Role.mrx) {
      _stopBackgroundService();
    }

    WidgetsBinding.instance.removeObserver(this);
    _timerMyLoc?.cancel();
    _timerHunters?.cancel();
    _timerMrXNotify?.cancel();
    _mrXStatusTimer?.cancel();
    _cooldownTimer?.cancel();
    _countdownTimer?.cancel();
    _pingSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App kommt aus Standby - Daten sofort aktualisieren
      debugPrint('🔄 App aus Standby - Aktualisiere Daten...');
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    try {
      // Hole die neuesten Ping-Daten
      final pingData = await _fs.getLatestValidPing();
      if (pingData != null && pingData['isValid'] == true) {
        final timestamp = pingData['timestamp'] as Timestamp;
        final geo = pingData['location'] as GeoPoint;
        final pos = LatLng(geo.latitude, geo.longitude);
        final pingTime = timestamp.toDate();

        if (mounted) {
          setState(() {
            _lastPingTime = pingTime;
            _lastPingPos = pos;
          });
          _startCountdownTimer(); // ✅ Countdown neu starten
        }
        debugPrint('✅ Ping-Daten aktualisiert: ${_formatPingTime(pingTime)}');
      }

      // Aktualisiere Hunter-Positionen falls nötig
      if (_role == Role.hunter) {
        await _fetchHunters();
      }

      // ✅ Auch für Mr.X: Position aktualisieren
      await _updateMyLocation();
    } catch (e) {
      debugPrint('❌ Fehler beim Aktualisieren: $e');
    }
  }

  Future<void> _initializeMap() async {
    print('🔄 _initializeMap started');
    try {
      await _updateMyLocation();
      print('✅ _updateMyLocation completed');

      if (_role == Role.mrx) {
        _sendPendingPings();
      }

      if (_role == Role.hunter) {
        await _fetchHunters();
        print('✅ _fetchHunters completed');

        await _checkInitialPing();
        print('✅ Initial Ping check completed');
      }

      _startTimers();
      print('✅ _startTimers completed');
    } catch (e) {
      print('❌ _initializeMap failed: $e');
      if (mounted) {
        _startTimers();
      }
    }
  }

  void _startTimers() {
    _timerMyLoc = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateMyLocation(),
    );
    if (_role == Role.hunter) {
      _timerHunters = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _fetchHunters(),
      );
    }
  }

  double _calculateDistance(LatLng pos1, LatLng pos2) {
    const R = 6371000.0;
    final lat1 = pos1.latitude * pi / 180;
    final lat2 = pos2.latitude * pi / 180;
    final dLat = (pos2.latitude - pos1.latitude) * pi / 180;
    final dLng = (pos2.longitude - pos1.longitude) * pi / 180;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _updateMyLocation() async {
    print('🔄 _updateMyLocation started');
    try {
      final pos = await LocationService.getCurrent();
      print('📍 Location received: ${pos.latitude}, ${pos.longitude}');

      if (pos.latitude == null || pos.longitude == null) {
        print('❌ Invalid location data');
        return;
      }

      final myLatLng = LatLng(pos.latitude!, pos.longitude!);
      print('📍 LatLng created: $myLatLng');

      // Bewegung prüfen
      if (_lastSentPosition != null &&
          _calculateDistance(_lastSentPosition!, myLatLng) < 20) {
        print('📏 Movement < 20m, skipping update');
        return;
      }

      await _fs.sendLocation(
        lat: pos.latitude!,
        lng: pos.longitude!,
        isHunter: _role == Role.hunter,
      );
      print('✅ Location sent to Firestore');

      _lastSentPosition = myLatLng;

      final meMarker = Marker(
        key: const ValueKey('me'),
        point: myLatLng,
        width: 40,
        height: 40,
        child: Icon(
          Icons.person_pin_circle,
          color: _role == Role.hunter
              ? Colors.greenAccent.shade400
              : Colors.redAccent,
          size: 40,
        ),
      );

      setState(() {
        _center = myLatLng;
        print('🎯 Center set to: $_center');
        _markers.removeWhere((m) => m.key == const ValueKey('me'));
        _markers.add(meMarker);
        print('📍 Marker added');
      });
    } catch (e) {
      print('❌ _updateMyLocation failed: $e');
    }
  }

  Future<void> _fetchHunters() async {
    try {
      final data = await _fs.getAllHunterLocationsWithNames();
      setState(() {
        _markers.removeWhere((m) =>
            m.key is ValueKey<String> &&
            (m.key as ValueKey<String>).value.startsWith('hunter_'));
        for (var entry in data.entries) {
          if (entry.key == _uid) continue;
          final pt = LatLng(entry.value['latitude'], entry.value['longitude']);
          _markers.add(
            Marker(
              key: ValueKey('hunter_${entry.key}'),
              point: pt,
              width: 80,
              height: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.grey[800],
                    child: Text(
                      entry.value['username'],
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(Icons.person_pin, size: 36, color: Color(0xFF0A864A)),
                ],
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('Fetch hunters failed: $e');
    }
  }

  Future<void> _fetchMrX() async {
    try {
      // ✅ WIRD NICHT MEHR VERWENDET - Hunter sehen nur Pings
      // Diese Methode bleibt als Backup oder für zukünftige Erweiterungen
      final pingData = await _fs.getLatestValidPing();
      if (pingData != null && pingData['isValid'] == true) {
        final geo = pingData['location'] as GeoPoint;
        final pos = LatLng(geo.latitude, geo.longitude);
        _updateMrXMarker(pos);
        print('✅ Mr.X durch Ping angezeigt: $pos');
      } else {
        print('ℹ️ Kein gültiger Ping verfügbar - Mr.X bleibt versteckt');

        setState(() {
          _markers.removeWhere((m) => m.key == const ValueKey('mrx'));
        });
      }
    } catch (e) {
      print('Fetch Mr.X failed: $e');
    }
  }

  void _updateMrXMarker(LatLng pos) {
    setState(() {
      _markers.removeWhere((m) => m.key == const ValueKey('mrx'));
      _markers.add(
        Marker(
          key: const ValueKey('mrx'),
          point: pos,
          width: 80,
          height: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.grey[800],
                child: const Text(
                  'Mr.X',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.person, size: 36, color: Colors.redAccent),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _handleVibeAndPing(LatLng pos, {int duration = 300}) async {
    await Vibe.vibrate(duration: duration);
    _triggerPingVisual(pos);
  }

  void _triggerPingVisual(LatLng pos) {
    if (!mounted) return;

    setState(() {
      _lastPingTime = DateTime.now();
      _lastPingPos = pos;
      _showPulse = true;
    });

    _fadeController.forward(from: 0);

    // Zeige die Pulse-Animation für 2 Sekunden
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showPulse = false);
      }
    });
  }

  void _useAbility() async {
    if (_abilityUsed) return;

    setState(() {
      _abilityUsed = true;
      _cooldown = 1800; // 30 Minuten in Sekunden
    });
    _startCooldownTimer();

    try {
      print('🎯 Mr.X Fähigkeit aktiviert - Lade Hunter-Positionen...');
      final data = await _fs.getAllHunterLocationsWithNames();

      if (data.isEmpty) {
        print('❌ Keine Hunter-Positionen verfügbar');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Keine Hunter-Positionen verfügbar'),
          duration: Duration(seconds: 3),
        ));
        // Reset cooldown wenn keine Daten verfügbar
        setState(() {
          _abilityUsed = false;
          _cooldown = 0;
        });
        return;
      }

      print('✅ ${data.length} Hunter-Positionen geladen');

      setState(() {
        // Entferne alte Ability-Marker
        _markers.removeWhere((m) =>
            m.key is ValueKey<String> &&
            (m.key as ValueKey<String>).value.startsWith('ability_'));

        // Füge neue Ability-Marker hinzu
        for (var entry in data.entries) {
          if (entry.key == _uid) continue; // Überspringe sich selbst

          final pt = LatLng(entry.value['latitude'], entry.value['longitude']);
          _markers.add(
            Marker(
              key: ValueKey('ability_${entry.key}'),
              point: pt,
              width: 80,
              height: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.grey[800],
                    child: Text(
                      entry.value['username'],
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(Icons.person_pin, size: 36, color: Colors.orange),
                ],
              ),
            ),
          );
        }
      });

      // Zoom auf alle Hunter-Positionen
      final hunterPoints = data.values
          .map((hunter) => LatLng(hunter['latitude'], hunter['longitude']))
          .toList();

      if (hunterPoints.isNotEmpty) {
        _mapController.fitBounds(
          LatLngBounds.fromPoints(hunterPoints),
          options: const FitBoundsOptions(padding: EdgeInsets.all(50)),
        );
        print('✅ Karte auf Hunter-Positionen gezoomt');
      }

      // Zeige Erfolgsmeldung
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Hunter-Positionen sichtbar für 60 Sekunden (${data.length} Hunter)'),
        duration: Duration(seconds: 4),
      ));

      // Entferne die Marker nach 60 Sekunden
      Future.delayed(const Duration(seconds: 60), () {
        if (!mounted) return;
        setState(() {
          _markers.removeWhere((m) =>
              m.key is ValueKey<String> &&
              (m.key as ValueKey<String>).value.startsWith('ability_'));
        });
        print('✅ Ability-Marker entfernt');
      });
    } catch (e) {
      print('❌ Ability fetch failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler beim Laden der Hunter-Positionen: $e'),
        duration: Duration(seconds: 4),
      ));

      // Reset bei Fehler
      setState(() {
        _abilityUsed = false;
        _cooldown = 0;
      });
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
        setState(() {
          _abilityUsed = false;
          _cooldown = 0;
        });
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String _formatTimeDifference(DateTime pingTime) {
    final now = DateTime.now();
    final difference = now.difference(pingTime);

    if (difference.inMinutes < 1) {
      return 'vor wenigen Sekunden';
    } else if (difference.inMinutes < 60) {
      return 'vor ${difference.inMinutes} Minuten';
    } else if (difference.inHours < 24) {
      return 'vor ${difference.inHours} Stunden';
    } else {
      return 'vor ${difference.inDays} Tagen';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_center == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurpleAccent),
        ),
      );
    }
    final auth = context.read<AuthService>();
    final accent = Colors.deepPurpleAccent;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        title: Text(_role == Role.hunter ? 'Hunter-View' : 'Mr.X-View'),
        leading: BackButton(
          onPressed: () async {
            print('🔄 Back-Button gedrückt');
            try {
              // ✅ Zuerst lokale Rolle löschen
              final auth = context.read<AuthService>();
              auth.clearRole();

              await _fs.deleteLocationOnly(isHunter: _role == Role.hunter);
              print('✅ Location gelöscht');

              await _db.collection('users').doc(_uid).update({
                'role': FieldValue.delete(),
              });
              print('✅ Rolle in Firestore gelöscht');

              // ✅ SICHERER NAVIGATIONS-FALLBACK
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/roleselect', (route) => false);
              }
            } catch (e) {
              print('❌ Fehler im Back-Button: $e');
              // ✅ ABSOLUTER FALLBACK
              if (mounted) {
                final auth = context.read<AuthService>();
                auth.clearRole();
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/roleselect', (route) => false);
              }
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              print('🔄 Logout-Button gedrückt');
              try {
                await auth.logout(deleteData: true);
                print('✅ Logout erfolgreich');
              } catch (e) {
                print('❌ Fehler im Logout: $e');
                // Fallback: Direkter Logout
                final auth = context.read<AuthService>();
                await auth.logout(deleteData: true);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(center: _center!, zoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),
          if (_lastPingTime != null && _lastPingPos != null && _isMrXActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Letzter Ping: ${_formatPingTime(_lastPingTime!)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_timeUntilNextPing.inSeconds > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _timeUntilNextPing.inMinutes < 1
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Nächster: ${_formatCountdown(_timeUntilNextPing)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mr.X ist aktiv',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_isMrXActive && _role == Role.hunter)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.orange[800],
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  'Mr.X ist nicht aktiv',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (_showPulse)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 9000),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.redAccent, width: 8),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _role == Role.mrx
          ? Stack(
              alignment: Alignment.center,
              children: [
                FloatingActionButton(
                  backgroundColor: _abilityUsed
                      ? Colors.grey
                      : Colors.deepPurple.withOpacity(0.7),
                  onPressed: _abilityUsed ? null : _useAbility,
                  child: Icon(
                    _abilityUsed ? Icons.visibility_off : Icons.visibility,
                    color: Colors.black,
                  ),
                ),
                if (_cooldown > 0)
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: _cooldown / 60,
                      strokeWidth: 4,
                      backgroundColor: Colors.black26,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                if (_cooldown > 0)
                  Text(
                    '$_cooldown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            )
          : null,
    );
  }
}
