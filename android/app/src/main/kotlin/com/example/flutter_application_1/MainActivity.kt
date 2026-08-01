package com.example.campusbite

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "campusbite/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceAbi" -> result.success(deviceAbi())
                    "canRequestPackageInstalls" ->
                        result.success(canRequestPackageInstalls())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_path", "Missing APK path", null)
                        } else {
                            val launched = installApk(path)
                            if (launched) {
                                result.success(null)
                            } else {
                                result.error(
                                    "install_failed",
                                    "Could not launch the installer",
                                    null
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Primary ABI of the running device (e.g. "arm64-v8a", "x86_64").
    // Prefers the first entry of SUPPORTED_ABIS, which is the preferred ABI.
    private fun deviceAbi(): String =
        Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"

    private fun canRequestPackageInstalls(): Boolean {
        val pm = applicationContext.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pm.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallSettings() {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            intent.data = Uri.parse("package:${applicationContext.packageName}")
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // No settings activity available — nothing more we can do.
        }
    }

    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            val uri: Uri = FileProvider.getUriForFile(
                applicationContext,
                "${applicationContext.packageName}.fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            // Resolve explicitly to surface a clear error if no installer exists
            // (e.g. the permission gate on Android 8+ returns no activity).
            val resolved = packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            if (resolved == null) {
                openInstallSettings()
                false
            } else {
                startActivity(intent)
                true
            }
        } catch (_: Exception) {
            false
        }
    }
}
