package com.example.mr_x_app;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.content.Intent;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.mr_x_app/background";
    
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("startMrXBackgroundService")) {
                    startMrXBackgroundService();
                    result.success("Background Service gestartet");
                } else if (call.method.equals("stopMrXBackgroundService")) {
                    stopMrXBackgroundService();
                    result.success("Background Service gestoppt");
                } else {
                    result.notImplemented();
                }
            });
    }
    
    private void startMrXBackgroundService() {
        Intent serviceIntent = new Intent(this, MrXBackgroundService.class);
        startService(serviceIntent);
    }
    
    private void stopMrXBackgroundService() {
        Intent serviceIntent = new Intent(this, MrXBackgroundService.class);
        stopService(serviceIntent);
    }
}