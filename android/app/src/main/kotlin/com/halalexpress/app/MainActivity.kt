package com.halalexpress.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val VIBRATE_CHANNEL = "com.halalexpress/vibrate"
    private val INSTALL_CHANNEL = "com.halalexpress/install_permission"
    private val INSTALL_APK_CHANNEL = "com.halalexpress/install_apk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    val duration = (call.arguments as? Double)?.toLong() ?: 500L
                    vibrate(duration)
                    result.success(true)
                }
                "cancel" -> {
                    cancelVibration()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(canInstall)
                }
                "openInstallSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_APK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.arguments as? String
                    if (filePath == null) {
                        result.error("INVALID_ARG", "File path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(filePath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        if (!file.exists()) throw Exception("APK file not found: $filePath")

        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        startActivity(intent)
    }

    private fun vibrate(durationMs: Long) {
        val vibrator = getVibrator()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }

    private fun cancelVibration() {
        getVibrator().cancel()
    }

    private fun getVibrator(): Vibrator {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }
}
