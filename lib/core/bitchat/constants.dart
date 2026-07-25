/// Protocol constants ported from the BitChat Swift source.
///
/// These values MUST match the native implementation byte-for-byte or native
/// peers will reject or silently fail to parse our packets.
class BitchatConstants {
  BitchatConstants._();

  // Header sizes (BinaryProtocol.swift).
  static const int v1HeaderSize = 14;
  static const int v2HeaderSize = 16;
  static const int senderIdSize = 8;
  static const int recipientIdSize = 8;
  static const int signatureSize = 64;

  // Flag bits (BinaryProtocol.Flags).
  static const int flagHasRecipient = 0x01;
  static const int flagHasSignature = 0x02;
  static const int flagIsCompressed = 0x04;
  static const int flagHasRoute = 0x08; // v2 only
  static const int flagIsRSR = 0x10;
  static const int flagIsRsr = 0x10; // dart-style alias

  // Padding block sizes (MessagePadding.blockSizes).
  static const List<int> paddingBlockSizes = [256, 512, 1024, 2048];

  // Padding assumes ~16 bytes of AEAD tag overhead when choosing a bucket.
  static const int paddingOverhead = 16;

  // Compression (Constants.compressionThresholdBytes).
  static const int compressionThreshold = 100;

  // Compression safety: reject absurd expansion ratios.
  static const double maxCompressionRatio = 50000.0;

  // BLE service / characteristic UUIDs (BLEService.swift).
  // Use the testnet UUID unless you specifically want mainnet interop.
  static const String serviceUuidTestnet =
      'F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5A';
  static const String serviceUuidMainnet =
      'F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C';
  static const String characteristicUuid =
      'A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D';

  // Fragmentation (TransportConfig.bleDefaultFragmentSize).
  static const int fragmentChunkSize = 469;
  static const int fragmentIdLength = 8;
  static const Duration fragmentAssemblyTimeout = Duration(seconds: 30);
  static const int fragmentMaxConcurrentAssemblies = 128;
  static const int fragmentMaxSizeBytes = 1024 * 1024; // 1 MiB

  // Announce TLV field types (AnnouncementPacket.TLVType).
  static const int tlvNickname = 0x01;
  static const int tlvNoisePublicKey = 0x02;
  static const int tlvSigningPublicKey = 0x03;
  static const int tlvDirectNeighbors = 0x04;
  static const int tlvCapabilities = 0x05;
  static const int tlvBridgeGeohash = 0x06;
}
