// Platform and model integrations are deliberately behind these contracts.
// The Flutter UI can remain fully local-first while Android implementations
// handle BLE, Wi-Fi Direct, OCR, and the on-device model runtime.

enum DeliveryState { queued, nearbyDelivered, relayed, expired }

class LocalDocument {
  const LocalDocument({
    required this.id,
    required this.name,
    required this.filePath,
    required this.byteCount,
    required this.pageCount,
    required this.addedAt,
  });

  final String id;
  final String name;
  final String filePath;
  final int byteCount;
  final int pageCount;
  final DateTime addedAt;
}

class GroundedAnswer {
  const GroundedAnswer({
    required this.text,
    required this.documentId,
    required this.pageNumbers,
    required this.isSafetySensitive,
  });

  final String text;
  final String? documentId;
  final List<int> pageNumbers;
  final bool isSafetySensitive;
}

class NearbyPeer {
  const NearbyPeer({
    required this.ephemeralId,
    required this.lastSeen,
    required this.transport,
  });

  final String ephemeralId;
  final DateTime lastSeen;
  final String transport;
}

class OutboundMessage {
  const OutboundMessage({
    required this.id,
    required this.groupId,
    required this.ciphertext,
    required this.expiresAt,
    required this.maxHops,
  });

  final String id;
  final String? groupId;
  final List<int> ciphertext;
  final DateTime expiresAt;
  final int maxHops;
}

abstract class DocumentIntelligenceService {
  Future<LocalDocument> importPdf(String path);

  Future<String> summarize(LocalDocument document);

  Future<GroundedAnswer> answer({
    required String prompt,
    required List<LocalDocument> context,
  });
}

abstract class NearbyTransport {
  Stream<List<NearbyPeer>> discover();

  Future<bool> verifyPeer({
    required NearbyPeer peer,
    required String verificationCode,
  });

  Future<DeliveryState> send(OutboundMessage message);
}

abstract class SecureStore {
  Future<void> write(String key, List<int> plaintext);

  Future<List<int>?> read(String key);

  Future<void> delete(String key);
}
