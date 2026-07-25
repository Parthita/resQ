import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

import 'core/bitchat/bitchat_link.dart';
import 'core/bitchat/ble_link.dart';
import 'core/bitchat/flood_router.dart';
import 'core/bitchat/identity_service.dart';
import 'core/bitchat/sync_doc_tunnel.dart';

/// High-level controller that turns on the BitChat-style mesh for resQ.
///
/// Owns the full stack:
///   MeshController
///     -> BleLink (real dual-role BLE) OR injected BitchatLink (tests)
///     -> FloodRouter (dedup + TTL flood)
///     -> MeshIdentity (X25519 + Ed25519, senderID derivation)
///     -> SyncDocTunnel (Yjs CRDT sync over the mesh)
///
/// Design choice: this class has NO Flutter dependency, so it is fully
/// unit-testable with a [MockBitchatLink] (same pattern as FloodRouter tests).
/// The UI layer just calls start()/stop() and listens to [state] / [peers].
class MeshController {
  MeshController({BitchatLink? link, this.useMainnet = false})
      : _preferredLink = link;

  final bool useMainnet;
  final BitchatLink? _preferredLink;

  /// Lazily created. We must NOT construct BleLink (which instantiates
  /// CentralManager/PeripheralManager) in the constructor: those throw
  /// UnimplementedError off-device, and on-device we only want to pay the cost
  /// when the mesh actually starts. Built on first requestPermissions()/start().
  BitchatLink? _link;

  late MeshIdentity identity;
  late FloodRouter router;
  late SyncDocTunnel tunnel;
  BitchatLink get link {
    _ensureLink();
    return _link!;
  }

  /// True once the mesh has actually started and an identity exists.
  bool get isStarted => _state == MeshState.running;

  /// My sender id as a hex string, or '' before the mesh starts.
  String get myIdHex {
    if (_state != MeshState.running) return '';
    return identity.senderId
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Current snapshot of peers, for widgets that mount AFTER peers were
  /// already discovered (a broadcast stream has no replay).
  List<MeshPeer> get currentPeers => List.of(_peers);

  /// Current connection count for widgets that mount late.
  int get connectedCount => _peers.where((p) => p.connected).length;

  void _ensureLink() {
    _link ??= _preferredLink ?? BleLink(useMainnet: useMainnet);
  }

  final _stateController = StreamController<MeshState>.broadcast();
  final _peerController = StreamController<List<MeshPeer>>.broadcast();

  MeshState _state = MeshState.stopped;
  MeshState get state => _state;
  Stream<MeshState> get stateStream => _stateController.stream;
  Stream<List<MeshPeer>> get peersStream => _peerController.stream;

  final List<MeshPeer> _peers = [];

  /// Request BLE permissions AND verify the Bluetooth adapter is on.
  /// Returns a [MeshPermissionResult] so the UI can tell the user exactly what
  /// is missing. The adapter check uses [BitchatLink.isPoweredOn] (the real
  /// CentralManager state) — NOT Permission.bluetooth.status, which reports
  /// 'restricted' on Android 12+ even when BT is actually on.
  Future<MeshPermissionResult> requestPermissions() async {
    _ensureLink();
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    final allGranted = statuses.values.every((s) => s.isGranted);
    if (!allGranted) {
      return MeshPermissionResult(ok: false, reason: 'permissions');
    }

    if (!_link!.isPoweredOn) {
      return MeshPermissionResult(ok: false, reason: 'bluetooth_off');
    }

    return MeshPermissionResult(ok: true);
  }

  Future<void> start() async {
    _setState(MeshState.starting);
    _ensureLink();

    try {
      identity = await MeshIdentity.generate();
      router = FloodRouter(link: _link!, chunkSize: 469);
      tunnel = SyncDocTunnel(router: router, senderId: identity.senderId);

      // surface real BLE discoveries to the UI peer list
      _link!.peers.listen(_onLinkPeer);

      // We verify peer signatures using their announced Ed25519 key. For now
      // the router has no verifier wired (open mesh); the SyncDocTunnel still
      // applies CRDT updates. To enforce identity, pass a verifier built from a
      // learned key table (populated from announce TLV 0x03).
      await tunnel.start();
    } on BluetoothOffException {
      // Adapter is off — drop back to stopped and let the UI show the hint.
      _setState(MeshState.stopped);
      rethrow;
    }

    _setState(MeshState.running);
  }

  void _onLinkPeer(LinkPeer p) {
    final idx = _peers.indexWhere((e) => e.id == p.id);
    final peer = MeshPeer(
      id: p.id,
      nickname: p.name ?? p.id,
      lastSeen: DateTime.now(),
      connected: p.connected,
    );
    if (idx >= 0) {
      _peers[idx] = peer;
    } else {
      _peers.add(peer);
    }
    _peerController.add(List.of(_peers));
  }

  /// Broadcast a small text note as a CRDT update over the mesh.
  Future<void> publishNote(String text) async {
    tunnel.text.insert(tunnel.text.length, text);
    await tunnel.broadcastUpdate();
  }

  void _setState(MeshState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> stop() async {
    if (_state == MeshState.stopped) return; // idempotent
    _setState(MeshState.stopping);
    await tunnel.stop();
    _peers.clear();
    _peerController.add(const []);
    _setState(MeshState.stopped);
    // Drop the BLE link so the next start() builds a fresh one (the old link's
    // GATT server/scan was torn down and its controllers closed).
    _link = null;
    // NOTE: do NOT close _stateController / _peerController here. Closing them
    // makes a later start() throw when it calls _setState(). They are only
    // closed in dispose(), when the controller is truly gone.
  }

  /// Permanently release resources. Call when the owning widget is disposed.
  Future<void> dispose() async {
    await stop();
    await _link?.dispose();
    await _stateController.close();
    await _peerController.close();
  }
}

enum MeshState { stopped, starting, running, stopping }

class MeshPeer {
  MeshPeer({
    required this.id,
    required this.nickname,
    this.lastSeen,
    this.connected = false,
  });

  final String id;
  final String nickname;
  final DateTime? lastSeen;
  final bool connected;
}

/// Result of the runtime permission + adapter check.
class MeshPermissionResult {
  MeshPermissionResult({required this.ok, this.reason});

  final bool ok;
  /// 'permissions' if BLE perms denied, 'bluetooth_off' if adapter is off.
  final String? reason;
}
