package com.mcmusic.app.mcmusic_flutter

import android.content.Context
import android.content.Intent
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var isAudioPlaying = false
    private val cachedWebViews = java.util.Collections.synchronizedSet(mutableSetOf<java.lang.ref.WeakReference<WebView>>())

    // Network Handover Monitor (WiFi <-> Cellular smooth playback transition)
    private var wakelockChannel: MethodChannel? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Android Native Audio Effects (Hardware-accelerated Equalizer, Loudness Enhancer, Bass Boost & 3D Virtualizer)
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private val CHANNEL = "com.mcmusic.app/equalizer"
    private val WAKELOCK_CHANNEL = "com.mcmusic.app/wakelock"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initAudioEffects()

        wakelockChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKELOCK_CHANNEL)
        wakelockChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireLocks" -> {
                    isAudioPlaying = true
                    acquirePlaybackLocks()
                    result.success(true)
                }
                "releaseLocks" -> {
                    isAudioPlaying = false
                    releasePlaybackLocks()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isIgnoring = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(isIgnoring)
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("ERROR", e2.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    setEffectsEnabled(enabled)
                    result.success(true)
                }
                "setBands" -> {
                    val rawBands = call.argument<List<*>>("bands")
                    val preampDb = (call.argument<Number>("preamp"))?.toDouble() ?: 0.0
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (rawBands != null) {
                        val bands = rawBands.mapNotNull { item ->
                            when (item) {
                                is Number -> item.toDouble()
                                else -> null
                            }
                        }
                        applyBands(bands, preampDb, enabled)
                    }
                    result.success(true)
                }
                "setBandLevel" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val levelDb = (call.argument<Number>("level"))?.toDouble() ?: 0.0
                    val preampDb = (call.argument<Number>("preamp"))?.toDouble() ?: 0.0
                    applyBandLevel(band, levelDb, preampDb)
                    result.success(true)
                }
                "setBassBoost" -> {
                    val strength = (call.argument<Number>("strength"))?.toDouble() ?: 0.0
                    applyBassBoost(strength)
                    result.success(true)
                }
                "setVirtualizer" -> {
                    val strength = (call.argument<Number>("strength"))?.toDouble() ?: 0.0
                    applyVirtualizer(strength)
                    result.success(true)
                }
                "setLoudnessGain" -> {
                    val gainMb = call.argument<Int>("gain") ?: 600
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    applyLoudnessGain(gainMb, enabled)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initAudioEffects() {
        try {
            if (equalizer == null) {
                equalizer = Equalizer(1000, 0).apply {
                    enabled = false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            if (loudnessEnhancer == null) {
                loudnessEnhancer = LoudnessEnhancer(0).apply {
                    setTargetGain(0)
                    enabled = false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            if (bassBoost == null) {
                bassBoost = BassBoost(1000, 0).apply {
                    enabled = false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            if (virtualizer == null) {
                virtualizer = Virtualizer(1000, 0).apply {
                    enabled = false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun setEffectsEnabled(enabled: Boolean) {
        try {
            initAudioEffects()
            equalizer?.enabled = enabled
            if (!enabled) {
                bassBoost?.enabled = false
                virtualizer?.enabled = false
                // Keep loudness enhancer active so car speaker volume never drops suddenly
                val hasGain = (loudnessEnhancer?.targetGain?.toInt() ?: 0) > 0
                loudnessEnhancer?.enabled = hasGain
            } else {
                bassBoost?.enabled = (bassBoost?.roundedStrength?.toInt() ?: 0) > 0
                virtualizer?.enabled = (virtualizer?.roundedStrength?.toInt() ?: 0) > 0
                loudnessEnhancer?.enabled = (loudnessEnhancer?.targetGain?.toInt() ?: 0) > 0
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyLoudnessGain(gainMb: Int, enabled: Boolean) {
        try {
            initAudioEffects()
            loudnessEnhancer?.let { le ->
                // Allow up to 1200 mB (+12.0 dB) for punchy and clear car & Bluetooth audio
                val safeGain = gainMb.coerceIn(0, 1200)
                le.setTargetGain(safeGain)
                le.enabled = enabled && safeGain > 0
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyBandLevel(bandIndex: Int, levelDb: Double, preampDb: Double = 0.0) {
        try {
            initAudioEffects()
            equalizer?.let { eq ->
                val numBands = eq.numberOfBands.toInt()
                if (bandIndex in 0 until numBands) {
                    val range = eq.bandLevelRange
                    val min = range[0].toInt()
                    val max = range[1].toInt()
                    // Apply negative headroom compensation to protect against digital audio clipping (>0 dBFS)
                    val effectiveDb = levelDb + (preampDb * 0.6)
                    val targetMb = (effectiveDb * 100).toInt().coerceIn(min, max).toShort()
                    eq.setBandLevel(bandIndex.toShort(), targetMb)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyBands(bands: List<Double>, preampDb: Double = 0.0, enabled: Boolean) {
        try {
            initAudioEffects()
            setEffectsEnabled(enabled)
            equalizer?.let { eq ->
                val numBands = eq.numberOfBands.toInt()
                for (i in bands.indices) {
                    if (i < numBands) {
                        val range = eq.bandLevelRange
                        val min = range[0].toInt()
                        val max = range[1].toInt()
                        // Apply negative headroom compensation to protect against digital audio clipping (>0 dBFS)
                        val effectiveDb = bands[i] + (preampDb * 0.6)
                        val targetMb = (effectiveDb * 100).toInt().coerceIn(min, max).toShort()
                        eq.setBandLevel(i.toShort(), targetMb)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyBassBoost(strengthRatio: Double) {
        try {
            initAudioEffects()
            bassBoost?.let { bb ->
                if (bb.strengthSupported) {
                    val strength = (strengthRatio * 1000).toInt().coerceIn(0, 1000).toShort()
                    bb.setStrength(strength)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyVirtualizer(strengthRatio: Double) {
        try {
            initAudioEffects()
            virtualizer?.let { virt ->
                if (virt.strengthSupported) {
                    val strength = (strengthRatio * 1000).toInt().coerceIn(0, 1000).toShort()
                    virt.setStrength(strength)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "McMusic::PlaybackWakeLock")
            wakeLock?.setReferenceCounted(false)

            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL, "McMusic::PlaybackWifiLock")
            wifiLock?.setReferenceCounted(false)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Register Network Callback to handle smooth WiFi <-> Mobile Data handover without audio interruption
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                networkCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        runOnUiThread {
                            wakelockChannel?.invokeMethod("onNetworkAvailable", null)
                        }
                    }

                    override fun onLost(network: Network) {
                        runOnUiThread {
                            // If WiFi was lost, release wifiLock immediately so mobile data takes over without lock contention
                            if (wifiLock?.isHeld == true) {
                                try { wifiLock?.release() } catch (_: Throwable) {}
                            }
                            wakelockChannel?.invokeMethod("onNetworkLost", null)
                        }
                    }

                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                        val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        val isValidated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                        val isWifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                        val isCellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)

                        runOnUiThread {
                            if (isWifi && isAudioPlaying) {
                                if (wifiLock?.isHeld != true) {
                                    try { wifiLock?.acquire() } catch (_: Throwable) {}
                                }
                            } else if (isCellular) {
                                if (wifiLock?.isHeld == true) {
                                    try { wifiLock?.release() } catch (_: Throwable) {}
                                }
                            }

                            if (hasInternet && isValidated) {
                                wakelockChannel?.invokeMethod("onNetworkValidated", mapOf(
                                    "isWifi" to isWifi,
                                    "isCellular" to isCellular
                                ))
                            }
                        }
                    }
                }
                networkCallback?.let { connectivityManager?.registerDefaultNetworkCallback(it) }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Enable High Refresh Rate (90Hz / 120Hz / 144Hz) for ultra-fluid 60fps+ rendering
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                display?.supportedModes?.maxByOrNull { it.refreshRate }?.let { maxMode ->
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                @Suppress("DEPRECATION")
                val modes = windowManager.defaultDisplay.supportedModes
                val maxMode = modes?.maxByOrNull { it.refreshRate }
                if (maxMode != null) {
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun collectWebViews(view: View) {
        if (view is WebView) {
            var alreadyCached = false
            synchronized(cachedWebViews) {
                for (ref in cachedWebViews) {
                    if (ref.get() === view) {
                        alreadyCached = true
                        break
                    }
                }
                if (!alreadyCached) {
                    cachedWebViews.add(java.lang.ref.WeakReference(view))
                }
            }
            try {
                view.settings.mediaPlaybackRequiresUserGesture = false
            } catch (_: Throwable) {}
        } else if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                collectWebViews(view.getChildAt(i))
            }
        }
    }

    private fun notifyWebViewsForeground() {
        try {
            window.decorView?.let { collectWebViews(it) }
        } catch (_: Throwable) {}
        synchronized(cachedWebViews) {
            val iterator = cachedWebViews.iterator()
            while (iterator.hasNext()) {
                val wv = iterator.next().get()
                if (wv == null) {
                    iterator.remove()
                } else {
                    try {
                        wv.onResume()
                        wv.resumeTimers()
                        wv.dispatchWindowVisibilityChanged(View.VISIBLE)
                    } catch (_: Throwable) {}
                }
            }
        }
    }

    private fun isWifiConnected(): Boolean {
        try {
            val cm = connectivityManager ?: (getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager) ?: return false
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val activeNetwork = cm.activeNetwork ?: return false
                val caps = cm.getNetworkCapabilities(activeNetwork) ?: return false
                return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
            } else {
                @Suppress("DEPRECATION")
                val info = cm.activeNetworkInfo ?: return false
                @Suppress("DEPRECATION")
                return info.type == ConnectivityManager.TYPE_WIFI && info.isConnected
            }
        } catch (_: Throwable) {}
        return false
    }

    private fun acquirePlaybackLocks() {
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(4 * 60 * 60 * 1000L) // Safe 4-hour max timeout
            }
            // Only acquire WifiLock if actively connected to WiFi (prevents locking mobile data)
            if (isWifiConnected() && wifiLock?.isHeld != true) {
                wifiLock?.acquire()
            }
            notifyWebViewsForeground()
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    private fun releasePlaybackLocks() {
        try {
            if (!isAudioPlaying) {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    override fun onPause() {
        try {
            if (isAudioPlaying) {
                acquirePlaybackLocks()
            }
            notifyWebViewsForeground()
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        super.onPause()
    }

    override fun onStop() {
        try {
            if (isAudioPlaying) {
                acquirePlaybackLocks()
            }
            notifyWebViewsForeground()
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        try {
            if (!isAudioPlaying) {
                releasePlaybackLocks()
            }
            window.decorView?.let { collectWebViews(it) }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        try {
            networkCallback?.let {
                connectivityManager?.unregisterNetworkCallback(it)
            }
            networkCallback = null
        } catch (_: Throwable) {}

        try {
            equalizer?.release()
            equalizer = null
            loudnessEnhancer?.release()
            loudnessEnhancer = null
            bassBoost?.release()
            bassBoost = null
            virtualizer?.release()
            virtualizer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            isAudioPlaying = false
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        super.onDestroy()
    }
}
