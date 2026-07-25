import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bitchat_packet.dart';

/// Local mesh identity for the BitChat protocol.
///
/// This is the single most important interop piece. Native BitChat derives its
/// peer/sender ID from the NOISE static key, not from the Ed25519 signing key
/// and not from a random value. Port of:
///   - PeerID(publicKey:) -> sha256(noiseStaticPubKey).hex.prefix(16) (8 bytes)
///   - NoiseEncryptionService: separate X25519 static key + Ed25519 signing key
///
/// Rule you MUST respect:
///   * senderId is derived from the Noise static PUBLIC key's SHA-256.
///   * The same Noise static key's public bytes are published in the announce
///     TLV 0x02 so peers can derive your senderId and match it to packets.
///   * The Ed25519 public key is published in announce TLV 0x03 so peers can
///     verify your signatures. If you omit TLV 0x03, native peers reject you.
///   * Signatures cover packet.toBinaryDataForSigning() (ttl forced to 0,
///     signature omitted, isRSR omitted).
class MeshIdentity {
  static const _noisePrivateKey = 'resq.mesh.identity.noise.private.v1';
  static const _noisePublicKey = 'resq.mesh.identity.noise.public.v1';
  static const _signingPrivateKey = 'resq.mesh.identity.signing.private.v1';
  static const _signingPublicKey = 'resq.mesh.identity.signing.public.v1';
  static const _storage = FlutterSecureStorage();

  MeshIdentity._({
    required this.noisePrivateKey,
    required this.noisePublicKey,
    required this.signingPrivateKey,
    required this.signingPublicKey,
    required this.senderId,
  });

  /// X25519 key used as the Noise static identity. Its public key drives the
  /// peer/sender ID derivation.
  final SimpleKeyPairData noisePrivateKey;
  final Uint8List noisePublicKey;

  /// Ed25519 key used to sign/verify packets.
  final SimpleKeyPairData signingPrivateKey;
  final Uint8List signingPublicKey;

  /// 8 raw bytes. This is what goes in BitchatPacket.senderId.
  final Uint8List senderId;

  /// Generate a fresh identity.
  static Future<MeshIdentity> generate() async {
    final noise = await X25519().newKeyPair();
    final noisePub = await noise.extractPublicKey();
    final signing = await Ed25519().newKeyPair();
    final signingPub = await signing.extractPublicKey();

    final noisePubBytes = Uint8List.fromList(noisePub.bytes);
    final senderId = await deriveSenderId(noisePubBytes);

    return MeshIdentity._(
      noisePrivateKey: noise as SimpleKeyPairData,
      noisePublicKey: noisePubBytes,
      signingPrivateKey: signing as SimpleKeyPairData,
      signingPublicKey: Uint8List.fromList(signingPub.bytes),
      senderId: senderId,
    );
  }

  /// Load the device's long-lived BitChat identity, creating it once on first
  /// use. Private key material is stored through the platform keystore (not
  /// in app files or preferences), so contacts retain the same sender ID
  /// after process restarts and app updates.
  static Future<MeshIdentity> loadOrCreate() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _noisePrivateKey),
        _storage.read(key: _noisePublicKey),
        _storage.read(key: _signingPrivateKey),
        _storage.read(key: _signingPublicKey),
      ]);
      if (values.every((value) => value != null)) {
        final noisePrivate = base64Decode(values[0]!);
        final noisePublic = base64Decode(values[1]!);
        final signingPrivate = base64Decode(values[2]!);
        final signingPublic = base64Decode(values[3]!);
        if (noisePrivate.length == 32 &&
            noisePublic.length == 32 &&
            signingPrivate.length == 32 &&
            signingPublic.length == 32) {
          return MeshIdentity._(
            noisePrivateKey: SimpleKeyPairData(
              noisePrivate,
              publicKey: SimplePublicKey(noisePublic, type: KeyPairType.x25519),
              type: KeyPairType.x25519,
            ),
            noisePublicKey: Uint8List.fromList(noisePublic),
            signingPrivateKey: SimpleKeyPairData(
              signingPrivate,
              publicKey: SimplePublicKey(
                signingPublic,
                type: KeyPairType.ed25519,
              ),
              type: KeyPairType.ed25519,
            ),
            signingPublicKey: Uint8List.fromList(signingPublic),
            senderId: await deriveSenderId(Uint8List.fromList(noisePublic)),
          );
        }
      }

      final identity = await generate();
      await Future.wait([
        _storage.write(
          key: _noisePrivateKey,
          value: base64Encode(identity.noisePrivateKey.bytes),
        ),
        _storage.write(
          key: _noisePublicKey,
          value: base64Encode(identity.noisePublicKey),
        ),
        _storage.write(
          key: _signingPrivateKey,
          value: base64Encode(identity.signingPrivateKey.bytes),
        ),
        _storage.write(
          key: _signingPublicKey,
          value: base64Encode(identity.signingPublicKey),
        ),
      ]);
      return identity;
    } on Object {
      // Headless tests and unsupported platforms can lack a platform keystore.
      // Keep the transport functional there; Android/iOS use secure storage.
      return generate();
    }
  }

  /// Derive the 8-byte sender/peer ID from a Noise static public key.
  ///
  /// Mirrors PeerID(publicKey:) in PeerID.swift:
  ///   sha256(noisePubKey).hexEncodedString().prefix(16) -> 16 hex chars.
  /// 16 hex chars = 8 bytes.
  static Future<Uint8List> deriveSenderId(Uint8List noisePublicKeyBytes) async {
    final hash = await Sha256().hash(noisePublicKeyBytes);
    final hex = _toHex(hash.bytes);
    final prefix = hex.substring(0, 16);
    return _hexToBytes(prefix);
  }

  /// Sign a packet and return a copy carrying the 64-byte Ed25519 signature.
  ///
  /// The signature is computed over packet.toBinaryDataForSigning(), which
  /// excludes the signature field, forces ttl=0, and drops isRSR.
  Future<BitchatPacket> signPacket(BitchatPacket packet) async {
    final signingBytes = packet.toBinaryDataForSigning();
    final sig = await Ed25519().sign(signingBytes, keyPair: signingPrivateKey);
    return BitchatPacket(
      version: packet.version,
      type: packet.type,
      senderId: packet.senderId,
      recipientId: packet.recipientId,
      timestamp: packet.timestamp,
      payload: packet.payload,
      signature: Uint8List.fromList(sig.bytes),
      ttl: packet.ttl,
      route: packet.route,
      isRsr: packet.isRsr,
    );
  }

  /// Verify a packet's signature against the given Ed25519 public key.
  static Future<bool> verifyPacket(
    BitchatPacket packet,
    Uint8List ed25519PublicKey,
  ) async {
    final signature = packet.signature;
    if (signature == null || signature.length != 64) return false;
    final signingBytes = packet.toBinaryDataForSigning();
    try {
      final ok = await Ed25519().verify(
        signingBytes,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(
            ed25519PublicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      );
      return ok;
    } on Exception {
      return false;
    }
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
