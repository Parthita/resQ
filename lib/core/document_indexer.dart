import 'package:pdfrx/pdfrx.dart';

import 'offline_contracts.dart';

class DocumentIndexResult {
  const DocumentIndexResult({
    required this.pageCount,
    required this.sections,
    required this.state,
  });

  final int pageCount;
  final List<DocumentSection> sections;
  final DocumentIndexState state;
}

class PdfDocumentIndexer {
  const PdfDocumentIndexer();

  static const _sectionLength = 900;
  static const _sectionOverlap = 140;

  Future<DocumentIndexResult> index(LocalDocument document) async {
    await pdfrxFlutterInitialize();
    final pdf = await PdfDocument.openFile(document.filePath);

    try {
      final sections = <DocumentSection>[];

      for (final page in pdf.pages) {
        final pageText = await page.loadStructuredText();
        final normalizedText = _normalize(pageText.fullText);
        if (normalizedText.isEmpty) continue;

        final pageSections = _splitIntoSections(normalizedText);
        for (var index = 0; index < pageSections.length; index++) {
          sections.add(
            DocumentSection(
              documentId: document.id,
              pageNumber: page.pageNumber,
              sectionNumber: index,
              text: pageSections[index],
            ),
          );
        }
      }

      return DocumentIndexResult(
        pageCount: pdf.pages.length,
        sections: sections,
        state: sections.isEmpty
            ? DocumentIndexState.needsOcr
            : DocumentIndexState.ready,
      );
    } finally {
      await pdf.dispose();
    }
  }

  List<String> _splitIntoSections(String text) {
    if (text.length <= _sectionLength) return [text];

    final sections = <String>[];
    var remaining = text;

    while (remaining.length > _sectionLength) {
      var splitAt = remaining.lastIndexOf('\n', _sectionLength);
      if (splitAt < _sectionLength ~/ 2) {
        splitAt = remaining.lastIndexOf(' ', _sectionLength);
      }
      if (splitAt < _sectionLength ~/ 2) splitAt = _sectionLength;

      final section = remaining.substring(0, splitAt).trim();
      if (section.isNotEmpty) sections.add(section);

      final overlapStart = splitAt > _sectionOverlap
          ? splitAt - _sectionOverlap
          : splitAt;
      remaining = remaining.substring(overlapStart).trimLeft();
    }

    if (remaining.isNotEmpty) sections.add(remaining);
    return sections;
  }

  String _normalize(String text) {
    return text
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }
}

class LocalDocumentSearch {
  const LocalDocumentSearch();

  List<DocumentSearchHit> search({
    required String query,
    required List<DocumentSection> sections,
    int limit = 4,
  }) {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];

    final phrase = query.trim().toLowerCase();
    final hits = <DocumentSearchHit>[];

    for (final section in sections) {
      final text = section.text.toLowerCase();
      var score = 0;

      for (final term in terms) {
        score += _occurrences(text, term) * 3;
      }
      if (phrase.length > 3 && text.contains(phrase)) score += 8;
      if (score > 0) {
        hits.add(DocumentSearchHit(section: section, score: score));
      }
    }

    hits.sort((a, b) {
      final scoreComparison = b.score.compareTo(a.score);
      if (scoreComparison != 0) return scoreComparison;
      return a.section.pageNumber.compareTo(b.section.pageNumber);
    });
    return hits.take(limit).toList(growable: false);
  }

  List<String> _terms(String query) {
    const punctuation = r'''.,!?;:()[]{}"'`~@#%^&*=+\\/<>|_-''';
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(
          (word) => word
              .split('')
              .where((character) => !punctuation.contains(character))
              .join(),
        )
        .where((word) => word.runes.length > 1)
        .toSet()
        .toList(growable: false);
  }

  int _occurrences(String text, String term) {
    var count = 0;
    var start = 0;

    while (true) {
      final position = text.indexOf(term, start);
      if (position == -1) return count;
      count++;
      start = position + term.length;
    }
  }
}
