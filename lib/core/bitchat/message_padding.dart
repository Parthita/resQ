import 'dart:typed_data';

import 'constants.dart';

/// PKCS#7-style padding for privacy-preserving message sizes.
///
/// Port of MessagePadding.swift. The goal is to pad packets toward uniform
/// block sizes so an eavesdropper on the BLE link can't use length to guess
/// message type/content.
///
/// Rule (must match native exactly):
///  - pad appends N bytes each equal to N, where N is the number of bytes
///    needed to reach the target size.
///  - N is constrained to 1..255 (a single pad-length byte).
///  - unpad reads the last byte as N, verifies all trailing N bytes equal N,
///    and strips them. If the padding is invalid it returns the data unchanged
///    (native is equally forgiving on decode).
class MessagePadding {
  MessagePadding._();

  /// Smallest block size (plus assumed AEAD overhead) that fits [dataSize].
  static int optimalBlockSize(int dataSize) {
    final total = dataSize + BitchatConstants.paddingOverhead;
    for (final block in BitchatConstants.paddingBlockSizes) {
      if (total <= block) return block;
    }
    // Very large messages are not padded (they get fragmented anyway).
    return dataSize;
  }

  /// Pad [data] up to [targetSize] using PKCS#7. No-op if already >= target.
  static Uint8List pad(Uint8List data, int targetSize) {
    if (data.length >= targetSize) return data;
    final needed = targetSize - data.length;
    if (needed <= 0 || needed > 255) return data; // N must fit one byte
    final out = Uint8List(targetSize);
    out.setAll(0, data);
    out.fillRange(data.length, targetSize, needed);
    return out;
  }

  /// Strip PKCS#7 padding. Returns the data unchanged if padding is invalid.
  static Uint8List unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data.last;
    if (padLen <= 0 || padLen > data.length) return data;
    final start = data.length - padLen;
    for (var i = start; i < data.length; i++) {
      if (data[i] != padLen) return data; // invalid -> leave as-is
    }
    return data.sublist(0, start);
  }
}
