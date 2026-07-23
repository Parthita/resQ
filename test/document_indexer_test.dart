import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/document_indexer.dart';
import 'package:resq/core/offline_contracts.dart';

void main() {
  const search = LocalDocumentSearch();
  const sections = [
    DocumentSection(
      documentId: 'guide',
      pageNumber: 2,
      sectionNumber: 0,
      text: 'Carry enough water and refill only from verified water sources.',
    ),
    DocumentSection(
      documentId: 'guide',
      pageNumber: 8,
      sectionNumber: 0,
      text:
          'If a person shows signs of heat stroke, cool them rapidly and seek emergency help.',
    ),
    DocumentSection(
      documentId: 'guide',
      pageNumber: 11,
      sectionNumber: 0,
      text: 'The camp meeting point is beside the trail marker.',
    ),
  ];

  test('ranks locally matched sections and retains their page citation', () {
    final hits = search.search(query: 'heat stroke help', sections: sections);

    expect(hits, hasLength(1));
    expect(hits.single.section.pageNumber, 8);
    expect(hits.single.section.text, contains('heat stroke'));
  });

  test('returns no hit when local sections do not match the query', () {
    final hits = search.search(query: 'avalanche beacon', sections: sections);

    expect(hits, isEmpty);
  });
}
