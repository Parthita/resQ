import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/bitchat/bitchat_link.dart';
import 'package:resq/core/bitchat/bitchat_packet.dart';
import 'package:resq/core/bitchat/flood_router.dart';
import 'package:resq/core/bitchat/identity_service.dart';
import 'package:resq/core/bitchat/message_type.dart';
import 'package:resq/core/bitchat/tlv_announce.dart';

Uint8List id8(List<int> b) => Uint8List.fromList(b);

void main() {
  group('FloodRouter (mock mesh)', () {
    test('a packet floods A -> B -> C and is delivered at C exactly once',
        () async {
      // topology: A-B, B-C (chain). A and C not directly linked.
      final a = MockBitchatLink(label: 'A');
      final b = MockBitchatLink(label: 'B');
      final c = MockBitchatLink(label: 'C');
      a.pairWith(b);
      b.pairWith(c);

      final routerA = FloodRouter(link: a);
      final routerB = FloodRouter(link: b);
      final routerC = FloodRouter(link: c);
      await routerA.start();
      await routerB.start();
      await routerC.start();

      final deliveredAtC = <BitchatPacket>[];
      routerC.delivered.listen(deliveredAtC.add);

      final sender = id8([1, 2, 3, 4, 5, 6, 7, 8]);
      final msg = BitchatPacket(
        type: MessageType.message.value,
        senderId: sender,
        timestamp: 12345,
        payload: Uint8List.fromList('hello chain'.codeUnits),
        ttl: 5,
      );
      await routerA.broadcast(msg);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(deliveredAtC.length, 1);
      expect(String.fromCharCodes(deliveredAtC.first.payload), 'hello chain');

      // B must NOT redeliver / loop (dedup). Give extra time to be sure.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(deliveredAtC.length, 1);

      await routerA.stop();
      await routerB.stop();
      await routerC.stop();
    });

    test('TTL bounds propagation: ttl=1 does not cross one hop', () async {
      final a = MockBitchatLink(label: 'A');
      final b = MockBitchatLink(label: 'B');
      final c = MockBitchatLink(label: 'C');
      a.pairWith(b);
      b.pairWith(c);
      final routerA = FloodRouter(link: a);
      final routerB = FloodRouter(link: b);
      final routerC = FloodRouter(link: c);
      await routerA.start();
      await routerB.start();
      await routerC.start();

      final atC = <BitchatPacket>[];
      routerC.delivered.listen(atC.add);

      final sender = id8([9, 9, 9, 9, 9, 9, 9, 9]);
      final msg = BitchatPacket(
        type: MessageType.message.value,
        senderId: sender,
        timestamp: 1,
        payload: Uint8List.fromList([1, 2, 3]),
        ttl: 1, // only reaches B, not C
      );
      await routerA.broadcast(msg);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(atC, isEmpty);

      await routerA.stop();
      await routerB.stop();
      await routerC.stop();
    });

    test('signature verifier drops forged packets', () async {
      final sender = MockBitchatLink(label: 'S');
      final receiver = MockBitchatLink(label: 'R');
      sender.pairWith(receiver);

      // verifier that always says "no" -> everything dropped
      final routerR = FloodRouter(
        link: receiver,
        signatureVerifier: (_) async => false,
      );
      await sender.start();
      await routerR.start();

      final got = <BitchatPacket>[];
      routerR.delivered.listen(got.add);

      final sid = id8([1, 1, 1, 1, 1, 1, 1, 1]);
      final msg = BitchatPacket(
        type: MessageType.message.value,
        senderId: sid,
        timestamp: 99,
        payload: Uint8List.fromList([7, 7]),
        ttl: 3,
      );
      await sender.send(BinaryProtocol.encode(msg, padding: false));
      await Future.delayed(const Duration(milliseconds: 30));
      expect(got, isEmpty);

      await sender.stop();
      await routerR.stop();
    });

    test('signed packet passes a real Ed25519 verifier end-to-end', () async {
      final id = await MeshIdentity.generate();
      final sender = MockBitchatLink(label: 'S');
      final receiver = MockBitchatLink(label: 'R');
      sender.pairWith(receiver);

      final routerS = FloodRouter(link: sender);
      final routerR = FloodRouter(
        link: receiver,
        signatureVerifier: (p) => MeshIdentity.verifyPacket(p, id.signingPublicKey),
      );
      await routerS.start();
      await routerR.start();

      final got = <BitchatPacket>[];
      routerR.delivered.listen(got.add);

      final msg = BitchatPacket(
        type: MessageType.message.value,
        senderId: id.senderId,
        timestamp: 555,
        payload: Uint8List.fromList('signed'.codeUnits),
        ttl: 3,
      );
      final signed = await id.signPacket(msg);
      await routerS.broadcast(signed); // go through the router (fragment path)
      await Future.delayed(const Duration(milliseconds: 30));
      expect(got.length, 1);
      expect(String.fromCharCodes(got.first.payload), 'signed');

      await routerS.stop();
      await routerR.stop();
    });
  });

  group('TlvAnnounce', () {
    test('round-trips nickname + noise key + signing key (interop-critical)',
        () async {
      final id = await MeshIdentity.generate();
      final ann = TlvAnnounce(
        nickname: 'resQ-node',
        noisePublicKey: id.noisePublicKey,
        signingPublicKey: id.signingPublicKey,
        capabilities: 1,
        neighbors: ['abcdef0123456789'],
      );
      final bytes = ann.encode();
      final back = TlvAnnounce.decode(bytes);
      expect(back.nickname, 'resQ-node');
      expect(back.noisePublicKey, id.noisePublicKey);
      expect(back.signingPublicKey, id.signingPublicKey);
      expect(back.capabilities, 1);
    });

    test('decodes with missing optional fields without throwing', () {
      final minimal = TlvAnnounce(
        nickname: 'x',
        noisePublicKey: Uint8List(32),
        signingPublicKey: Uint8List(32),
      ).encode();
      final back = TlvAnnounce.decode(minimal);
      expect(back.nickname, 'x');
      expect(back.noisePublicKey.length, 32);
      expect(back.signingPublicKey.length, 32);
    });
  });
}
