import 'dart:async';

import 'package:flutter/services.dart';

import 'local_file_picker.dart';

class LocalModelStatus {
  const LocalModelStatus({
    required this.hasModel,
    required this.isLoaded,
    required this.sizeBytes,
  });

  const LocalModelStatus.empty()
    : hasModel = false,
      isLoaded = false,
      sizeBytes = 0;

  final bool hasModel;
  final bool isLoaded;
  final int sizeBytes;

  factory LocalModelStatus.fromMap(Map<Object?, Object?> values) {
    return LocalModelStatus(
      hasModel: values['hasModel'] as bool? ?? false,
      isLoaded: values['isLoaded'] as bool? ?? false,
      sizeBytes: values['sizeBytes'] as int? ?? 0,
    );
  }
}

class LocalLlmService {
  LocalLlmService() {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  static const _channel = MethodChannel('resq.local_llm');
  StreamController<String>? _generationController;

  Future<LocalModelStatus> status() async {
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'modelStatus',
    );
    return LocalModelStatus.fromMap(values ?? const {});
  }

  Future<LocalModelStatus?> pickAndImportModel() async {
    final path = await LocalFilePicker.pickSingle(
      extensions: const ['gguf'],
    );
    if (path == null) return null;

    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'importModel',
      {'sourcePath': path},
    );
    return LocalModelStatus.fromMap(values ?? const {});
  }

  Future<LocalModelStatus> loadModel() async {
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'loadModel',
    );
    return LocalModelStatus.fromMap(values ?? const {});
  }

  Stream<String> generate({required String prompt, int maxTokens = 256}) {
    if (_generationController != null) {
      throw const LocalModelException('The local model is already generating.');
    }

    final controller = StreamController<String>();
    _generationController = controller;
    unawaited(
      _channel
          .invokeMethod<void>('generate', {
            'prompt': prompt,
            'maxTokens': maxTokens,
          })
          .then((_) => _closeGeneration())
          .catchError((Object error) {
            if (!controller.isClosed) controller.addError(error);
            _closeGeneration();
          }),
    );
    return controller.stream;
  }

  Future<void> unloadModel() async {
    await _channel.invokeMethod<void>('unloadModel');
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    final controller = _generationController;
    if (controller == null) return;

    switch (call.method) {
      case 'token':
        final values = call.arguments as Map<Object?, Object?>;
        controller.add(values['value'] as String? ?? '');
        return;
      case 'generationComplete':
        _closeGeneration();
        return;
      case 'generationError':
        final values = call.arguments as Map<Object?, Object?>;
        controller.addError(
          LocalModelException(
            values['message'] as String? ?? 'Generation failed.',
          ),
        );
        _closeGeneration();
        return;
    }
  }

  void _closeGeneration() {
    final controller = _generationController;
    _generationController = null;
    if (controller != null && !controller.isClosed) controller.close();
  }
}

class LocalModelException implements Exception {
  const LocalModelException(this.message);

  final String message;

  @override
  String toString() => message;
}
