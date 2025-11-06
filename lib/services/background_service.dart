import 'package:flutter/services.dart';

class BackgroundService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mr_x_app/background');

  static Future<void> startMrXBackgroundService() async {
    try {
      await _channel.invokeMethod('startMrXBackgroundService');
      print('✅ Mr.X Background Service gestartet');
    } on PlatformException catch (e) {
      print('❌ Fehler beim Starten des Background Service: ${e.message}');
    }
  }

  static Future<void> stopMrXBackgroundService() async {
    try {
      await _channel.invokeMethod('stopMrXBackgroundService');
      print('✅ Mr.X Background Service gestoppt');
    } on PlatformException catch (e) {
      print('❌ Fehler beim Stoppen des Background Service: ${e.message}');
    }
  }
}
