import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resq/core/bitchat/bitchat_packet.dart';
import 'package:resq/core/bitchat/compression_util.dart';
import 'package:resq/core/bitchat/constants.dart';
import 'package:resq/core/bitchat/message_padding.dart';
import 'package:resq/core/bitchat/message_type.dart';

/// Builder for 8-byte sender IDs (the wire form), mirroring how native builds
/// senderID from raw 8 bytes rather than a hex string.
Uint8List id8(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('MessageType', () {
    test('maps known values and rejects unknown', () {
      expect(MessageType.announce.value, 0x01);
      expect(MessageType.fragment.value, 0x20);
      expect(MessageType.fromValue(0x01), MessageType.announce);
      expect(MessageType.fromValue(0x20), MessageType.fragment);
      expect(MessageType.fromValue(0x99), isNull);
    });
  });

  group('MessagePadding', () {
    test('pads to exact target with PKCS#7 byte = N', () {
      final data = Uint8List.fromList(utf8.encode('hello'));
      // need 3 bytes to reach 8
      final padded = MessagePadding.pad(data, 8);
      expect(padded.length, 8);
      expect(padded.sublist(5), [3, 3, 3]);
    });

    test('unpad reverses pad and validates', () {
      final data = Uint8List.fromList(utf8.encode('hello'));
      final padded = MessagePadding.pad(data, 8);
      final unpadded = MessagePadding.unpad(padded);
      expect(unpadded, data);
    });

    test('unpad is forgiving on invalid padding (returns data unchanged)', () {
      final bad = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      // last byte 8 but not all trailing bytes are 8 -> invalid
      expect(MessagePadding.unpad(bad), bad);
    });

    test('optimalBlockSize picks smallest bucket + overhead', () {
      // 20 bytes + 16 overhead = 36 -> fits 256
      expect(MessagePadding.optimalBlockSize(20), 256);
      // huge payload -> not padded
      expect(MessagePadding.optimalBlockSize(5000), 5000);
    });

    test('matches native block sizes for sample payloads', () {
      for (final s in [
        'Short',
        'a' * 300,
        'b' * 1200,
        'c' * 2700,
      ]) {
        final p = BitchatPacket(
          type: MessageType.message.value,
          senderId: id8([1, 2, 3, 4, 5, 6, 7, 8]),
          timestamp: 1700000000000,
          payload: Uint8List.fromList(utf8.encode(s)),
          ttl: 3,
        );
        final enc = BinaryProtocol.encode(p, padding: true);
        if (enc.length <= 2048) {
          expect(BitchatConstants.paddingBlockSizes.contains(enc.length), isTrue,
              reason: 'encoded size ${enc.length} not a standard block');
        } else {
          expect(enc.length, greaterThan(2048));
        }
      }
    });
  });

  group('CompressionUtil', () {
    test('compresses repetitive payload, skips small', () {
      final small = Uint8List.fromList(utf8.encode('tiny'));
      expect(CompressionUtil.shouldCompress(small), isFalse);
      final big = Uint8List.fromList(utf8.encode('compress-me' * 150));
      final compressed = CompressionUtil.compress(big);
      expect(compressed, isNotNull);
      final back = CompressionUtil.decompress(compressed!, big.length);
      expect(back, big);
    });

    test('decompress rejects size mismatch', () {
      final big = Uint8List.fromList(utf8.encode('compress-me' * 150));
      final compressed = CompressionUtil.compress(big)!;
      // wrong expected size -> null
      expect(CompressionUtil.decompress(compressed, big.length + 1), isNull);
    });

    test('decompress rejects garbage', () {
      expect(CompressionUtil.decompress(Uint8List.fromList([0, 1, 2, 3]), 100),
          isNull);
    });
  });

  group('BinaryProtocol v1', () {
    test('round-trips a basic packet (padded)', () {
      final p = BitchatPacket(
        type: MessageType.message.value,
        senderId: id8([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22]),
        timestamp: 1720000000000,
        payload: Uint8List.fromList(utf8.encode('test payload')),
        ttl: 3,
      );
      final enc = BinaryProtocol.encode(p, padding: true);
      final dec = BinaryProtocol.decode(enc);
      expect(dec, isNotNull);
      expect(dec!.type, p.type);
      expect(dec.ttl, p.ttl);
      expect(dec.timestamp, p.timestamp);
      expect(dec.payload, p.payload);
      // senderId is 8 raw bytes, trailing zeros trimmed on compare
      expect(dec.senderId.sublist(0, 8), p.senderId);
    });

    test('round-trips recipient + signature', () {
      final sig = Uint8List(64);
      for (var i = 0; i < 64; i++) {
        sig[i] = i;
      }
      final p = BitchatPacket(
        type: MessageType.announce.value,
        senderId: id8([1, 1, 1, 1, 1, 1, 1, 1]),
        recipientId: id8([2, 2, 2, 2, 2, 2, 2, 2]),
        timestamp: 1730000000000,
        payload: Uint8List.fromList(utf8.encode('directed')),
        signature: sig,
        ttl: 5,
      );
      final enc = BinaryProtocol.encode(p, padding: true);
      final dec = BinaryProtocol.decode(enc)!;
      expect(dec.recipientId, isNotNull);
      expect(dec.recipientId!.sublist(0, 8), id8([2, 2, 2, 2, 2, 2, 2, 2]));
      expect(dec.signature, sig);
    });

    test('header layout matches native v1 (14-byte header, BE fields)', () {
      final p = BitchatPacket(
        type: 0x02,
        senderId: id8([9, 9, 9, 9, 9, 9, 9, 9]),
        timestamp: 0x0001020304050607,
        payload: Uint8List.fromList([0xDE, 0xAD]),
        ttl: 7,
      );
      final raw = BinaryProtocol.encode(p, padding: false);
      // version(1) type(1) ttl(1) ts(8) flags(1) len(2) sender(8)
      expect(raw[0], 1); // version
      expect(raw[1], 0x02); // type
      expect(raw[2], 7); // ttl
      expect(raw[3], 0x00);
      expect(raw[4], 0x01);
      expect(raw[5], 0x02);
      expect(raw[6], 0x03);
      expect(raw[7], 0x04);
      expect(raw[8], 0x05);
      expect(raw[9], 0x06);
      expect(raw[10], 0x07); // timestamp big-endian
      expect(raw[11], 0x00); // flags (no recipient/sig)
      // payload length = 2, big-endian at [12..13]
      expect(raw[12], 0x00);
      expect(raw[13], 0x02);
      // sender id starts at offset 14
      expect(raw.sublist(14, 22), id8([9, 9, 9, 9, 9, 9, 9, 9]));
      // payload after sender
      expect(raw.sublist(22), [0xDE, 0xAD]);
    });

    test('decode tolerates PKCS#7 padding (forgiving)', () {
      final p = BitchatPacket(
        type: MessageType.message.value,
        senderId: id8([3, 3, 3, 3, 3, 3, 3, 3]),
        timestamp: 1,
        payload: Uint8List.fromList(utf8.encode('abc')),
        ttl: 2,
      );
      final raw = BinaryProtocol.encode(p, padding: false);
      final padded = MessagePadding.pad(raw, 256);
      final dec = BinaryProtocol.decode(padded);
      expect(dec, isNotNull);
      expect(dec!.payload, p.payload);
    });

    test('compression flag round-trips on decode (repeats >100 bytes)', () {
      final payload = Uint8List.fromList(utf8.encode('compress-me' * 150));
      final p = BitchatPacket(
        type: MessageType.message.value,
        senderId: id8([4, 4, 4, 4, 4, 4, 4, 4]),
        timestamp: 1,
        payload: payload,
        ttl: 2,
      );
      final enc = BinaryProtocol.encode(p, padding: false);
      // compressed payload is smaller than 150*11 bytes
      expect(enc.length, lessThan(payload.length + 14 + 8));
      final dec = BinaryProtocol.decode(enc)!;
      expect(dec.payload, payload);
    });

    test('toBinaryDataForSigning excludes signature, forces ttl=0, isRSR=false', () {
      final sig = Uint8List(64);
      final p = BitchatPacket(
        type: MessageType.message.value,
        senderId: id8([5, 5, 5, 5, 5, 5, 5, 5]),
        timestamp: 12345,
        payload: Uint8List.fromList(utf8.encode('sign me')),
        signature: sig,
        ttl: 9,
        isRsr: true,
      );
      final sb = p.toBinaryDataForSigning();
      // version..flags at [0..11]; flags at [11] must NOT have sig bit (0x02)
      // and ttl at [2] must be 0
      expect(sb[2], 0); // ttl forced to 0
      expect(sb[11] & BitchatConstants.flagHasSignature, 0);
      expect(sb[11] & BitchatConstants.flagIsRsr, 0);
      // signing bytes must not contain the 64-byte signature tail
      expect(sb.length, lessThan(64 + 30));
    });
  });
}
