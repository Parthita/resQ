package com.resq.app.resq

import android.content.Context
import android.util.Log
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File

class LocalLlmChannel(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var generationJob: Job? = null
    private var loadedModelPath: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "modelStatus" -> result.success(modelStatus())
            "importModel" -> importModel(call, result)
            "loadModel" -> loadModel(result)
            "generate" -> generate(call, result)
            "unloadModel" -> unloadModel(result)
            "stopGeneration" -> stopGeneration(result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        generationJob?.cancel()
        scope.cancel()
    }

    private fun importModel(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        if (sourcePath.isNullOrBlank() || !sourcePath.endsWith(".gguf", true)) {
            result.error("invalid_model", "Choose a .gguf model file.", null)
            return
        }

        scope.launch {
            try {
                val source = File(sourcePath)
                require(source.isFile && source.canRead()) { "The selected model cannot be read." }

                val directory = File(context.filesDir, "models").apply { mkdirs() }
                val destination = File(directory, "active-model.gguf")
                withContext(Dispatchers.IO) { source.copyTo(destination, overwrite = true) }
                loadedModelPath = null

                // Delete the cache copy from the file picker to avoid accumulation
                withContext(Dispatchers.IO) {
                    source.delete()
                    // Also sweep any other stale imports from previous sessions
                    File(context.cacheDir, "imports")
                        .takeIf { it.isDirectory }
                        ?.listFiles()
                        ?.forEach { it.delete() }
                }

                result.success(modelStatus())
            } catch (error: Exception) {
                Log.e(TAG, "GGUF import failed", error)
                result.error("model_import_failed", error.message, null)
            }
        }
    }

    private fun loadModel(result: MethodChannel.Result) {
        scope.launch {
            try {
                val model = activeModel() ?: error("No GGUF model has been imported.")
                val engine = awaitEngine()

                if (loadedModelPath != model.absolutePath) {
                    Log.i(TAG, "LOAD: fresh load — model not in memory yet")
                    if (engine.state.value.isModelLoaded) {
                        Log.i(TAG, "LOAD: unloading previous model first")
                        engine.cleanUp()
                    }
                    engine.loadModel(model.absolutePath)
                    engine.setSystemPrompt(systemPrompt)
                    loadedModelPath = model.absolutePath
                    Log.i(TAG, "LOAD: model ready")
                } else {
                    Log.i(TAG, "LOAD: skipped — model already loaded at %s".format(model.absolutePath))
                }
                result.success(modelStatus())
            } catch (error: Exception) {
                Log.e(TAG, "GGUF model load failed", error)
                result.error("model_load_failed", error.message, null)
            }
        }
    }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val prompt = call.argument<String>("prompt")?.trim()
        val maxTokens = call.argument<Int>("maxTokens") ?: 256
        if (prompt.isNullOrEmpty()) {
            result.error("empty_prompt", "A prompt is required.", null)
            return
        }
        if (generationJob?.isActive == true) {
            result.error("generation_busy", "The local model is already generating.", null)
            return
        }

        generationJob = scope.launch {
            val tStart = System.nanoTime()
            var tLoadEnd = tStart
            try {
                loadIfNeeded()
                tLoadEnd = System.nanoTime()
                val engine = awaitEngine()
                val tGenStart = System.nanoTime()
                var tokenCount = 0
                var firstTokenTime = tGenStart

                engine.sendUserPrompt(prompt, maxTokens).collect { token ->
                    if (tokenCount == 0) firstTokenTime = System.nanoTime()
                    tokenCount++
                    channel.invokeMethod("token", mapOf("value" to token))
                }
                val tEnd = System.nanoTime()

                val setupMs = (tLoadEnd - tStart) / 1_000_000
                val ttftMs = (firstTokenTime - tGenStart) / 1_000_000
                val totalMs = (tEnd - tGenStart) / 1_000_000
                val tps = if (totalMs > 0) (tokenCount * 1000.0 / totalMs) else 0.0

                Log.i(TAG, "PERF: setup=%dms | ttft=%dms | tokens=%d | total=%dms | %.1f tok/s"
                    .format(setupMs, ttftMs, tokenCount, totalMs, tps))
                Log.i(TAG, "PERF: model was %salready loaded"
                    .format(if (loadedModelPath != null) "" else "NOT "))

                channel.invokeMethod("generationComplete", null)
                result.success(null)
            } catch (error: Exception) {
                Log.e(TAG, "GGUF generation failed", error)
                channel.invokeMethod("generationError", mapOf("message" to (error.message ?: "Local generation failed.")))
                result.error("generation_failed", error.message, null)
            }
        }
    }

    private fun unloadModel(result: MethodChannel.Result) {
        scope.launch {
            try {
                generationJob?.cancel()
                val engine = awaitEngine()
                if (engine.state.value.isModelLoaded) engine.cleanUp()
                loadedModelPath = null
                result.success(modelStatus())
            } catch (error: Exception) {
                Log.e(TAG, "GGUF model unload failed", error)
                result.error("model_unload_failed", error.message, null)
            }
        }
    }

    private fun stopGeneration(result: MethodChannel.Result) {
        generationJob?.cancel()
        generationJob = null
        scope.launch {
            try {
                val engine = awaitEngine()
                engine.cancelGeneration()
            } catch (_: Exception) { }
        }
        result.success(null)
    }

    private suspend fun loadIfNeeded() {
        val model = activeModel() ?: error("No GGUF model has been imported.")
        if (loadedModelPath == model.absolutePath) {
            Log.i(TAG, "LOADIFNEEDED: context reused — model already loaded, skipping init")
            return
        }

        Log.i(TAG, "LOADIFNEEDED: model not loaded — performing full init (load + system prompt)")
        val engine = awaitEngine()
        if (engine.state.value.isModelLoaded) {
            Log.i(TAG, "LOADIFNEEDED: unloading stale model before loading new one")
            engine.cleanUp()
        }
        engine.loadModel(model.absolutePath)
        engine.setSystemPrompt(systemPrompt)
        loadedModelPath = model.absolutePath
        Log.i(TAG, "LOADIFNEEDED: model init complete")
    }

    private suspend fun awaitEngine(): InferenceEngine {
        val engine = AiChat.getInferenceEngine(context)
        withTimeout(20_000) {
            engine.state.filter {
                it is InferenceEngine.State.Initialized ||
                    it is InferenceEngine.State.ModelReady ||
                    it is InferenceEngine.State.Error
            }.first()
        }
        return engine
    }

    private fun activeModel(): File? {
        val model = File(context.filesDir, "models/active-model.gguf")
        return model.takeIf { it.isFile && it.canRead() }
    }

    private fun modelStatus(): Map<String, Any> {
        val model = activeModel()
        return mapOf(
            "hasModel" to (model != null),
            "isLoaded" to (loadedModelPath != null),
            "sizeBytes" to (model?.length() ?: 0L),
        )
    }

    companion object {
        private const val TAG = "ResQModel"
        private val InferenceEngine.State.isModelLoaded: Boolean
            get() = this is InferenceEngine.State.ModelReady ||
                this is InferenceEngine.State.Generating ||
                this is InferenceEngine.State.ProcessingUserPrompt ||
                this is InferenceEngine.State.ProcessingSystemPrompt

        private const val systemPrompt = "You are resQ. Answer in 2-3 words minimum, max 2 sentences. Stay in that range unless the user asks for more. When context is given, answer only from it."
    }
}
