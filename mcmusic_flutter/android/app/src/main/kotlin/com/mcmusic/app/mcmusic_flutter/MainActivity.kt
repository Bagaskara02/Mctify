package com.mcmusic.app.mcmusic_flutter

import android.content.Context
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.Virtualizer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val keepAliveRunnable = object : Runnable {
        override fun run() {
            try {
                window.decorView?.let { keepWebViewsAlive(it) }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            mainHandler.postDelayed(this, 350)
        }
    }

    // Android Native Audio Effects (Hardware-accelerated Equalizer, Bass Boost & 3D Virtualizer)
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private val CHANNEL = "com.mcmusic.app/equalizer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initAudioEffects()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    setEffectsEnabled(enabled)
                    result.success(true)
                }
                "setBands" -> {
                    val rawBands = call.argument<List<*>>("bands")
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    if (rawBands != null) {
                        val bands = rawBands.mapNotNull { item ->
                            when (item) {
                                is Number -> item.toDouble()
                                else -> null
                            }
                        }
                        applyBands(bands, enabled)
                    }
                    result.success(true)
                }
                "setBandLevel" -> {
                    val band = call.argument<Int>("band") ?: 0
                    val levelDb = (call.argument<Number>("level"))?.toDouble() ?: 0.0
                    applyBandLevel(band, levelDb)
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
                else -> result.notImplemented()
            }
        }
    }

    private fun initAudioEffects() {
        try {
            if (equalizer == null) {
                equalizer = Equalizer(1000, 0).apply {
                    enabled = true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            if (bassBoost == null) {
                bassBoost = BassBoost(1000, 0).apply {
                    enabled = true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            if (virtualizer == null) {
                virtualizer = Virtualizer(1000, 0).apply {
                    enabled = true
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
            bassBoost?.enabled = enabled
            virtualizer?.enabled = enabled
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyBandLevel(bandIndex: Int, levelDb: Double) {
        try {
            initAudioEffects()
            equalizer?.let { eq ->
                val numBands = eq.numberOfBands.toInt()
                if (bandIndex in 0 until numBands) {
                    val range = eq.bandLevelRange
                    val min = range[0].toInt()
                    val max = range[1].toInt()
                    val targetMb = (levelDb * 100).toInt().coerceIn(min, max).toShort()
                    eq.setBandLevel(bandIndex.toShort(), targetMb)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun applyBands(bands: List<Double>, enabled: Boolean) {
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
                        val targetMb = (bands[i] * 100).toInt().coerceIn(min, max).toShort()
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun keepWebViewsAlive(view: View) {
        if (view is WebView) {
            try {
                view.onResume()
                view.resumeTimers()
                view.dispatchWindowVisibilityChanged(View.VISIBLE)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                keepWebViewsAlive(view.getChildAt(i))
            }
        }
    }

    override fun onPause() {
        try {
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
            window.decorView?.let { keepWebViewsAlive(it) }
            mainHandler.removeCallbacks(keepAliveRunnable)
            mainHandler.post(keepAliveRunnable)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onPause()
        try {
            window.decorView?.let { keepWebViewsAlive(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStop() {
        try {
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(24 * 60 * 60 * 1000L)
            }
            window.decorView?.let { keepWebViewsAlive(it) }
            mainHandler.removeCallbacks(keepAliveRunnable)
            mainHandler.post(keepAliveRunnable)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onStop()
        try {
            window.decorView?.let { keepWebViewsAlive(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            mainHandler.removeCallbacks(keepAliveRunnable)
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            window.decorView?.let { keepWebViewsAlive(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        try {
            equalizer?.release()
            equalizer = null
            bassBoost?.release()
            bassBoost = null
            virtualizer?.release()
            virtualizer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            mainHandler.removeCallbacks(keepAliveRunnable)
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        super.onDestroy()
    }
}
