package uz.yordamchi.yordamchi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.util.Locale

/**
 * "Hey Jarvis" uyg'otuvchi so'z xizmati.
 *
 * Foydalanuvchi ilova yopiq/ekran o'chiq bo'lsa ham doimiy eshitib turadi.
 * "Hey Jarvis" eshitilganda [MainActivity] old yuzaga chiqariladi va
 * Flutter'ga "onWakeWord" xabari uzatiladi.
 *
 * Fon xizmati (foreground service) ekani uchun Android uni o'ldirmaydi.
 */
class WakeWordService : Service() {

    companion object {
        private const val TAG = "WakeWordService"
        private const val CHANNEL_ID = "wake_word_channel"
        private const val NOTIF_ID = 42

        const val ACTION_START = "uz.yordamchi.yordamchi.WAKE_START"
        const val ACTION_STOP = "uz.yordamchi.yordamchi.WAKE_STOP"
        const val ACTION_PAUSE = "uz.yordamchi.yordamchi.WAKE_PAUSE"
        const val ACTION_RESUME = "uz.yordamchi.yordamchi.WAKE_RESUME"
        const val EXTRA_WAKE = "wake_word_triggered"

        // Static holat: MainActivity ham shu flagni o'qiy oladi.
        var paused = false
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var restartRunnable: Runnable? = null
    private var listening = false
    private var destroyed = false
    private var restartDelay = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock =
            pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "yordamchi:wake_word")
        wakeLock?.setReferenceCounted(false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                paused = false
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                paused = true
                stopListening()
                return START_STICKY
            }
            ACTION_RESUME -> {
                paused = false
                startForegroundSafe()
                startListening()
                return START_STICKY
            }
            else -> { // ACTION_START yoki birinchi ishga tushirish
                paused = false
                startForegroundSafe()
                startListening()
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        destroyed = true
        stopListening()
        handler.removeCallbacksAndMessages(null)
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {}
        super.onDestroy()
    }

    // ---------------- Foreground ----------------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hey Jarvis",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
    }

    private fun startForegroundSafe() {
        try {
            val notif = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(NOTIF_ID, notif)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "startForeground error: ${t.message}")
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Jarvis eshitmoqda")
            .setContentText("\"Hey Jarvis\" deb gapiring")
            .setSmallIcon(R.drawable.ic_wake)
            .setContentIntent(pi)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    // ---------------- Eshitish ----------------

    private fun startListening() {
        if (destroyed || paused || listening) return
        try {
            if (recognizer == null) {
                recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                recognizer?.setRecognitionListener(listener)
            }
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                // "hey jarvis" inglizcha — o'zbek (uz-UZ) tanib olishchi uni
                // boshqacha yozadi (hatto kirillcha ham chiqaradi), shuning
                // uchun doim en-US ishlatamiz.
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                // Sukut pauzalarida ham eshitib turish uchun kutishlarni uzaytiramiz
                putExtra(
                    "android.speech.extra.SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS",
                    3000L
                )
                putExtra(
                    "android.speech.extra.SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS",
                    3000L
                )
            }
            listening = true
            recognizer?.startListening(intent)
            acquireWakeLock()
        } catch (t: Throwable) {
            Log.w(TAG, "startListening error: ${t.message}")
            listening = false
            scheduleRestart()
        }
    }

    private fun stopListening() {
        listening = false
        try {
            recognizer?.stopListening()
        } catch (_: Throwable) {}
        try {
            recognizer?.cancel()
        } catch (_: Throwable) {}
        releaseWakeLock()
    }

    private fun acquireWakeLock() {
        try {
            wakeLock?.let { if (!it.isHeld) it.acquire(10 * 60 * 1000L) }
        } catch (_: Throwable) {}
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {}
    }

    private fun scheduleRestart() {
        if (destroyed || paused) return
        restartRunnable?.let { handler.removeCallbacks(it) }
        // Gapirlik paytida xabar qolib ketmasligi uchun uzilishni qisqa
        // tutamiz (300ms dan 1500ms gacha).
        restartDelay = (restartDelay + 300L).coerceAtMost(1500L)
        restartRunnable = Runnable {
            restartDelay = 0L
            if (!paused) startListening()
        }
        handler.postDelayed(restartRunnable!!, restartDelay)
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {
            listening = false
        }

        override fun onError(error: Int) {
            listening = false
            Log.w(TAG, "tanib olish xatosi: $error")
            scheduleRestart()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val matches = partialResults?.getStringArrayList(
                SpeechRecognizer.RESULTS_RECOGNITION
            )
            checkMatches(matches)
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val matches = results?.getStringArrayList(
                SpeechRecognizer.RESULTS_RECOGNITION
            )
            checkMatches(matches)
            scheduleRestart()
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    // ---------------- Uyg'otish ----------------

    private fun checkMatches(matches: ArrayList<String>?) {
        if (destroyed || paused) return
        matches?.forEach { raw ->
            Log.i(TAG, "eshitildi: $raw")
            if (isWake(raw)) {
                trigger()
                return
            }
        }
    }

    /**
     * "Hey Jarvis" (yoki unga yaqin variantlar) tanib olinganmi.
     * Google'ning o'zbekcha va inglizcha variantlarini hisobga oladi,
     * "jarvis" so'zining ozgina xato yozilishiga ham toqat qiladi.
     */
    private fun isWake(raw: String): Boolean {
        val text = raw
            .lowercase(Locale.ROOT)
            .replace(Regex("[^a-zа-яё ]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        // To'g'ridan-to'g'ri variantlar (inglizcha + kirillcha)
        val direct = listOf(
            "hey jarvis", "he jarvis", "hay jarvis", "ay jarvis",
            "hi jarvis", "hello jarvis", "okay jarvis",
            "хей джарвис", "эй джарвис", "хи джарвис"
        )
        if (direct.any { text.contains(it) }) return true
        if (text == "jarvis" || text == "джарвис") return true

        // So'z darajasida: "jarvis"ga yoki "джарвис"ga juda yaqin so'z
        val words = text.split(" ")
        return words.any { levenshtein(it, "jarvis") <= 2 } ||
            words.any { levenshtein(it, "джарвис") <= 2 }
    }

    private fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val tmp = dp[j]
                dp[j] = minOf(
                    dp[j] + 1,
                    dp[j - 1] + 1,
                    prev + if (a[i - 1] == b[j - 1]) 0 else 1
                )
                prev = tmp
            }
        }
        return dp[b.length]
    }

    private fun trigger() {
        if (destroyed) return
        paused = true
        stopListening()
        try {
            val i = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
                putExtra(EXTRA_WAKE, true)
            }
            startActivity(i)
        } catch (t: Throwable) {
            Log.e(TAG, "trigger error: ${t.message}")
            // Aktivlik ochilmadi — oxirgi imkoniyat: bildirishnoma bilan ochish
            try {
                val openIntent = Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra(EXTRA_WAKE, true)
                val pi = PendingIntent.getActivity(
                    this,
                    1,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                pi.send()
            } catch (_: Throwable) {}
        }
    }
}
