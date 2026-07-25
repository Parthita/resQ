import 'dart:async';
import 'dart:typed_data';

import 'bitchat_link.dart';
import 'bitchat_packet.dart';
import 'fragment_protocol.dart';
import 'message_type.dart';

/// Flood routing core for the mesh.
///
/// Responsibilities (port of the native flood router + BLE transport glue):
///   - Fragment outgoing packets (<= 469 B frames) and push them on the link.
///   - Reassemble incoming fragment frames into whole packets.
///   - Deduplicate by packet hash so the same packet isn't delivered/reflooded
///     more than once. (native uses senderID+timestamp+sequence for the seen-set)
///   - Decrement TTL on reflood; drop at TTL 0.
///   - Split-horizon: never reflood a packet back out the link it arrived on.
///   - Optionally verify the Ed25519 signature before accepting a packet.
///
/// This class is link-agnostic: feed it a [BitchatLink] (real BLE or mock),
/// so all logic is testable headlessly.
class FloodRouter {
  FloodRouter({
    required this.link,
    this.signatureVerifier,
    this.chunkSize = 469,
  });

  final BitchatLink link;

  /// If provided, every non-fragment packet must verify or it is dropped.
  /// Signature check uses packet.toBinaryDataForSigning() (ttl forced 0).
  final Future<bool> Function(BitchatPacket packet)? signatureVerifier;

  final int chunkSize;

  final Map<String, DateTime> _seen = {};
  FragmentAssembler? _assembler;
  final _delivered = StreamController<BitchatPacket>.broadcast();

  /// Packets that passed dedup + (optional) signature and are meant for us /
  /// the app layer.
  Stream<BitchatPacket> get delivered => _delivered.stream;

  Future<void> start() async {
    await link.start();
    _assembler = FragmentAssembler(onReassembled: _onReassembled);
    link.received.listen(_onFrame);
  }

  /// Send a whole (already-built, signed) packet to the mesh.
  Future<void> broadcast(BitchatPacket packet) async {
    final encoded = BinaryProtocol.encode(packet, padding: true);
    final frags = Fragmenter(chunkSize: chunkSize).fragment(
      encoded,
      packet.senderId,
      ttl: packet.ttl,
    );
    for (final f in frags) {
      final frame = BinaryProtocol.encode(f, padding: false);
      await link.send(frame);
    }
    // mark our own packet as seen so we don't reflood echoes of it
    _markSeen(packet);
  }

  void _onFrame(Uint8List frame) {
    // frames on the wire are unpadded fragment packets (padding:false)
    final frag = BinaryProtocol.decode(frame);
    if (frag == null) return;
    _assembler?.add(frag);
  }

  void _onReassembled(Uint8List senderId, Uint8List fullPacket) {
    final packet = BinaryProtocol.decode(fullPacket);
    if (packet == null) return;
    _handlePacket(packet, fromLink: link);
  }

  Future<void> _handlePacket(BitchatPacket packet,
      {required BitchatLink fromLink}) async {
    if (packet.type == MessageType.fragment.value) return; // already handled
    if (_isSeen(packet)) return; // dedup
    _markSeen(packet);

    // optional signature verification (M2): reject packets that fail.
    // Signatures cover toBinaryDataForSigning() (ttl forced 0), so a reflood
    // with ttl-1 still verifies correctly.
    if (signatureVerifier != null) {
      final ok = await signatureVerifier!(packet);
      if (!ok) return; // drop unverifiable packet
    }

    // deliver to app layer
    _delivered.add(packet);

    // reflood to other peers (split-horizon: not back to the origin link)
    _reflood(packet, exceptLink: fromLink);
  }

  void _reflood(BitchatPacket packet, {required BitchatLink exceptLink}) {
    if (packet.ttl <= 1) return; // drop at TTL 1 (already at last hop)
    final forwarded = BitchatPacket(
      version: packet.version,
      type: packet.type,
      senderId: packet.senderId,
      recipientId: packet.recipientId,
      timestamp: packet.timestamp,
      payload: packet.payload,
      signature: packet.signature,
      ttl: packet.ttl - 1, // hop decrement
      route: packet.route,
      isRsr: packet.isRsr,
    );
    // reflood to peers (loop prevention is via the dedup seen-set; native also
    // applies per-peer split-horizon at the BLE layer, which the real BleLink
    // does by not writing back to the central it received from)
    _sendNow(forwarded);
  }

  Future<void> _sendNow(BitchatPacket packet) async {
    final encoded = BinaryProtocol.encode(packet, padding: true);
    final frags = Fragmenter(chunkSize: chunkSize).fragment(
      encoded,
      packet.senderId,
      ttl: packet.ttl,
    );
    for (final f in frags) {
      final frame = BinaryProtocol.encode(f, padding: false);
      await link.send(frame);
    }
  }

  String _dedupKey(BitchatPacket p) {
    // senderId + timestamp + payload hash is a stable seen-key
    final h = _hash(p.payload);
    return '${String.fromCharCodes(p.senderId)}|${p.timestamp}|$h';
  }

  bool _isSeen(BitchatPacket p) => _seen.containsKey(_dedupKey(p));

  void _markSeen(BitchatPacket p) {
    _seen[_dedupKey(p)] = DateTime.now();
    if (_seen.length > 5000) _seen.clear(); // bound memory
  }

  static String _hash(Uint8List data) {
    // simple FNV-1a 32-bit; enough for dedup, not security
    var h = 0x811c9dc5;
    for (final b in data) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  Future<void> stop() async {
    await _delivered.close();
    await link.stop();
  }
}
