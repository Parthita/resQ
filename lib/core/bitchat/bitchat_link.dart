import 'dart:async';
import 'dart:typed_data';

/// A peer discovered/connected at the BLE link layer.
/// [id] is the BLE device UUID; [name] is the advertised name (may be null);
/// [connected] flips true once the GATT link is up.
class LinkPeer {
  LinkPeer({
    required this.id,
    this.name,
    this.identityHint,
    this.connected = false,
  });

  final String id;
  final String? name;

  /// The sender-id advertised by a resQ peer, when available.
  final String? identityHint;
  final bool connected;

  LinkPeer copyWith({bool? connected}) => LinkPeer(
    id: id,
    name: name,
    identityHint: identityHint,
    connected: connected ?? this.connected,
  );
}

/// Abstract byte-pipe between two mesh peers over BLE.
///
/// The mesh layer (flood router + fragmentation) only cares about sending and
/// receiving opaque byte frames. The concrete implementation may be the real
/// bluetooth_low_energy adapter (central + peripheral GATT) OR an in-memory
/// mock used for headless tests. Keeping this narrow means M5 (flood routing)
/// is fully testable without a phone.
///
/// Wire rule: each [send] carries ONE fragment packet's raw encoded bytes
/// (<= 469 + header). The receiver hands those exact bytes to the fragment
/// assembler. No framing/length headers are added here — BLE GATT write value
/// already carries the full buffer.
abstract class BitchatLink {
  /// Fires with raw bytes received from a peer.
  Stream<Uint8List> get received;

  /// Fires when a peer is discovered or its connection state changes.
  /// The mesh controller turns these into the UI peer list.
  Stream<LinkPeer> get peers;

  /// True when the BLE adapter is actually powered on. This is the
  /// authoritative adapter state (NOT the Android permission status, which
  /// reports 'restricted' even when BT is on and must not be used to decide
  /// whether the mesh can start).
  bool get isPoweredOn;

  /// Send raw bytes to peers. Returns true if the link accepted the frame.
  Future<bool> send(Uint8List frame);

  /// Begin advertising/scanning so peers can connect and exchange frames.
  Future<void> start();

  /// Stop advertising/scanning and release resources.
  Future<void> stop();

  /// Permanently release the link's streams. Called when the link is discarded.
  Future<void> dispose();
}

/// In-memory loopback link for tests. Two links can be "paired" so a [send] on
/// one delivers to the other's [received] stream, modelling a BLE connection.
class MockBitchatLink implements BitchatLink {
  MockBitchatLink({this.label = 'mock'});

  final String label;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();
  final StreamController<LinkPeer> _peerController =
      StreamController<LinkPeer>.broadcast();
  final List<MockBitchatLink> _peers = [];
  bool _started = false;

  /// Wire this link to another so frames flow both ways.
  void pairWith(MockBitchatLink other) {
    if (!_peers.contains(other)) _peers.add(other);
    if (!other._peers.contains(this)) other._peers.add(this);
  }

  final List<Uint8List> sentFrames = [];

  @override
  Stream<Uint8List> get received => _controller.stream;

  @override
  Stream<LinkPeer> get peers => _peerController.stream;

  @override
  bool get isPoweredOn => true;

  @override
  Future<bool> send(Uint8List frame) async {
    sentFrames.add(Uint8List.fromList(frame));
    for (final peer in _peers) {
      // deliver asynchronously, mirroring BLE's async delivery
      Future(() => peer._deliver(frame));
    }
    return true;
  }

  void _deliver(Uint8List frame) {
    if (!_started) return;
    _controller.add(Uint8List.fromList(frame));
  }

  @override
  Future<void> start() async {
    _started = true;
    // Model the BLE link lifecycle as well as byte delivery.  The controller
    // uses this to distinguish an accepted relationship from an available
    // transport path.
    for (final peer in _peers.where((peer) => peer._started)) {
      _peerController.add(LinkPeer(id: peer.label, connected: true));
      peer._peerController.add(LinkPeer(id: label, connected: true));
    }
  }

  @override
  Future<void> stop() async {
    _started = false;
    for (final peer in _peers.where((peer) => peer._started)) {
      peer._peerController.add(LinkPeer(id: label, connected: false));
    }
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    await _peerController.close();
  }
}
