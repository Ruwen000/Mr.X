package com.example.mr_x_app

import android.os.VibrationEffect
import android.os.Vibrator
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log     

class MainActivity: FlutterActivity() {
  private val CHANNEL = "app.channel.vibration"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    Log.i("VIBE", "🛎️ configureFlutterEngine ist da!")
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
      call, result ->
      if (call.method == "vibrate") {
        val duration = (call.argument<Int>("duration") ?: 500).toLong()
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        // ab Android O:
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
          vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
          @Suppress("DEPRECATION")
          vibrator.vibrate(duration)
        }
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
  }
}
