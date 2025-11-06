// MrXBackgroundService.java - VOLLSTÄNDIG ERSETZEN
package com.example.mr_x_app;

import android.app.Service;
import android.content.Intent;
import android.location.Location;
import android.os.IBinder;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.firebase.firestore.FirebaseFirestore;
import com.google.firebase.firestore.SetOptions;
import java.util.HashMap;
import java.util.Map;

public class MrXBackgroundService extends Service {
    private static final String TAG = "MrXBackgroundService";
    private static final int NOTIFICATION_ID = 123;
    private FusedLocationProviderClient fusedLocationClient;
    private LocationCallback locationCallback;
    private FirebaseFirestore db;
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Mr.X Background Service gestartet");
        
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this);
        db = FirebaseFirestore.getInstance();
        
        startForeground(NOTIFICATION_ID, createNotification());
        startLocationUpdates();
    }
    
    private android.app.Notification createNotification() {
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, "mr_x_channel")
            .setContentTitle("Mr.X läuft im Hintergrund")
            .setContentText("Standort wird alle 10 Minuten gesendet")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW);
        
        return builder.build();
    }
    
    private void startLocationUpdates() {
        LocationRequest locationRequest = LocationRequest.create();
        locationRequest.setInterval(600000); // 10 Minuten
        locationRequest.setFastestInterval(600000);
        locationRequest.setPriority(LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY);
        
        locationCallback = new LocationCallback() {
            @Override
            public void onLocationResult(LocationResult locationResult) {
                if (locationResult == null) return;
                
                for (Location location : locationResult.getLocations()) {
                    sendPingToFirestore(location.getLatitude(), location.getLongitude());
                }
            }
        };
        
        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, null);
            Log.d(TAG, "Location Updates gestartet");
        } catch (SecurityException e) {
            Log.e(TAG, "Location permission fehlt: " + e.getMessage());
        }
    }
    
    private void sendPingToFirestore(double lat, double lng) {
        try {
            Map<String, Object> pingData = new HashMap<>();
            pingData.put("location", new com.google.firebase.firestore.GeoPoint(lat, lng));
            pingData.put("timestamp", com.google.firebase.firestore.FieldValue.serverTimestamp());
            pingData.put("isValid", true);
            
            db.collection("games").document("current")
              .collection("pings").document("latest")
              .set(pingData, SetOptions.merge())
              .addOnSuccessListener(aVoid -> 
                  Log.d(TAG, "Ping erfolgreich gesendet: " + lat + ", " + lng))
              .addOnFailureListener(e -> 
                  Log.e(TAG, "Fehler beim Senden des Pings: " + e.getMessage()));
                  
        } catch (Exception e) {
            Log.e(TAG, "Exception beim Senden des Pings: " + e.getMessage());
        }
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }
    
    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        if (fusedLocationClient != null && locationCallback != null) {
            fusedLocationClient.removeLocationUpdates(locationCallback);
        }
        Log.d(TAG, "Mr.X Background Service gestoppt");
    }
}