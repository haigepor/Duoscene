package com.example.duoscene

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var playerChannel: MethodChannel? = null
    private var galleryPermission: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duoscene/player")
        playerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success("${info.versionName} (${if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()})")
                }
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text == null || text.length > 4096) {
                        result.error("INVALID_TEXT", "Invalid share text", null)
                    } else {
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }, "分享观影邀请"))
                        result.success(null)
                    }
                }
                "getAndroidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                "isNetworkMetered" -> result.success((getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).isActiveNetworkMetered)
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature("android.software.picture_in_picture")) {
                        try {
                            val width = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
                            val height = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
                            val aspect = width.toDouble() / height
                            val ratio = if (aspect in (1.0 / 2.39)..2.39) Rational(width, height) else Rational(16,9)
                            result.success(enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(ratio).build()))
                        } catch (_: Exception) { result.success(false) }
                    } else { result.success(false) }
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 103)
                    }
                    result.success(null)
                }
                "requestGalleryPermission" -> {
                    if (Build.VERSION.SDK_INT >= 29 || checkSelfPermission("android.permission.WRITE_EXTERNAL_STORAGE") == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else if (galleryPermission != null) {
                        result.error("BUSY", "Permission request in progress", null)
                    } else {
                        galleryPermission = result
                        requestPermissions(arrayOf("android.permission.WRITE_EXTERNAL_STORAGE"), 104)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onPictureInPictureModeChanged(inPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPictureInPictureMode, newConfig)
        playerChannel?.invokeMethod("pipChanged", inPictureInPictureMode)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 104) {
            galleryPermission?.success(grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
            galleryPermission = null
        }
    }
}
