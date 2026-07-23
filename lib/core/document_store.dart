import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'local_document_repository.dart';
import 'offline_contracts.dart';

class DocumentStore extends ChangeNotifier {
  DocumentStore({LocalDocumentRepository? repository})
    : _repository = repository ?? LocalDocumentRepository();

  final LocalDocumentRepository _repository;

  List<LocalDocument> _documents = const [];
  bool _isLoading = true;

  List<LocalDocument> get documents => List.unmodifiable(_documents);
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _documents = await _repository.loadAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<LocalDocument?> pickAndImportPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (result == null) return null;

    final selectedFile = result.files.single;
    final path = selectedFile.path;
    if (path == null) {
      throw const DocumentStorageException(
        'This device did not provide access to the selected PDF.',
      );
    }

    final document = await _repository.importPdf(
      sourcePath: path,
      displayName: selectedFile.name,
    );
    _documents = [document, ..._documents];
    notifyListeners();
    return document;
  }

  Future<void> delete(LocalDocument document) async {
    await _repository.delete(document);
    _documents = _documents.where((item) => item.id != document.id).toList();
    notifyListeners();
  }
}
