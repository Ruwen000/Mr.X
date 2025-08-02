import 'package:location/location.dart';

class LocationService {
  static final Location _location = Location();

  static Future<LocationData> getCurrent() async {
    // Permission prüfen und ggf. anfragen
    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) {
        throw Exception('Location permission denied');
      }
    }

    // Standortdienst prüfen und ggf. anfragen
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        throw Exception('Location services disabled');
      }
    }

    // Standort abrufen
    return await _location.getLocation();
  }
}
