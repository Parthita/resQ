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
  }

  Future<Directory> _documentDirectory() async {
    final appDirectory = await getApplicationSupportDirectory();
    final documentDirectory = Directory('${appDirectory.path}/documents');
    if (!await documentDirectory.exists()) {
      await documentDirectory.create(recursive: true);
    }
    return documentDirectory;
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
  });

  factory _DocumentRecord.fromDocument(LocalDocument document) {
    return _DocumentRecord(
      id: document.id,
      name: document.name,
      filePath: document.filePath,
      byteCount: document.byteCount,
      pageCount: document.pageCount,
      addedAt: document.addedAt.toIso8601String(),
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
    );
  }

  final String id;
  final String name;
  final String filePath;
  final int byteCount;
  final int pageCount;
  final String addedAt;

  LocalDocument toDocument() {
    return LocalDocument(
      id: id,
      name: name,
      filePath: filePath,
      byteCount: byteCount,
      pageCount: pageCount,
      addedAt: DateTime.parse(addedAt),
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
    };
  }
}
