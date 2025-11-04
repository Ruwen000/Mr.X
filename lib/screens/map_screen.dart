// lib/screens/map_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/role.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import 'package:flutter/services.dart';

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

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _fs = FirestoreService();
  final List<Marker> _markers = [];
  LatLng? _center;
  late final MapController _mapController;

  Timer? _timerMyLoc, _timerHunters, _timerMrXNotify, _cooldownTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pingSub;

  late final Role _role;
  late final String _uid;

  DateTime? _lastPingTime;
  LatLng? _lastPingPos;
  bool _showPulse = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  bool _abilityUsed = false;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    final auth = context.read<AuthService>();
    _role = auth.role!;
    _uid = auth.uid;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _initializeMap();

    if (_role == Role.hunter) {
      _checkInitialPing();
      
      _pingSub = _fs.pingStream().listen((docSnap) {
        if (!docSnap.exists) return;
        final geo = docSnap.data()?['location'] as GeoPoint?;
        final timestamp = docSnap.data()?['ts'] as Timestamp?;
        if (geo == null || timestamp == null) return;
        
        final now = DateTime.now();
        final pingTime = timestamp.toDate();
        if (now.difference(pingTime).inMinutes > 10) return;
        
        final pos = LatLng(geo.latitude, geo.longitude);
        _updateMrXMarker(pos);
        _handleVibeAndPing(pos);
      });
    }

    Future<void> _checkInitialPing() async {
      try {
        final pingData = await _fs.getLatestValidPing();
        if (pingData != null && pingData['isValid'] == true) {
          final geo = pingData['location'] as GeoPoint;
          final pos = LatLng(geo.latitude, geo.longitude);
          _updateMrXMarker(pos);
        }
      } catch (e) {
        debugPrint("Fehler beim Laden des initialen Pings: $e");
      }
    }

    if (_role == Role.mrx) {
      _timerMrXNotify = Timer.periodic(
        const Duration(seconds: 600), // 10 Minuten
        (_) async {
          try {
            // Hole die aktuelle Position direkt vom Location Service
            final currentPos = await LocationService.getCurrent();
            if (currentPos.latitude == null || currentPos.longitude == null) return;
            
            final currentLatLng = LatLng(currentPos.latitude!, currentPos.longitude!);
            
            // Sende Ping mit der aktuellen Position
            await _fs.sendPing(currentLatLng.latitude, currentLatLng.longitude);
            _handleVibeAndPing(currentLatLng);
            
            debugPrint('Mr.X Ping gesendet um ${DateTime.now()}');
          } catch (e) {
            debugPrint("Fehler beim Ping senden: $e");
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _timerMyLoc?.cancel();
    _timerHunters?.cancel();
    _timerMrXNotify?.cancel();
    _cooldownTimer?.cancel();
    _pingSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _updateMyLocation();
    if (_role == Role.hunter) {
      await _fetchHunters();
      await _fetchMrX();
    }
    _startTimers();
  }

  void _startTimers() {
    _timerMyLoc = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateMyLocation(),
    );
    if (_role == Role.hunter) {
      _timerHunters = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _fetchHunters(),
      );
    }
  }

  Future<void> _updateMyLocation() async {
    try {
      final pos = await LocationService.getCurrent();
      if (pos.latitude == null || pos.longitude == null) return;
      final myLatLng = LatLng(pos.latitude!, pos.longitude!);

      await _fs.sendLocation(
        lat: pos.latitude!,
        lng: pos.longitude!,
        isHunter: _role == Role.hunter,
      );

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
        _center ??= myLatLng;
        _markers.removeWhere((m) => m.key == const ValueKey('me'));
        _markers.add(meMarker);
      });
    } catch (e) {
      debugPrint('Update my location failed: $e');
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
      debugPrint('Fetch hunters failed: $e');
    }
  }

  Future<void> _fetchMrX() async {
    try {
      final info = await _fs.getMrXWithName();
      if (info == null) return;
      final pos = LatLng(info['latitude'], info['longitude']);
      _updateMrXMarker(pos);
    } catch (e) {
      debugPrint('Fetch Mr.X failed: $e');
    }
  }

  /// Zeigt immer hardcoded "Mr.X" an
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
    setState(() {
      _lastPingTime = DateTime.now();
      _lastPingPos = pos;
      _showPulse = true;
    });
    
    _fadeController.forward(from: 0);
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showPulse = false);
    });
  }

  void _useAbility() async {
    if (_abilityUsed) return;
    setState(() {
      _abilityUsed = true;
      _cooldown = 1800;
    });
    _startCooldownTimer();

    try {
      final data = await _fs.getAllHunterLocationsWithNames();
      setState(() {
        _markers.removeWhere((m) =>
            m.key is ValueKey<String> &&
            (m.key as ValueKey<String>).value.startsWith('ability_'));
        for (var entry in data.entries) {
          if (entry.key == _uid) continue;
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
        final pts = _markers.map((m) => m.point).toList();
        if (pts.isNotEmpty) {
          _mapController.fitBounds(
            LatLngBounds.fromPoints(pts),
            options: const FitBoundsOptions(padding: EdgeInsets.all(50)),
          );
        }
      });
    } catch (e) {
      debugPrint('Ability fetch failed: $e');
    }
    Future.delayed(const Duration(seconds: 60), () {
      if (!mounted) return;
      setState(() {
        _markers.removeWhere((m) =>
            m.key is ValueKey<String> &&
            (m.key as ValueKey<String>).value.startsWith('ability_'));
      });
    });
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
            await _fs.deleteLocationOnly(isHunter: _role == Role.hunter);
            auth.clearRole();
            Navigator.of(context).pushReplacementNamed('/roleselect');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => auth.logout(deleteData: true),
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
          if (_lastPingTime != null && _lastPingPos != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Container(
                  color: Colors.black54,
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Text(
                    'Letzter Mr.X Ping um ${TimeOfDay.fromDateTime(_lastPingTime!).format(context)} '
                    'bei (${_lastPingPos!.latitude.toStringAsFixed(5)}, '
                    '${_lastPingPos!.longitude.toStringAsFixed(5)})',
                    style: const TextStyle(color: Colors.white),
                  ),
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
