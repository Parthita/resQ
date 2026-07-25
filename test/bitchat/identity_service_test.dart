import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/bitchat/bitchat_packet.dart';
import 'package:resq/core/bitchat/identity_service.dart';
import 'package:resq/core/bitchat/message_type.dart';

Uint8List id8(List<int> b) => Uint8List.fromList(b);

void main() {
  group('MeshIdentity', () {
    test('derives an 8-byte senderId from the Noise static public key', () async {
      final id = await MeshIdentity.generate();
      expect(id.senderId.length, 8);
      // senderId must be stable for the same noise key
      expect(id.senderId, isNotEmpty);
    });

    test('senderId is reproducible from the noise public key bytes', () async {
      final id = await MeshIdentity.generate();
      final id2 = await MeshIdentity.generate();
      // two fresh identities differ
      expect(id.senderId, isNot(id2.senderId));
      // derive again from the SAME noise pubkey -> same senderId
      final rederived = await MeshIdentity.deriveSenderId(id.noisePublicKey);
      expect(rederived, id.senderId);
    });

    test('signs a packet and the signature round-trips verification', () async {
      final id = await MeshIdentity.generate();
      final packet = BitchatPacket(
        type: MessageType.message.value,
        senderId: id.senderId,
        timestamp: 1700000000000,
        payload: Uint8List.fromList('hello mesh'.codeUnits),
        ttl: 5,
      );
      final signed = await id.signPacket(packet);
      expect(signed.signature, isNotNull);
      expect(signed.signature!.length, 64);
      final ok = await MeshIdentity.verifyPacket(signed, id.signingPublicKey);
      expect(ok, isTrue);
    });

    test('verification FAILS if the signature is from a different key', () async {
      final a = await MeshIdentity.generate();
      final b = await MeshIdentity.generate();
      final packet = BitchatPacket(
        type: MessageType.message.value,
        senderId: a.senderId,
        timestamp: 1,
        payload: Uint8List.fromList([1, 2, 3]),
        ttl: 5,
      );
      final signedByA = await a.signPacket(packet);
      final ok = await MeshIdentity.verifyPacket(signedByA, b.signingPublicKey);
      expect(ok, isFalse);
    });

    test('verification survives TTL decrement (relay-safe)', () async {
      // Native forces ttl=0 in the signed bytes, so a relay dropping ttl
      // from 5 -> 4 must NOT invalidate the signature.
      final id = await MeshIdentity.generate();
      final packet = BitchatPacket(
        type: MessageType.message.value,
        senderId: id.senderId,
        timestamp: 42,
        payload: Uint8List.fromList('relay me'.codeUnits),
        ttl: 5,
      );
      final signed = await id.signPacket(packet);
      // simulate a relay decrementing ttl before forwarding
      final relayed = BitchatPacket(
        version: signed.version,
        type: signed.type,
        senderId: signed.senderId,
        recipientId: signed.recipientId,
        timestamp: signed.timestamp,
        payload: signed.payload,
        signature: signed.signature,
        ttl: 4, // decremented
        route: signed.route,
        isRsr: signed.isRsr,
      );
      final ok = await MeshIdentity.verifyPacket(relayed, id.signingPublicKey);
      expect(ok, isTrue);
    });

    test('verification FAILS on payload tamper', () async {
      final id = await MeshIdentity.generate();
      final packet = BitchatPacket(
        type: MessageType.message.value,
        senderId: id.senderId,
        timestamp: 7,
        payload: Uint8List.fromList('original'.codeUnits),
        ttl: 3,
      );
      final signed = await id.signPacket(packet);
      final tampered = BitchatPacket(
        version: signed.version,
        type: signed.type,
        senderId: signed.senderId,
        recipientId: signed.recipientId,
        timestamp: signed.timestamp,
        payload: Uint8List.fromList('tampered'.codeUnits),
        signature: signed.signature,
        ttl: signed.ttl,
        route: signed.route,
        isRsr: signed.isRsr,
      );
      final ok = await MeshIdentity.verifyPacket(tampered, id.signingPublicKey);
      expect(ok, isFalse);
    });
  });
}
