package com.resq.app.resq

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var localLlmChannel: LocalLlmChannel
    private lateinit var localFilePickerChannel: LocalFilePickerChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "resq.local_llm",
        )
        localLlmChannel = LocalLlmChannel(this, channel)
        channel.setMethodCallHandler(localLlmChannel)

        val filePicker = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "resq.file_picker",
        )
        localFilePickerChannel = LocalFilePickerChannel(this, filePicker)
        filePicker.setMethodCallHandler(localFilePickerChannel)

        val platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "resq.platform",
        )
        platformChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdk" -> result.success(Build.VERSION.SDK_INT)
                "isPowerSaveMode" -> result.success(isPowerSaveMode())
                "isFlashlightAvailable" -> result.success(isFlashlightAvailable())
                "flashlightOn" -> {
                    setFlashlight(true)
                    result.success(true)
                }
                "flashlightOff" -> {
                    setFlashlight(false)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPowerSaveMode(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isPowerSaveMode
    }

    private fun isFlashlightAvailable(): Boolean {
        return try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                    val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE)
                    if (hasFlash == true) return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun setFlashlight(on: Boolean) {
        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cameraManager.setTorchMode(id, on)
                    return
                }
            }
        } catch (_: Exception) {
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (::localFilePickerChannel.isInitialized &&
            localFilePickerChannel.handleActivityResult(requestCode, resultCode, data)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (::localLlmChannel.isInitialized) localLlmChannel.dispose()
        if (::localFilePickerChannel.isInitialized) localFilePickerChannel.dispose()
        super.onDestroy()
    }
}
