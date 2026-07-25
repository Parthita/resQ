import 'package:flutter/foundation.dart';

import 'local_llm_service.dart';

class ModelStore extends ChangeNotifier {
  ModelStore({LocalLlmService? service})
    : _service = service ?? LocalLlmService();

  final LocalLlmService _service;
  LocalModelStatus _status = const LocalModelStatus.empty();
  bool _isBusy = false;

  LocalModelStatus get status => _status;
  bool get isBusy => _isBusy;
  // A persisted model can be loaded by the native layer on the first prompt.
  bool get isReady => _status.hasModel;

  Future<void> refresh() async {
    _status = await _service.status();
    notifyListeners();
  }

  Future<void> importAndLoad() async {
    _isBusy = true;
    notifyListeners();
    try {
      final importedStatus = await _service.pickAndImportModel();
      if (importedStatus == null) return;
      _status = await _service.loadModel();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Stream<String> generate({required String prompt, int maxTokens = 256}) {
    return _service.generate(prompt: prompt, maxTokens: maxTokens);
  }

  Future<void> unload() async {
    _isBusy = true;
    notifyListeners();
    try {
      await _service.unloadModel();
      _status = await _service.status();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
