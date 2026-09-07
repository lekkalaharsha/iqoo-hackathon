package com.example.camapp

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ponytail: while this app is foregrounded the volume rocker is the app's
// primary control (blind users find it by feel). Vol-Up = act, Vol-Down = repeat.
class MainActivity : FlutterActivity() {

    private var events: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "aiforall/hardware_keys")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { events = sink }
                override fun onCancel(args: Any?) { events = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aiforall/phone")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Direct dial: a blind user cannot reliably find and tap the
                    // dialer's call button, so ACTION_CALL rather than ACTION_DIAL.
                    // Dart side runs a cancellable countdown before calling this.
                    "call" -> {
                        val number = call.argument<String>("number")
                        if (number.isNullOrBlank()) {
                            result.error("no_number", "No number supplied", null)
                        } else {
                            result.success(placeCall(number))
                        }
                    }
                    // Falls back to the dialer, which needs no permission.
                    "dial" -> {
                        val number = call.argument<String>("number")
                        if (number.isNullOrBlank()) {
                            result.error("no_number", "No number supplied", null)
                        } else {
                            startActivity(
                                Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        }
                    }
                    // Opens the system "Digital assistant app" picker so the user
                    // can set Logic Legends as the assistant (power-button-hold launch).
                    "openAssistSettings" -> {
                        val tries = listOf(
                            "android.settings.VOICE_INPUT_SETTINGS",
                            android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS,
                            android.provider.Settings.ACTION_SETTINGS,
                        )
                        var opened = false
                        for (action in tries) {
                            try {
                                startActivity(
                                    Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                opened = true
                                break
                            } catch (_: Exception) { /* try the next one */ }
                        }
                        result.success(opened)
                    }
                    // "Pay this bill": hand a upi://pay link to whatever UPI app
                    // the user has. That app shows payee + amount and demands the
                    // UPI PIN on a secure keyboard we cannot see — the payment
                    // never passes through this app.
                    "payUpi" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrBlank() || !uri.startsWith("upi://")) {
                            result.error("bad_uri", "Not a upi:// link", null)
                        } else {
                            result.success(openUpi(uri))
                        }
                    }
                    // "Open <app>" by voice: the phone's own launchable-app list
                    // (label + package) so Dart can match a spoken phrase to a
                    // real installed app — no hand-maintained package map.
                    "listLaunchableApps" -> result.success(listLaunchableApps())
                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent != null) {
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "hasCallPermission" -> result.success(hasCallPermission())
                    "requestCallPermission" -> {
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.CALL_PHONE), 4711
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Shows the "Pay with" chooser for a upi://pay link. A chooser every time:
     * there is no reliable "default UPI app", and a blind user must not silently
     * pay from the wrong account. Returns false if no UPI app is installed.
     */
    private fun openUpi(uri: String): Boolean {
        val view = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        if (view.resolveActivity(packageManager) == null) return false
        return try {
            startActivity(
                Intent.createChooser(view, "Pay with")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Every activity that shows in the launcher: user-visible label + package. */
    private fun listLaunchableApps(): List<Map<String, String>> {
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(main, 0).map {
            mapOf(
                "label" to it.loadLabel(packageManager).toString(),
                "package" to it.activityInfo.packageName,
            )
        }
    }

    private fun hasCallPermission() = ContextCompat.checkSelfPermission(
        this, Manifest.permission.CALL_PHONE
    ) == PackageManager.PERMISSION_GRANTED

    /**
     * Returns true only if an ACTION_CALL activity was actually started. If the
     * countdown finished while the app was backgrounded, Android silently blocks
     * the background activity start — catch that and return false so the Dart
     * side speaks its "open the dialler" fallback instead of a false success.
     */
    private fun placeCall(number: String): Boolean {
        val uri = Uri.parse("tel:$number")
        val flags = Intent.FLAG_ACTIVITY_NEW_TASK
        if (hasCallPermission()) {
            try {
                startActivity(Intent(Intent.ACTION_CALL, uri).addFlags(flags))
                return true
            } catch (e: Exception) {
                // fall through to the dialler
            }
        }
        return try {
            startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(flags))
            false
        } catch (e: Exception) {
            false
        }
    }

    private val audio by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }

    // No system volume UI (flag 0), but the media stream still moves — otherwise a
    // blind user whose media volume is muted has no way to hear the TTS output.
    private fun nudgeVolume(up: Boolean) = audio.adjustStreamVolume(
        AudioManager.STREAM_MUSIC,
        if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
        0
    )

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                val up = keyCode == KeyEvent.KEYCODE_VOLUME_UP
                nudgeVolume(up)
                // Fire the app action once per physical press, not on auto-repeat.
                if (event?.repeatCount == 0) {
                    events?.success(if (up) "volume_up" else "volume_down")
                }
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    // Also swallow the matching key-up so the system volume UI never shows.
    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) return true
        return super.onKeyUp(keyCode, event)
    }
}
