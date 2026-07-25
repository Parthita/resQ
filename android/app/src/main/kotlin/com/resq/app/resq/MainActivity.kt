package com.resq.app.resq

import android.content.Intent
import android.os.Build
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "resq.platform",
        ).setMethodCallHandler { call, result ->
            if (call.method == "androidSdk") result.success(Build.VERSION.SDK_INT)
            else result.notImplemented()
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
