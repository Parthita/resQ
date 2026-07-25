enum DeliveryState { queued, nearbyDelivered, relayed, expired }

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
