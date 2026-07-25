import 'dart:typed_data';

import 'compression_util.dart';
import 'constants.dart';
import 'message_padding.dart';

/// Port of BitchatPacket.swift. The in-memory packet model.
///
/// Field meanings mirror the Swift struct:
///  - version: 1 (v2 adds 4-byte length + source routing; we stay on v1).
///  - type: MessageType value.
///  - senderId: 8 raw bytes (NOT a string). Derived from the Noise static key.
///  - recipientId: 8 raw bytes, or null for a broadcast.
///  - timestamp: milliseconds since epoch (8 bytes, big-endian).
///  - payload: the message body (already in its inner format, e.g. TLV).
///  - signature: 64 raw bytes, or null.
///  - ttl: hop limit (1 byte).
///  - route: v2-only; unused on v1 (kept for completeness, never encoded).
class BitchatPacket {
  const BitchatPacket({
    this.version = 1,
    required this.type,
    required this.senderId,
    this.recipientId,
    required this.timestamp,
    required this.payload,
    this.signature,
    required this.ttl,
    this.route,
    this.isRsr = false,
  });

  final int version;
  final int type;
  final Uint8List senderId;
  final Uint8List? recipientId;
  final int timestamp;
  final Uint8List payload;
  final Uint8List? signature;
  final int ttl;
  final List<Uint8List>? route;
  final bool isRsr;

  /// Canonical bytes used for signing (port of toBinaryDataForSigning).
  ///
  /// The signature covers everything EXCEPT: the signature field itself, the
  /// TTL byte (forced to 0 so relays decrementing TTL don't invalidate it),
  /// and the RSR flag (mutable, excluded). This is the single most important
  /// interop rule: if you sign any other byte set, native peers reject you.
  Uint8List toBinaryDataForSigning() {
    final unsigned = BitchatPacket(
      version: version,
      type: type,
      senderId: senderId,
      recipientId: recipientId,
      timestamp: timestamp,
      payload: payload,
      signature: null,
      ttl: 0,
      route: route,
      isRsr: false,
    );
    return BinaryProtocol.encode(unsigned, padding: false);
  }
}

/// Low-level binary encode/decode. Kept in the same file to avoid a circular
/// import at the top level; see [BinaryProtocol] below.
class BinaryProtocol {
  BinaryProtocol._();

  /// Encode a packet to its wire bytes.
  ///
  /// [padding] adds PKCS#7 padding to a standard block size (native default).
  /// Pass false when producing the canonical signing bytes.
  static Uint8List encode(BitchatPacket p, {bool padding = true}) {
    if (p.version != 1 && p.version != 2) {
      throw ArgumentError('unsupported version ${p.version}');
    }

    // --- optional compression of payload ---
    var payload = p.payload;
    var isCompressed = false;
    var originalSize = 0;
    if (CompressionUtil.shouldCompress(payload)) {
      final compressed = CompressionUtil.compress(payload);
      if (compressed != null) {
        originalSize = payload.length;
        payload = compressed;
        isCompressed = true;
      }
    }

    final lengthFieldSize = p.version == 2 ? 4 : 2;
    final hasRoute = p.version >= 2 && p.route != null && p.route!.isNotEmpty;
    final originalSizeFieldBytes = isCompressed ? lengthFieldSize : 0;

    // payloadLength in the header is payload-only (excludes inline originalSize).
    final payloadDataSize = payload.length + originalSizeFieldBytes;
    if (p.version == 1 && payloadDataSize > 0xFFFF) {
      throw ArgumentError('payload too large for v1');
    }

    final out = BytesBuilder()..addByte(p.version);
    out.addByte(p.type);
    out.addByte(p.ttl);

    // timestamp (8 bytes, big-endian)
    for (var shift = 56; shift >= 0; shift -= 8) {
      out.addByte((p.timestamp >> shift) & 0xFF);
    }

    // flags
    var flags = 0;
    if (p.recipientId != null) flags |= BitchatConstants.flagHasRecipient;
    if (p.signature != null) flags |= BitchatConstants.flagHasSignature;
    if (isCompressed) flags |= BitchatConstants.flagIsCompressed;
    if (hasRoute) flags |= BitchatConstants.flagHasRoute;
    if (p.isRsr) flags |= BitchatConstants.flagIsRsr;
    out.addByte(flags);

    // payload length (2 or 4 bytes, big-endian)
    if (p.version == 2) {
      final len = payloadDataSize;
      for (var shift = 24; shift >= 0; shift -= 8) {
        out.addByte((len >> shift) & 0xFF);
      }
    } else {
      out.addByte((payloadDataSize >> 8) & 0xFF);
      out.addByte(payloadDataSize & 0xFF);
    }

    // senderId (exactly 8 bytes, zero-padded/truncated)
    out.add(_truncate(p.senderId, BitchatConstants.senderIdSize));

    if (p.recipientId != null) {
      out.add(_truncate(p.recipientId!, BitchatConstants.recipientIdSize));
    }

    if (hasRoute) {
      out.addByte(p.route!.length);
      for (final hop in p.route!) {
        out.add(_truncate(hop, BitchatConstants.senderIdSize));
      }
    }

    if (isCompressed) {
      if (p.version == 2) {
        final v = originalSize;
        for (var shift = 24; shift >= 0; shift -= 8) {
          out.addByte((v >> shift) & 0xFF);
        }
      } else {
        out.addByte((originalSize >> 8) & 0xFF);
        out.addByte(originalSize & 0xFF);
      }
    }

    out.add(payload);

    if (p.signature != null) {
      out.add(_truncate(p.signature!, BitchatConstants.signatureSize));
    }

    final bytes = out.toBytes();
    if (!padding) return bytes;
    final target = MessagePadding.optimalBlockSize(bytes.length);
    return MessagePadding.pad(bytes, target);
  }

  /// Decode wire bytes to a packet.
  ///
  /// Matches native: try decode-as-is first, then fall back to stripping
  /// PKCS#7 padding. Returns null on hard failure.
  static BitchatPacket? decode(Uint8List data) {
    final direct = _decodeCore(data);
    if (direct != null) return direct;
    final unpadded = MessagePadding.unpad(data);
    if (identical(unpadded, data)) return null;
    return _decodeCore(unpadded);
  }

  static BitchatPacket? _decodeCore(Uint8List data) {
    var offset = 0;
    int read16() {
      final v = (data[offset] << 8) | data[offset + 1];
      offset += 2;
      return v;
    }

    // Manual readers that return Uint8List.
    Uint8List readN(int n) {
      final v = Uint8List.sublistView(data, offset, offset + n);
      offset += n;
      return v;
    }

    if (data.length < BitchatConstants.v1HeaderSize + BitchatConstants.senderIdSize) {
      return null;
    }
    final version = data[offset++];
    if (version != 1 && version != 2) return null;
    final type = data[offset++];
    final ttl = data[offset++];

    int timestamp = 0;
    for (var i = 0; i < 8; i++) {
      timestamp = (timestamp << 8) | data[offset++];
    }

    final flags = data[offset++];
    final hasRecipient = (flags & BitchatConstants.flagHasRecipient) != 0;
    final hasSignature = (flags & BitchatConstants.flagHasSignature) != 0;
    final isCompressed = (flags & BitchatConstants.flagIsCompressed) != 0;
    final hasRoute = (version >= 2) && (flags & BitchatConstants.flagHasRoute) != 0;
    final isRsr = (flags & BitchatConstants.flagIsRsr) != 0;

    int payloadLength;
    if (version == 2) {
      payloadLength = 0;
      for (var i = 0; i < 4; i++) {
        payloadLength = (payloadLength << 8) | data[offset++];
      }
    } else {
      payloadLength = read16();
    }

    final senderId = readN(BitchatConstants.senderIdSize);
    Uint8List? recipientId;
    if (hasRecipient) recipientId = readN(BitchatConstants.recipientIdSize);

    List<Uint8List>? route;
    if (hasRoute) {
      final count = data[offset++];
      final hops = <Uint8List>[];
      for (var i = 0; i < count; i++) {
        hops.add(readN(BitchatConstants.senderIdSize));
      }
      route = hops;
    }

    Uint8List payload;
    if (isCompressed) {
      int originalSize;
      if (version == 2) {
        originalSize = 0;
        for (var i = 0; i < 4; i++) {
          originalSize = (originalSize << 8) | data[offset++];
        }
      } else {
        originalSize = read16();
      }
      final compressedSize = payloadLength - (version == 2 ? 4 : 2);
      if (compressedSize <= 0) return null;
      final compressed = readN(compressedSize);
      final decompressed = CompressionUtil.decompress(compressed, originalSize);
      if (decompressed == null) return null;
      payload = decompressed;
    } else {
      if (offset + payloadLength > data.length) return null;
      payload = readN(payloadLength);
    }

    Uint8List? signature;
    if (hasSignature) signature = readN(BitchatConstants.signatureSize);

    return BitchatPacket(
      version: version,
      type: type,
      senderId: senderId,
      recipientId: recipientId,
      timestamp: timestamp,
      payload: payload,
      signature: signature,
      ttl: ttl,
      route: route,
      isRsr: isRsr,
    );
  }

  /// Truncate or zero-pad [data] to exactly [n] bytes (matches native prefix).
  static Uint8List _truncate(Uint8List data, int n) {
    if (data.length == n) return Uint8List.fromList(data);
    final out = Uint8List(n);
    final copy = data.length < n ? data.length : n;
    out.setAll(0, data.sublist(0, copy));
    return out;
  }
}
