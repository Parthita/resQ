import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_contracts.dart';

class LocalDocumentRepository {
  LocalDocumentRepository({SharedPreferencesAsync? preferences}) {
    _preferences = preferences;
  }

  static const _documentsKey = 'resq.local_documents.v1';

  SharedPreferencesAsync? _preferences;

  Future<List<LocalDocument>> loadAll() async {
    final preferences = _preferences ??= SharedPreferencesAsync();
    final encodedDocuments = await preferences.getString(_documentsKey);
    if (encodedDocuments == null || encodedDocuments.isEmpty) return const [];

    try {
      final rawDocuments = jsonDecode(encodedDocuments) as List<dynamic>;
      final documents = <LocalDocument>[];

      for (final rawDocument in rawDocuments) {
        final document = _DocumentRecord.fromJson(
          rawDocument as Map<String, dynamic>,
        ).toDocument();

        if (await File(document.filePath).exists()) {
          documents.add(document);
        }
      }

      documents.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return documents;
    } on FormatException {
      return const [];
    }
  }

  Future<LocalDocument> importPdf({
    required String sourcePath,
    required String displayName,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const DocumentStorageException(
        'The selected PDF is no longer available.',
      );
    }

    final sanitizedName = _sanitizeName(displayName);
    if (!sanitizedName.toLowerCase().endsWith('.pdf')) {
      throw const DocumentStorageException('Please select a PDF document.');
    }

    final identifier = DateTime.now().microsecondsSinceEpoch.toString();
    final directory = await _documentDirectory();
    final destination = File('${directory.path}/$identifier.pdf');
    await sourceFile.copy(destination.path);

    final document = LocalDocument(
      id: identifier,
      name: sanitizedName,
      filePath: destination.path,
      byteCount: await destination.length(),
      pageCount: 0,
      addedAt: DateTime.now().toUtc(),
    );

    final documents = await loadAll();
    await _writeAll([document, ...documents]);
    return document;
  }

  Future<void> delete(LocalDocument document) async {
    final documents = await loadAll();
    await _writeAll(documents.where((item) => item.id != document.id).toList());

    final file = File(document.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final indexFile = await _indexFile(document.id);
    if (await indexFile.exists()) {
      await indexFile.delete();
    }
  }

  Future<void> update(LocalDocument updatedDocument) async {
    final documents = await loadAll();
    await _writeAll(
      documents
          .map(
            (document) =>
                document.id == updatedDocument.id ? updatedDocument : document,
          )
          .toList(),
    );
  }

  Future<void> saveSections(
    String documentId,
    List<DocumentSection> sections,
  ) async {
    final indexFile = await _indexFile(documentId);
    final records = sections
        .map(_SectionRecord.fromSection)
        .map((record) => record.toJson())
        .toList(growable: false);
    await indexFile.writeAsString(jsonEncode(records), flush: true);
  }

  Future<List<DocumentSection>> loadSections(String documentId) async {
    final indexFile = await _indexFile(documentId);
    if (!await indexFile.exists()) return const [];

    try {
      final rawSections =
          jsonDecode(await indexFile.readAsString()) as List<dynamic>;
      return rawSections
          .map(
            (section) =>
                _SectionRecord.fromJson(section as Map<String, dynamic>),
          )
          .map((record) => record.toSection())
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<Directory> _documentDirectory() async {
    final appDirectory = await getApplicationSupportDirectory();
    final documentDirectory = Directory('${appDirectory.path}/documents');
    if (!await documentDirectory.exists()) {
      await documentDirectory.create(recursive: true);
    }
    return documentDirectory;
  }

  Future<File> _indexFile(String documentId) async {
    final appDirectory = await getApplicationSupportDirectory();
    final indexDirectory = Directory('${appDirectory.path}/indexes');
    if (!await indexDirectory.exists()) {
      await indexDirectory.create(recursive: true);
    }
    return File('${indexDirectory.path}/$documentId.json');
  }

  Future<void> _writeAll(List<LocalDocument> documents) {
    final records = documents
        .map(_DocumentRecord.fromDocument)
        .map((record) => record.toJson())
        .toList(growable: false);
    final preferences = _preferences ??= SharedPreferencesAsync();
    return preferences.setString(_documentsKey, jsonEncode(records));
  }

  String _sanitizeName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Untitled document.pdf' : trimmed;
  }
}

class DocumentStorageException implements Exception {
  const DocumentStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DocumentRecord {
  const _DocumentRecord({
    required this.id,
    required this.name,
    required this.filePath,
    required this.byteCount,
    required this.pageCount,
    required this.addedAt,
    required this.indexState,
  });

  factory _DocumentRecord.fromDocument(LocalDocument document) {
    return _DocumentRecord(
      id: document.id,
      name: document.name,
      filePath: document.filePath,
      byteCount: document.byteCount,
      pageCount: document.pageCount,
      addedAt: document.addedAt.toIso8601String(),
      indexState: document.indexState.name,
    );
  }

  factory _DocumentRecord.fromJson(Map<String, dynamic> json) {
    return _DocumentRecord(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String,
      byteCount: json['byteCount'] as int,
      pageCount: json['pageCount'] as int,
      addedAt: json['addedAt'] as String,
      indexState:
          json['indexState'] as String? ?? DocumentIndexState.pending.name,
    );
  }

  final String id;
  final String name;
  final String filePath;
  final int byteCount;
  final int pageCount;
  final String addedAt;
  final String indexState;

  LocalDocument toDocument() {
    return LocalDocument(
      id: id,
      name: name,
      filePath: filePath,
      byteCount: byteCount,
      pageCount: pageCount,
      addedAt: DateTime.parse(addedAt),
      indexState: DocumentIndexState.values.byName(indexState),
    );
  }

  Map<String, Object> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'byteCount': byteCount,
      'pageCount': pageCount,
      'addedAt': addedAt,
      'indexState': indexState,
    };
  }
}

class _SectionRecord {
  const _SectionRecord({
    required this.documentId,
    required this.pageNumber,
    required this.sectionNumber,
    required this.text,
  });

  factory _SectionRecord.fromSection(DocumentSection section) {
    return _SectionRecord(
      documentId: section.documentId,
      pageNumber: section.pageNumber,
      sectionNumber: section.sectionNumber,
      text: section.text,
    );
  }

  factory _SectionRecord.fromJson(Map<String, dynamic> json) {
    return _SectionRecord(
      documentId: json['documentId'] as String,
      pageNumber: json['pageNumber'] as int,
      sectionNumber: json['sectionNumber'] as int,
      text: json['text'] as String,
    );
  }

  final String documentId;
  final int pageNumber;
  final int sectionNumber;
  final String text;

  DocumentSection toSection() {
    return DocumentSection(
      documentId: documentId,
      pageNumber: pageNumber,
      sectionNumber: sectionNumber,
      text: text,
    );
  }

  Map<String, Object> toJson() {
    return {
      'documentId': documentId,
      'pageNumber': pageNumber,
      'sectionNumber': sectionNumber,
      'text': text,
    };
  }
}
