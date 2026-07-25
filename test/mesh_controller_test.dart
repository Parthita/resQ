import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/bitchat/bitchat_link.dart';
import 'package:resq/mesh_controller.dart';

void main() {
  group('MeshController (headless, mock link)', () {
    test('start() builds identity + router + tunnel and reaches running',
        () async {
      final link = MockBitchatLink(label: 'mock');
      final ctrl = MeshController(link: link);
      await ctrl.start();
      expect(ctrl.state, MeshState.running);
      expect(ctrl.identity.senderId.length, 8);
      await ctrl.stop();
      expect(ctrl.state, MeshState.stopped);
    });

    test('publishNote broadcasts a CRDT update the peer mesh can apply', () async {
      // two controllers on a paired mock link => acts like two phones
      final linkA = MockBitchatLink(label: 'A');
      final linkB = MockBitchatLink(label: 'B');
      linkA.pairWith(linkB);

      final ctrlA = MeshController(link: linkA);
      final ctrlB = MeshController(link: linkB);
      await ctrlA.start();
      await ctrlB.start();

      await ctrlA.publishNote('hello mesh');
      await Future.delayed(const Duration(milliseconds: 80));

      // B's synced Y.Doc should contain the note A published
      expect(ctrlB.tunnel.text.toString(), contains('hello mesh'));

      await ctrlA.stop();
      await ctrlB.stop();
    });

    test('stop then start again reaches running (toggle bug regression)', () async {
      final link = MockBitchatLink(label: 'mock');
      final ctrl = MeshController(link: link);
      await ctrl.start();
      expect(ctrl.state, MeshState.running);
      await ctrl.stop();
      expect(ctrl.state, MeshState.stopped);
      // second start must succeed (previously threw because stop() closed the
      // stream controllers AND identity/router/tunnel were late final)
      await ctrl.start();
      expect(ctrl.state, MeshState.running);
      await ctrl.stop();
    });
  });
}
