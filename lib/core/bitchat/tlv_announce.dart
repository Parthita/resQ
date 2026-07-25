import 'dart:typed_data';

/// TLV (type-length-value) builder/parser for BitChat announce packets.
///
/// Port of AnnouncementPacket encode/decode. Field types (AnnouncementPacket.TLVType):
///   0x01 nickname (utf8 string)
///   0x02 noiseStaticPublicKey (32 bytes)  -> peers derive your senderId from this
///   0x03 signingPublicKey (32 bytes)      -> peers verify your packet signatures with this
///   0x04 directNeighbors (array of peerID strings)
///   0x05 capabilities (bitfield)
///   0x06 bridgeGeohash (string)
///
/// The interop-critical pair is 0x02 + 0x03: without publishing your signing
/// public key (0x03), native peers have nothing to verify your signatures
/// against and WILL reject your packets.
class TlvAnnounce {
  TlvAnnounce({
    required this.nickname,
    required this.noisePublicKey,
    required this.signingPublicKey,
    this.capabilities = 0,
    this.neighbors = const [],
  });

  final String nickname;
  final Uint8List noisePublicKey; // 32 bytes
  final Uint8List signingPublicKey; // 32 bytes
  final int capabilities;
  final List<String> neighbors;

  static const int typeNickname = 0x01;
  static const int typeNoiseKey = 0x02;
  static const int typeSignKey = 0x03;
  static const int typeNeighbors = 0x04;
  static const int typeCapabilities = 0x05;

  static const int noiseKeyLength = 32;
  static const int signKeyLength = 32;

  Uint8List encode() {
    final out = BytesBuilder();
    _put(out, typeNickname, Uint8List.fromList(nickname.codeUnits));
    _put(out, typeNoiseKey, noisePublicKey);
    _put(out, typeSignKey, signingPublicKey);
    if (neighbors.isNotEmpty) {
      final nb = BytesBuilder();
      for (final n in neighbors) {
        final b = Uint8List.fromList(n.codeUnits);
        nb.addByte(b.length);
        nb.add(b);
      }
      _put(out, typeNeighbors, nb.toBytes());
    }
    _put(out, typeCapabilities, Uint8List.fromList([capabilities]));
    return out.toBytes();
  }

  static TlvAnnounce decode(Uint8List data) {
    final fields = <int, Uint8List>{};
    var offset = 0;
    while (offset + 2 <= data.length) {
      final t = data[offset++];
      final len = data[offset++];
      if (offset + len > data.length) break;
      fields[t] = Uint8List.sublistView(data, offset, offset + len);
      offset += len;
    }
    final nickname = String.fromCharCodes(fields[typeNickname] ?? Uint8List(0));
    final noiseKey = fields[typeNoiseKey] ?? Uint8List(0);
    final signKey = fields[typeSignKey] ?? Uint8List(0);
    final caps = fields[typeCapabilities];
    final capabilities = caps != null && caps.isNotEmpty ? caps[0] : 0;
    return TlvAnnounce(
      nickname: nickname,
      noisePublicKey: noiseKey,
      signingPublicKey: signKey,
      capabilities: capabilities,
    );
  }

  static void _put(BytesBuilder out, int type, Uint8List value) {
    out.addByte(type);
    out.addByte(value.length);
    out.add(value);
  }
}
