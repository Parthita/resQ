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
                    if (engine.state.value.isModelLoaded) engine.cleanUp()
                    engine.loadModel(model.absolutePath)
                    engine.setSystemPrompt(systemPrompt)
                    loadedModelPath = model.absolutePath
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
            try {
                loadIfNeeded()
                val engine = awaitEngine()
                engine.sendUserPrompt(prompt, maxTokens).collect { token ->
                    channel.invokeMethod("token", mapOf("value" to token))
                }
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

    private suspend fun loadIfNeeded() {
        val model = activeModel() ?: error("No GGUF model has been imported.")
        if (loadedModelPath == model.absolutePath) return

        val engine = awaitEngine()
        if (engine.state.value.isModelLoaded) engine.cleanUp()
        engine.loadModel(model.absolutePath)
        engine.setSystemPrompt(systemPrompt)
        loadedModelPath = model.absolutePath
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

        private const val systemPrompt = """
You are resQ, an offline emergency and document assistant.
When retrieved document context is provided, answer only from that context.
Keep answers concise, preserve page citations, and say when the context is insufficient.
Do not invent medical, legal, or safety facts.
"""
    }
}
