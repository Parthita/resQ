import 'dart:async';

import 'package:flutter/foundation.dart';

import 'document_indexer.dart';
import 'local_document_repository.dart';
import 'local_file_picker.dart';
import 'offline_contracts.dart';

class DocumentStore extends ChangeNotifier {
  DocumentStore({
    LocalDocumentRepository? repository,
    PdfDocumentIndexer? indexer,
    LocalDocumentSearch? search,
  }) : _repository = repository ?? LocalDocumentRepository(),
       _indexer = indexer ?? const PdfDocumentIndexer(),
       _search = search ?? const LocalDocumentSearch();

  final LocalDocumentRepository _repository;
  final PdfDocumentIndexer _indexer;
  final LocalDocumentSearch _search;

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

    for (final document in _documents) {
      if (document.indexState == DocumentIndexState.pending) {
        unawaited(_index(document));
      }
    }
  }

  Future<LocalDocument?> pickAndImportPdf() async {
    final path = await LocalFilePicker.pickSingle(
      extensions: const ['pdf'],
    );
    if (path == null) return null;

    final document = await _repository.importPdf(
      sourcePath: path,
      displayName: path.split('/').last,
    );
    final indexingDocument = document.copyWith(
      indexState: DocumentIndexState.indexing,
    );
    _documents = [indexingDocument, ..._documents];
    notifyListeners();
    await _repository.update(indexingDocument);
    return _index(document);
  }

  Future<void> delete(LocalDocument document) async {
    await _repository.delete(document);
    _documents = _documents.where((item) => item.id != document.id).toList();
    notifyListeners();
  }

  Future<List<DocumentSearchHit>> search(
    LocalDocument document,
    String query,
  ) async {
    if (document.indexState != DocumentIndexState.ready) return const [];

    final sections = await _repository.loadSections(document.id);
    return _search.search(query: query, sections: sections);
  }

  Future<LocalDocument> _index(LocalDocument document) async {
    final indexingDocument = document.copyWith(
      indexState: DocumentIndexState.indexing,
    );
    _replaceDocument(indexingDocument);
    await _repository.update(indexingDocument);

    try {
      final result = await _indexer.index(document);
      await _repository.saveSections(document.id, result.sections);
      final indexedDocument = document.copyWith(
        pageCount: result.pageCount,
        indexState: result.state,
      );
      await _repository.update(indexedDocument);
      _replaceDocument(indexedDocument);
      return indexedDocument;
    } catch (_) {
      final failedDocument = document.copyWith(
        indexState: DocumentIndexState.failed,
      );
      await _repository.update(failedDocument);
      _replaceDocument(failedDocument);
      return failedDocument;
    }
  }

  void _replaceDocument(LocalDocument updatedDocument) {
    _documents = _documents
        .map(
          (document) =>
              document.id == updatedDocument.id ? updatedDocument : document,
        )
        .toList(growable: false);
    notifyListeners();
  }
}
