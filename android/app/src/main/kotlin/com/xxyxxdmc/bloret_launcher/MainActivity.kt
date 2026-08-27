package com.xxyxxdmc.bloret_launcher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.content.ComponentName
import android.util.Log
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.view.View

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xxyxxdmc.bloret_launcher"

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()

        splashScreen.setOnExitAnimationListener { splashScreenView ->

            val fadeOut = ObjectAnimator.ofFloat(
                splashScreenView.view,
                View.ALPHA,
                1f,
                0f
            )

            fadeOut.duration = 300L

            fadeOut.addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    splashScreenView.remove()
                }
            })

            fadeOut.start()
        }

        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initShizuku" -> {
                    result.success(initShizuku())
                }
                "checkShizukuPermission" -> {
                    result.success(checkShizukuPermission())
                }
                "runShizukuShell" -> {
                    val cmd = call.argument<String>("command")
                    if (cmd != null) {
                        lifecycleScope.launch {
                            val output = runShizukuShell(cmd)
                            result.success(output)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Command is null", null)
                    }
                }
                "changeIcon" -> {
                    val isNight = call.argument<Boolean>("isNight") ?: false

                    changeNightIcon(isNight)

                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    fun changeNightIcon(isNight: Boolean) {
        val pm = packageManager

        val darkIcon = ComponentName(
            this,
            "com.xxyxxdmc.bloret_launcher.DarkIcon"
        )

        val lightIcon = ComponentName(
            this,
            "com.xxyxxdmc.bloret_launcher.LightIcon"
        )

        when (isNight) {
            true -> {
                pm.setComponentEnabledSetting(
                    darkIcon,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )

                pm.setComponentEnabledSetting(
                    lightIcon,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }

            false -> {
                pm.setComponentEnabledSetting(
                    lightIcon,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP
                )

                pm.setComponentEnabledSetting(
                    darkIcon,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }
    private suspend fun runShizukuShell(command: String): String = withContext(Dispatchers.IO) {
        val result = StringBuilder()
        try {
            val process = Shizuku.newProcess(arrayOf("sh", "-c", command), null, null)

            val reader = BufferedReader(InputStreamReader(process.inputStream))
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                result.append(line).append("\n")
            }

            val errorReader = BufferedReader(InputStreamReader(process.errorStream))
            var errorLine: String?
            while (errorReader.readLine().also { errorLine = it } != null) {
                Log.e("ShizukuShell", "Error: $errorLine")
            }

            process.waitFor()
        } catch (e: Exception) {
            Log.e("ShizukuShell", "Error", e)
            return@withContext "Error: ${e.message}"
        }
        result.toString().trim()
    }

    private fun initShizuku() : Int {
        try {
            if (Shizuku.isPreV11()) return 2
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) return 0
            Shizuku.requestPermission(2525)
            return 3
        } catch (e: Exception) {
            Log.e("Shizuku Init", e.toString())
            return 1
        }
    }

    private fun checkShizukuPermission() : Boolean {
        return try {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }
}
