package com.mcmusic.app.mcmusic_flutter

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.ryanheise.audioservice.AudioServiceActivity

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
            mainHandler.postDelayed(this, 1000)
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
        super.onPause()
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
    }

    override fun onStop() {
        super.onStop()
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
