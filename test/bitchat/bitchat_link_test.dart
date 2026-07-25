import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/bitchat/bitchat_link.dart';

void main() {
  group('MockBitchatLink', () {
    test('paired links deliver frames both ways after start()', () async {
      final a = MockBitchatLink(label: 'a');
      final b = MockBitchatLink(label: 'b');
      a.pairWith(b);

      final receivedByB = <Uint8List>[];
      b.received.listen(receivedByB.add);

      await a.start();
      await b.start();

      final frame = Uint8List.fromList([1, 2, 3, 4, 5]);
      final ok = await a.send(frame);
      expect(ok, isTrue);

      // give the async delivery a tick
      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedByB.length, 1);
      expect(receivedByB.first, frame);

      await a.stop();
      await b.stop();
    });

    test('a never-started link does not deliver frames', () async {
      final a = MockBitchatLink();
      final b = MockBitchatLink();
      a.pairWith(b);
      // neither started

      final got = <Uint8List>[];
      b.received.listen(got.add);
      await a.send(Uint8List.fromList([9, 9]));
      await Future.delayed(const Duration(milliseconds: 10));
      // a was never started so _deliver() is a no-op
      expect(got, isEmpty);

      await a.stop();
      await b.stop();
    });

    test('records sent frames for assertions', () async {
      final a = MockBitchatLink();
      final b = MockBitchatLink();
      a.pairWith(b);
      await a.start();
      await b.start();
      await a.send(Uint8List.fromList([7]));
      await a.send(Uint8List.fromList([8]));
      expect(a.sentFrames.length, 2);
      await a.stop();
      await b.stop();
    });
  });
}
