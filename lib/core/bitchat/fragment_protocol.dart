import 'dart:math';
import 'dart:typed_data';

import 'bitchat_packet.dart';
import 'constants.dart';
import 'message_type.dart';

/// Splits a fully-encoded packet into BLE-friendly fragment packets.
///
/// Port of BLEOutboundFragmentPlanner.makeFragmentPacket (Swift):
///   fragment payload = fragmentID(8) + index(2 BE) + total(2 BE)
///                      + originalType(1) + chunkData
///
/// We chunk at [BitchatConstants.fragmentChunkSize] (469) REGARDLESS of the
/// negotiated BLE MTU. Reassembly happens at the fragment layer, not the raw
/// BLE frame layer, so MTU is irrelevant to fragmentation.
class Fragmenter {
  Fragmenter({this.chunkSize = BitchatConstants.fragmentChunkSize});

  final int chunkSize;

  /// Split an already-encoded packet (raw wire bytes) into fragment packets.
  ///
  /// Each fragment packet's [senderId] is copied from the original so the
  /// receiver can key reassembly on (senderId, fragmentId). Fragments carry
  /// NO signature (native does the same) — the reassembled original is what
  /// gets verified.
  List<BitchatPacket> fragment(
    Uint8List encodedPacket,
    Uint8List senderId, {
    Uint8List? fragmentId,
    int ttl = 1,
  }) {
    final fid = fragmentId ?? _randomFragmentId();
    if (fid.length != BitchatConstants.fragmentIdLength) {
      throw ArgumentError('fragmentId must be 8 bytes');
    }
    if (encodedPacket.isEmpty) return [];

    // Original packet type lives at byte[1] of the encoded wire format.
    final originalType = encodedPacket.length > 1 ? encodedPacket[1] : 0;

    final total = (encodedPacket.length / chunkSize).ceil();
    if (total < 1) {
      // single fragment still emitted as index 0/total 1
      return [_makeFragment(fid, 0, 1, originalType, encodedPacket, senderId, ttl)];
    }

    final out = <BitchatPacket>[];
    for (var index = 0; index < total; index++) {
      final start = index * chunkSize;
      final end = min(start + chunkSize, encodedPacket.length);
      final chunk = encodedPacket.sublist(start, end);
      out.add(_makeFragment(fid, index, total,
          originalType, chunk, senderId, ttl));
    }
    return out;
  }

  BitchatPacket _makeFragment(
    Uint8List fid,
    int index,
    int total,
    int originalType,
    Uint8List chunk,
    Uint8List senderId,
    int ttl,
  ) {
    final payload = BytesBuilder();
    payload.add(fid); // 8 bytes
    // index (2 bytes, big-endian)
    payload.addByte((index >> 8) & 0xFF);
    payload.addByte(index & 0xFF);
    // total (2 bytes, big-endian)
    payload.addByte((total >> 8) & 0xFF);
    payload.addByte(total & 0xFF);
    // original type (1 byte)
    payload.addByte(originalType);
    payload.add(chunk);

    return BitchatPacket(
      type: MessageType.fragment.value,
      senderId: senderId,
      timestamp: 0,
      payload: payload.toBytes(),
      ttl: ttl,
    );
  }

  static Uint8List _randomFragmentId() {
    final rnd = Random.secure();
    final fid = Uint8List(BitchatConstants.fragmentIdLength);
    for (var i = 0; i < fid.length; i++) {
      fid[i] = rnd.nextInt(256);
    }
    return fid;
  }
}

/// Reassembles fragment packets into the original encoded packet.
///
/// Keyed by (senderId, fragmentId). Enforces the native limits:
///   - 30s assembly timeout (evict stale assemblies)
///   - 128 concurrent assemblies
///   - 1 MiB max reconstructed size
///
/// Once all fragments arrive, [onReassembled] is called with the full encoded
/// packet bytes. Callers then decode + verify that reassembled packet.
class FragmentAssembler {
  FragmentAssembler({this.onReassembled});

  final void Function(Uint8List senderId, Uint8List fullPacket)? onReassembled;

  final Map<String, _Assembly> _assemblies = {};

  /// Feed one received fragment packet. Returns true if it completed an
  /// assembly (and fired [onReassembled]).
  bool add(BitchatPacket fragment) {
    _evictStale();
    if (fragment.type != MessageType.fragment.value) return false;
    if (fragment.payload.length < 13) return false; // 8+2+2+1 minimum

    final p = fragment.payload;
    final fid = Uint8List.sublistView(p, 0, 8);
    final index = (p[8] << 8) | p[9];
    final total = (p[10] << 8) | p[11];
    final originalType = p[12];
    final chunk = Uint8List.sublistView(p, 13);

    if (total <= 0 || index >= total) return false;
    if (_assemblies.length >= BitchatConstants.fragmentMaxConcurrentAssemblies) {
      _evictStale(); // best-effort; could still be at cap
    }

    final key = _key(fragment.senderId, fid);
    final assembly = _assemblies.putIfAbsent(
      key,
      () => _Assembly(senderId: fragment.senderId, fragmentId: fid, total: total),
    );
    // total may differ if first fragment had a different total; trust the
    // highest seen total to be safe.
    assembly.total = total > assembly.total ? total : assembly.total;
    assembly.originalType = originalType;
    assembly.chunks[index] = chunk;
    assembly.touch();

    if (assembly.isComplete) {
      final full = assembly.reconstruct();
      _assemblies.remove(key);
      if (full != null) {
        onReassembled?.call(fragment.senderId, full);
        return true;
      }
    }
    return false;
  }

  void _evictStale() {
    final now = DateTime.now();
    _assemblies.removeWhere(
      (_, a) =>
          now.difference(a.lastUpdate) >
          BitchatConstants.fragmentAssemblyTimeout,
    );
  }

  static String _key(Uint8List senderId, Uint8List fragmentId) {
    return '${String.fromCharCodes(senderId)}|${String.fromCharCodes(fragmentId)}';
  }

  void clear() => _assemblies.clear();
}

class _Assembly {
  _Assembly({
    required this.senderId,
    required this.fragmentId,
    required this.total,
  });

  final Uint8List senderId;
  final Uint8List fragmentId;
  int total;
  int originalType = 0;
  final Map<int, Uint8List> chunks = {};
  DateTime lastUpdate = DateTime.now();

  bool get isComplete {
    if (chunks.length < total) return false;
    for (var i = 0; i < total; i++) {
      if (!chunks.containsKey(i)) return false;
    }
    return true;
  }

  Uint8List? reconstruct() {
    if (!isComplete) return null;
    final out = BytesBuilder();
    var projected = 0;
    for (var i = 0; i < total; i++) {
      final c = chunks[i]!;
      projected += c.length;
      if (projected > BitchatConstants.fragmentMaxSizeBytes) return null;
      out.add(c);
    }
    return out.toBytes();
  }

  void touch() => lastUpdate = DateTime.now();
}

/// Convenience: strip the fragment inner header from a chunk (used by tests).
Uint8List fragmentChunkData(Uint8List fragmentPayload) {
  if (fragmentPayload.length < 13) return Uint8List(0);
  return Uint8List.sublistView(fragmentPayload, 13);
}
