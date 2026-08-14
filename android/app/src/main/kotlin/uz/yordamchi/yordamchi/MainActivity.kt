package uz.yordamchi.yordamchi

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "yordamchi/wake_word"
        const val EXTRA_WAKE = "wake_word_triggered"
    }

    private var channel: MethodChannel? = null

    // Ilova sovuq ochilganda "Hey Jarvis" signali kelgan bo'lsa shu yerda turadi.
    private var pendingWakeWord = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    startWakeService(WakeWordService.ACTION_START)
                    result.success(true)
                }
                "stopService" -> {
                    stopService(Intent(this, WakeWordService::class.java))
                    result.success(true)
                }
                "pauseListening" -> {
                    startWakeService(WakeWordService.ACTION_PAUSE)
                    result.success(true)
                }
                "resumeListening" -> {
                    startWakeService(WakeWordService.ACTION_RESUME)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(isWakeServiceRunning())
                }
                "checkWakeWord" -> {
                    result.success(pendingWakeWord)
                    pendingWakeWord = false
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path") ?: ""
                    result.success(installApk(path))
                }
                "canRequestInstalls" -> {
                    result.success(canRequestInstalls())
                }
                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra(EXTRA_WAKE, false) == true) {
            pendingWakeWord = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_WAKE, false)) {
            pendingWakeWord = true
            notifyDartWake()
        }
    }

    override fun onResume() {
        super.onResume()
        // Ilova old yuzaga chiqqanda kechikkan signalni ham tekshiramiz.
        if (pendingWakeWord) {
            notifyDartWake()
        }
    }

    private fun notifyDartWake() {
        pendingWakeWord = false
        try {
            channel?.invokeMethod(
                "onWakeWord",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(
                        code: String,
                        message: String?,
                        details: Any?
                    ) {}

                    override fun notImplemented() {}
                }
            )
        } catch (_: Throwable) {
            // Dart tomonda handler hali ro'yxatdan o'tmagan bo'lishi mumkin;
            // bunda keyingi onResume/checkWakeWord to'ldiradi.
            pendingWakeWord = true
        }
    }

    private fun startWakeService(action: String) {
        try {
            val intent = Intent(this, WakeWordService::class.java).setAction(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Throwable) {}
    }

    private fun isWakeServiceRunning(): Boolean {
        return try {
            val manager =
                getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager
                .getRunningServices(Int.MAX_VALUE)
                .any { it.service.className == WakeWordService::class.java.name }
        } catch (_: Throwable) {
            false
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        try {
            val pm = packageManager
            if (pm.hasSystemFeature("android.hardware.battery")) {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        } catch (_: Throwable) {}
    }

    // ---------------- Auto-update ----------------

    /// Yuklab olingan APK faylini Android o'rnatuvchisiga ochadi.
    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /// Android 8+ da "noma'lum manbalardan o'rnatish" ruxsati berilganmi.
    private fun canRequestInstalls(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                true
            } else {
                packageManager.canRequestPackageInstalls()
            }
        } catch (_: Throwable) {
            false
        }
    }

    /// Foydalanuvchini "Noma'lum ilovalar" sozlamasiga olib boradi.
    private fun openInstallSettings() {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } catch (_: Throwable) {}
    }
}
