import 'package:location/location.dart';

class LocationService {
  static final Location _location = Location();

  static Future<LocationData> getCurrent() async {
    try {
      print('📍 LocationService: Starte Standortabfrage...');

      // Permission prüfen
      PermissionStatus permission = await _location.hasPermission();
      print('📍 LocationService: Permission Status: $permission');

      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
        print(
            '📍 LocationService: Nach Anfrage - Permission Status: $permission');
        if (permission != PermissionStatus.granted) {
          throw Exception('Location permission denied');
        }
      }

      // Standortdienst prüfen
      bool serviceEnabled = await _location.serviceEnabled();
      print('📍 LocationService: Service Enabled: $serviceEnabled');

      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        print(
            '📍 LocationService: Nach Service-Anfrage - Service Enabled: $serviceEnabled');
        if (!serviceEnabled) {
          throw Exception('Location services disabled');
        }
      }

      // Standort mit erhöhter Genauigkeit abrufen
      print('📍 LocationService: Hole Standortdaten...');
      final locationData = await _location.getLocation();
      print(
          '📍 LocationService: Standort erhalten: ${locationData.latitude}, ${locationData.longitude}');

      if (locationData.latitude == null || locationData.longitude == null) {
        throw Exception('Invalid location data');
      }

      return locationData;
    } catch (e) {
      print('❌ LocationService Error: $e');
      rethrow;
    }
  }
}
