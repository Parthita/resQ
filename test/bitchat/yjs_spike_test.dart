import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

/// Spike: prove yjs_dart converges two docs on this runtime (host Dart VM /
/// Android arm64). If this passes, the M6 CRDT tunnel is viable with no
/// WASM/JS interop risk.
///
/// Key gotcha discovered: yjs_dart's applyUpdate instantiates shared types
/// from the binary as a generic YMap. So the receiving doc must pre-create
/// the named YText (or YMap/YArray) BEFORE applying updates, otherwise a
/// later getText() hits a YMap/YText cast mismatch. We pre-declare types.
void main() {
  test('two Y.Docs converge via state-as-update exchange', () {
    final docA = Doc();
    final docB = Doc();

    // Pre-declare the text type on BOTH docs so applyUpdate binds correctly.
    docA.getText('shared');
    docB.getText('shared');

    docA.transact((tr) {
      docA.getText('shared')!.insert(0, 'hello ');
    });

    applyUpdate(docB, encodeStateAsUpdate(docA));
    expect(docB.getText('shared')!.toString(), 'hello ');

    docA.transact((tr) {
      final t = docA.getText('shared')!;
      t.insert(t.length, 'from A');
    });
    docB.transact((tr) {
      final t = docB.getText('shared')!;
      t.insert(t.length, 'from B');
    });

    applyUpdate(docB, encodeStateAsUpdate(docA));
    applyUpdate(docA, encodeStateAsUpdate(docB));

    final sa = docA.getText('shared')!.toString();
    final sb = docB.getText('shared')!.toString();
    expect(sa, sb);
    expect(sa, contains('hello '));
    expect(sa, contains('from A'));
    expect(sa, contains('from B'));
  });

  test('state vector based incremental sync avoids resending', () {
    final docA = Doc();
    final docB = Doc();
    docA.getText('x');
    docB.getText('x');
    docA.transact((tr) => docA.getText('x')!.insert(0, 'abc'));
    applyUpdate(docB, encodeStateAsUpdate(docA));

    docA.transact((tr) => docA.getText('x')!.insert(3, 'def'));
    applyUpdate(docB, encodeStateAsUpdate(docA));
    expect(docB.getText('x')!.toString(), 'abcdef');
  });

  test('updates are Uint8List and bounded for BLE frames', () {
    final doc = Doc();
    doc.getText('t');
    doc.transact((tr) => doc.getText('t')!.insert(0, 'some content'));
    final update = encodeStateAsUpdate(doc);
    expect(update, isA<Uint8List>());
    expect(update.length, lessThan(469 * 3));
  });
}
