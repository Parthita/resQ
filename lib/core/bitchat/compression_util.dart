import 'dart:io';
import 'dart:typed_data';

import 'constants.dart';

/// zlib compression/decompression for packet payloads.
///
/// Port of CompressionUtil.swift. Native uses Apple's COMPRESSION_ZLIB, which
/// is the standard zlib stream format, so Dart's `dart:io` ZLibEncoder /
/// ZLibDecoder (also zlib) are wire-compatible.
///
/// Critical interop rule (do NOT relax): on decode we MUST know the original
/// size ahead of time (native stores it in an inline length prefix) and verify
/// the decompressed output is exactly that length. We also reject absurd
/// compression ratios to avoid zip-bomb-style memory exhaustion. If you skip
/// these checks, you will accept/forward malformed packets.
class CompressionUtil {
  CompressionUtil._();

  /// Whether compressing [data] is worthwhile (mirrors native shouldCompress).
  static bool shouldCompress(Uint8List data) {
    if (data.length < BitchatConstants.compressionThreshold) return false;
    // Quick entropy heuristic: high byte-diversity usually means already
    // compressed. Sample up to 256 bytes.
    final sampleSize = data.length < 256 ? data.length : 256;
    final unique = <int>{};
    for (var i = 0; i < sampleSize; i++) {
      unique.add(data[i]);
    }
    final ratio = unique.length / sampleSize;
    return ratio < 0.9;
  }

  /// Compress with zlib. Returns null if not beneficial or if it doesn't shrink.
  static Uint8List? compress(Uint8List data) {
    if (!shouldCompress(data)) return null;
    final out = ZLibEncoder().convert(data);
    if (out.isEmpty || out.length >= data.length) return null;
    return Uint8List.fromList(out);
  }

  /// Decompress zlib [compressed] expecting exactly [originalSize] bytes.
  /// Returns null if decompression fails OR the size does not match.
  static Uint8List? decompress(Uint8List compressed, int originalSize) {
    if (originalSize <= 0 || originalSize > BitchatConstants.fragmentMaxSizeBytes) {
      return null;
    }
    if (compressed.isEmpty) return null;
    final ratio = originalSize / compressed.length;
    if (ratio > BitchatConstants.maxCompressionRatio) return null;
    try {
      final out = ZLibDecoder().convert(compressed);
      if (out.length != originalSize) return null;
      return Uint8List.fromList(out);
    } on Exception {
      return null;
    }
  }
}
