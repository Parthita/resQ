package com.resq.app.resq

import android.app.Activity
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/** Copies a selected SAF document into cache so Dart always receives a readable path. */
class LocalFilePickerChannel(
    private val activity: FlutterActivity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var pendingResult: MethodChannel.Result? = null
    private var requestedExtension = "file"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickSingle") {
            result.notImplemented()
            return
        }
        if (pendingResult != null) {
            result.error("picker_busy", "A file picker is already open.", null)
            return
        }

        val extensions = call.argument<List<String>>("extensions").orEmpty()
        requestedExtension = extensions.firstOrNull()?.lowercase() ?: "file"
        pendingResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (requestedExtension == "pdf") "application/pdf" else "*/*"
        }
        activity.startActivityForResult(intent, REQUEST_CODE)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        pendingResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }

        scope.launch {
            try {
                val importDirectory = File(activity.cacheDir, "imports").apply { mkdirs() }
                val destination = File(importDirectory, "${UUID.randomUUID()}.$requestedExtension")
                withContext(Dispatchers.IO) {
                    activity.contentResolver.openInputStream(uri)?.use { input ->
                        destination.outputStream().use(input::copyTo)
                    } ?: error("The selected file could not be opened.")
                }
                result.success(destination.absolutePath)
            } catch (error: Exception) {
                Log.e(TAG, "Selected file copy failed", error)
                result.error("file_copy_failed", error.message, null)
            }
        }
        return true
    }

    fun dispose() = scope.cancel()

    private companion object {
        const val TAG = "ResQFilePicker"
        const val REQUEST_CODE = 4821
    }
}
