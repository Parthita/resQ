import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:resq/core/bitchat/bitchat_link.dart';
import 'package:resq/core/bitchat/bitchat_packet.dart';
import 'package:resq/core/bitchat/flood_router.dart';
import 'package:resq/core/bitchat/identity_service.dart';
import 'package:resq/core/bitchat/sync_doc_tunnel.dart';

Uint8List id8(List<int> b) => Uint8List.fromList(b);

void main() {
  group('SyncDocTunnel (Yjs over mesh)', () {
    test('a Y.Text edit on A converges to B over the flood mesh', () async {
      final linkA = MockBitchatLink(label: 'A');
      final linkB = MockBitchatLink(label: 'B');
      linkA.pairWith(linkB);

      final routerA = FloodRouter(link: linkA);
      final routerB = FloodRouter(link: linkB);
      final tunA = SyncDocTunnel(router: routerA, senderId: id8([1, 1, 1, 1, 1, 1, 1, 1]));
      final tunB = SyncDocTunnel(router: routerB, senderId: id8([2, 2, 2, 2, 2, 2, 2, 2]));

      await tunA.start();
      await tunB.start();

      // A edits its shared text, then broadcasts the CRDT update
      tunA.text.insert(0, 'shared note: ');
      await tunA.broadcastUpdate();

      // give the mesh + apply time
      await Future.delayed(const Duration(milliseconds: 60));

      expect(tunB.text.toString(), 'shared note: ');

      // B edits; should propagate back to A (convergence both ways)
      tunB.text.insert(tunB.text.length, 'edited on B');
      await tunB.broadcastUpdate();
      await Future.delayed(const Duration(milliseconds: 60));

      final expected = 'shared note: edited on B';
      expect(tunA.text.toString(), expected);
      expect(tunB.text.toString(), expected);

      await tunA.stop();
      await tunB.stop();
    });

    test('receiver pre-declares the type so applyUpdate binds as YText', () async {
      // If we did NOT pre-declare, yjs_dart's applyUpdate would create a YMap
      // and later text access would throw. This test proves the tunnel's
      // declareText() guard prevents that.
      final linkA = MockBitchatLink(label: 'A');
      final linkB = MockBitchatLink(label: 'B');
      linkA.pairWith(linkB);
      final routerA = FloodRouter(link: linkA);
      final routerB = FloodRouter(link: linkB);
      final tunA = SyncDocTunnel(router: routerA, senderId: id8([3, 3, 3, 3, 3, 3, 3, 3]));
      final tunB = SyncDocTunnel(router: routerB, senderId: id8([4, 4, 4, 4, 4, 4, 4, 4]));
      await tunA.start();
      await tunB.start();

      tunA.text.insert(0, 'pre-declared works');
      await tunA.broadcastUpdate();
      await Future.delayed(const Duration(milliseconds: 60));

      // must not throw; text must be present on B
      expect(tunB.text.toString(), 'pre-declared works');

      await tunA.stop();
      await tunB.stop();
    });

    test('signed sender identity can be wired for verified sync (M2+M6)', () async {
      final id = await MeshIdentity.generate();
      final linkA = MockBitchatLink(label: 'A');
      final linkB = MockBitchatLink(label: 'B');
      linkA.pairWith(linkB);
      final routerA = FloodRouter(link: linkA);
      final routerB = FloodRouter(
        link: linkB,
        signatureVerifier: (p) => MeshIdentity.verifyPacket(p, id.signingPublicKey),
      );
      final tunA = SyncDocTunnel(router: routerA, senderId: id.senderId);
      final tunB = SyncDocTunnel(router: routerB, senderId: id8([5, 5, 5, 5, 5, 5, 5, 5]));
      await tunA.start();
      await tunB.start();

      // tunA must sign its sync packet with the same identity B verifies
      tunA.text.insert(0, 'verified sync ');
      final signedUpdate = await id.signPacket(BitchatPacket(
        type: 0x30,
        senderId: id.senderId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: encodeStateUpdateTunnel(tunA),
        ttl: 8,
      ));
      await routerA.broadcast(signedUpdate);
      await Future.delayed(const Duration(milliseconds: 60));

      expect(tunB.text.toString(), 'verified sync ');

      await tunA.stop();
      await tunB.stop();
    });

    test('chat messages converge A->B over the mesh (YArray)', () async {
      final linkA = MockBitchatLink(label: 'A');
      final linkB = MockBitchatLink(label: 'B');
      linkA.pairWith(linkB);
      final routerA = FloodRouter(link: linkA);
      final routerB = FloodRouter(link: linkB);
      final tunA = SyncDocTunnel(router: routerA, senderId: id8([6, 6, 6, 6, 6, 6, 6, 6]));
      final tunB = SyncDocTunnel(router: routerB, senderId: id8([7, 7, 7, 7, 7, 7, 7, 7]));
      await tunA.start();
      await tunB.start();

      await tunA.sendMessage('hello from A');
      await Future.delayed(const Duration(milliseconds: 80));

      final bMsgs = tunB.messageList;
      expect(bMsgs.length, 1);
      expect(bMsgs.first.text, 'hello from B'.replaceAll('B', 'A'));
      expect(bMsgs.first.senderId, '0606060606060606');

      // B replies; A should see it too
      await tunB.sendMessage('hi A, this is B');
      await Future.delayed(const Duration(milliseconds: 80));
      expect(tunA.messageList.length, 2);
      expect(tunA.messageList.last.text, 'hi A, this is B');

      await tunA.stop();
      await tunB.stop();
    });
  });
}

/// Helper: pull a state update from a tunnel's doc without broadcasting.
Uint8List encodeStateUpdateTunnel(SyncDocTunnel t) {
  // reuse yjs_dart directly
  return encodeStateAsUpdate(t.doc);
}
