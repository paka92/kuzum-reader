package com.karakaya.kuzum_reader

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (not FlutterActivity) so playback started from
// the UI survives the activity going away — required by audio_service.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+ suppresses the playback notification, and with it the
        // transport controls, unless this runtime permission is granted.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Ask ChatGPT" sends the prompt straight to one chosen app — the
        // system share sheet can't preselect a target, so this needs a plain
        // ACTION_SEND with the package pinned. Returns false when the app
        // isn't installed, letting Dart fall back to the share sheet.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kuzum_reader/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "sendTextTo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    call.argument<String>("package")?.let { setPackage(it) }
                }
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
