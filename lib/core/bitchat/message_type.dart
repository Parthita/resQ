/// Wire message types for the BitChat protocol (port of MessageType.swift).
///
/// These are the high-level "what is this packet" tags carried in the
/// packet header's `type` byte. We only need a subset for our mesh, but we
/// keep the full enum so we can decode native packets without dropping them.
///
/// Dart note: `enum` with an explicit `UInt8` value is expressed as a class
/// with a static const per type. This keeps the value mapping identical to
/// the Swift source.
class MessageType {
  const MessageType._(this.value);

  final int value;

  // Public / mesh-control
  static const announce = MessageType._(
    0x01,
  ); // "I'm here" + nickname/keys (TLV)
  static const message = MessageType._(0x02); // public chat message
  static const leave = MessageType._(0x03); // "I'm leaving"
  static const courierEnvelope = MessageType._(0x04);
  static const requestSync = MessageType._(0x21);
  static const syncDoc = MessageType._(
    0x30,
  ); // our CRDT sync carrier (project novelty)
  /// resQ's application-level invitation and direct-message envelope.
  static const personal = MessageType._(0x31);

  // Tier-2 reliable resync: chunked state transfer + acknowledgement.
  // The plain syncDoc path sends the whole Yjs doc as ONE packet that the
  // FloodRouter fragments into 469B BLE frames; a single dropped frame over
  // the unreliable `withoutResponse` link silently fails the reassembly and
  // the peers diverge. syncChunk splits the state into small (<=400B) frames
  // so each is a single BLE fragment, and syncAck lets the sender confirm the
  // peer actually received + applied the full state (and retransmit if not).
  static const syncChunk = MessageType._(0x32);
  static const syncAck = MessageType._(0x33);

  // Noise encryption (we skip Noise, but must recognise the types)
  static const noiseHandshake = MessageType._(0x10);
  static const noiseEncrypted = MessageType._(0x11);

  // Fragmentation + binary
  static const fragment = MessageType._(0x20); // large-message chunk
  static const fileTransfer = MessageType._(0x22);
  static const boardPost = MessageType._(0x23);
  static const prekeyBundle = MessageType._(0x24);
  static const groupMessage = MessageType._(0x25);
  static const ping = MessageType._(0x26);
  static const pong = MessageType._(0x27);
  static const nostrCarrier = MessageType._(0x28);
  static const voiceFrame = MessageType._(0x29);

  static MessageType? fromValue(int v) {
    for (final t in _all) {
      if (t.value == v) return t;
    }
    return null;
  }

  static const List<MessageType> _all = [
    announce,
    message,
    leave,
    courierEnvelope,
    requestSync,
    noiseHandshake,
    noiseEncrypted,
    fragment,
    fileTransfer,
    boardPost,
    prekeyBundle,
    groupMessage,
    ping,
    pong,
    nostrCarrier,
    voiceFrame,
    personal,
    syncChunk,
    syncAck,
  ];
}
