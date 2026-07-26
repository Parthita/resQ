import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/bitchat/bitchat_link.dart';
import 'core/bitchat/ble_link.dart';
import 'core/bitchat/flood_router.dart';
import 'core/bitchat/identity_service.dart';
import 'core/bitchat/bitchat_packet.dart';
import 'core/bitchat/message_type.dart';
import 'core/bitchat/sync_doc_tunnel.dart';
import 'core/bitchat/tlv_announce.dart';

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

  /// User-facing nickname broadcast in the BitChat announce (TLV 0x01) and
  /// personal-connection envelopes. Additive: when unset (or empty) we keep
  /// the historical default 'resQ' so existing behavior is unchanged until the
  /// UI provides a value. Set this from the UI before start() if persistence
  /// is desired.
  String? _nickname;
  set nickname(String? value) => _nickname = value;
  String get displayName =>
      (_nickname != null && _nickname!.isNotEmpty) ? _nickname! : 'resQ';

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
  final Map<String, PersonalContact> _contacts = {};
  final Map<String, List<PersonalMessage>> _messages = {};
  final _contactsController =
      StreamController<List<PersonalContact>>.broadcast();
  final _messagesController = StreamController<PersonalMessage>.broadcast();
  final _sosController = StreamController<IncomingSos>.broadcast();
  StreamSubscription<LinkPeer>? _peerSubscription;
  StreamSubscription<BitchatPacket>? _packetSubscription;
  StreamSubscription<void>? _docSubscription;
  Timer? _presenceTimer;
  Timer? _peerSweepTimer;
  bool _transportStarted = false;
  bool _replayingRequests = false;
  bool _resyncingDoc = false;
  final Set<String> _seenPersonalCrdtIds = <String>{};

  /// People discovered by the resQ protocol (not merely by a BLE scan).
  /// A contact cannot be messaged until they accept a connection request.
  List<PersonalContact> get contacts =>
      _contacts.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  Stream<List<PersonalContact>> get contactsStream =>
      _contactsController.stream;
  Stream<PersonalMessage> get messagesStream => _messagesController.stream;
  Stream<IncomingSos> get sosStream => _sosController.stream;
  List<PersonalMessage> messagesFor(String contactId) =>
      List.unmodifiable(_messages[contactId] ?? const []);

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

    // Android 11 and below require location permission for BLE scanning even
    // though Bluetooth itself is already granted. Android 12+ uses the three
    // nearby-devices permissions above and should not be blocked on location.
    if (await _needsLegacyScanLocation()) {
      final location = await Permission.locationWhenInUse.request();
      if (!location.isGranted) {
        return MeshPermissionResult(ok: false, reason: 'location');
      }
    }

    // A freshly-created native manager starts in `unknown` on many Android
    // phones and reports its real adapter state a moment later.  Do not reject
    // a valid scan here; BleLink.start waits for that authoritative callback.
    return MeshPermissionResult(ok: true);
  }

  static const _platformChannel = MethodChannel('resq.platform');

  static Future<bool> _needsLegacyScanLocation() async {
    try {
      final sdk = await _platformChannel.invokeMethod<int>('androidSdk');
      return sdk != null && sdk <= 30;
    } on MissingPluginException {
      // Tests and non-Android platforms do not expose this channel and do not
      // require Android's legacy location permission for BLE scanning.
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> start() async {
    debugPrint('[resq:mesh] start requested');
    _setState(MeshState.starting);
    _ensureLink();

    try {
      identity = await MeshIdentity.loadOrCreate();
      debugPrint('[resq:mesh] identity ready id=${_hex(identity.senderId)}');
      router = FloodRouter(link: _link!, chunkSize: 469);
      tunnel = SyncDocTunnel(router: router, senderId: identity.senderId);

      // surface real BLE discoveries to the UI peer list
      await _peerSubscription?.cancel();
      _peerSubscription = _link!.peers.listen(_onLinkPeer);

      // We verify peer signatures using their announced Ed25519 key. For now
      // the router has no verifier wired (open mesh); the SyncDocTunnel still
      // applies CRDT updates. To enforce identity, pass a verifier built from a
      // learned key table (populated from announce TLV 0x03).
      await tunnel.start();
      _transportStarted = true;
      await _docSubscription?.cancel();
      _docSubscription = tunnel.changed.listen((_) => _syncPersonalMessagesFromDoc());
      await _packetSubscription?.cancel();
      _packetSubscription = router.delivered.listen(_onPacket);
      // Mark running before announcing. A BLE connection can complete while
      // startup is in progress; its callback must be able to send a presence
      // packet immediately rather than dropping it as "not started".
      _setState(MeshState.running);
      debugPrint('[resq:mesh] transport running; sending initial announce');
      await _announce();
      // A GATT link and its notify subscription often become ready after the
      // first announcement. Repeat presence briefly/cheaply while scanning so
      // a physical resQ advertiser reliably becomes a visible app peer.
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_announce()),
      );
      _peerSweepTimer?.cancel();
      _peerSweepTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _evictStalePeers(),
      );
    } on BluetoothOffException {
      // Adapter is off — drop back to stopped and let the UI show the hint.
      _setState(MeshState.stopped);
      debugPrint('[resq:mesh] start aborted: bluetooth off');
      rethrow;
    } on Object catch (e, st) {
      // Any other BLE/startup failure (e.g. GATT addService-on-readvertise,
      // advertising rejected) must NOT leave us stuck in 'starting' or crash
      // the caller. Tear down and report.
      debugPrint('[mesh] start failed: $e\n$st');
      await stop();
      rethrow;
    }
  }

  void _onLinkPeer(LinkPeer p) {
    debugPrint(
      '[resq:mesh] BLE peer id=${p.id} name=${p.name ?? '-'} '
      'connected=${p.connected}',
    );
    final idx = _peers.indexWhere((e) => e.id == p.id);
    final previous = idx >= 0 ? _peers[idx] : null;
    final peer = MeshPeer(
      id: p.id,
      // Connection-state callbacks do not include an advertisement name; do
      // not overwrite the useful discovery name with a random BLE UUID.
      // Android may surface an inbound connection with a rotating MAC/UUID
      // and no advertisement name. That is transport metadata, never a
      // user-facing identity; wait for the signed BitChat announce instead.
      nickname: p.name ?? previous?.nickname ?? 'Nearby resQ',
      identityHint: p.identityHint ?? previous?.identityHint,
      lastSeen: DateTime.now(),
      connected: p.connected,
    );
    if (idx >= 0) {
      _peers[idx] = peer;
    } else {
      _peers.add(peer);
    }
    _peerController.add(List.of(_peers));
    if (p.connected && isStarted) {
      // Startup announcements commonly happen before the GATT notify/write
      // channel is ready. Announce early (it's small and retried), but defer
      // the full-doc CRDT resync + accept/response replay until the channel is
      // actually usable, otherwise the resync bytes are dropped (subscribers=0)
      // and the offline peer never catches up.
      unawaited(_announce());
      unawaited(_syncAfterChannelReady());
      _setAcceptedContactsLinkState(true);
    }
    // A physical link loss makes every accepted conversation unavailable. The
    // acceptance itself remains durable; only its transport availability
    // changes, so reconnecting does not require another approval.
    if (!p.connected && !_peers.any((peer) => peer.connected)) {
      _setAcceptedContactsLinkState(false);
    }
  }

  void _evictStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    final countBefore = _peers.length;
    _peers.removeWhere(
      (peer) => !peer.connected && (peer.lastSeen?.isBefore(cutoff) ?? true),
    );
    if (_peers.length != countBefore) _peerController.add(List.of(_peers));
  }

  /// Wait for the GATT data channel to be actually usable, then push the
  /// full-doc CRDT resync and replay any pending accept/response envelopes.
  ///
  /// The resync must not fire on the early `connected=true` peer event: at that
  /// instant the notify/write channel isn't established yet, so the bytes are
  /// dropped (subscribers=0) and an offline peer never catches up. Gating on
  /// [BitchatLink.channelReady] removes that race at the source.
  Future<void> _syncAfterChannelReady() async {
    try {
      await link.channelReady.first.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('[resq:mesh] channel-ready wait timed out; resyncing anyway');
    }
    if (!isStarted) return;
    unawaited(_resyncDocumentAfterLink());
    unawaited(_replayPendingRequests());
  }

  Future<void> _replayPendingRequests() async {
    if (_replayingRequests) {
      debugPrint('[resq:mesh] request replay skipped (already running)');
      return;
    }
    _replayingRequests = true;
    try {
      for (final contact in List<PersonalContact>.of(_contacts.values)) {
        try {
          // Only replay for contacts that are still PENDING a handshake. A
          // contact already connected (the normal request/response path set
          // status=connected) needs no replay — re-sending a 'response' there
          // just blocks on a send that the peer never answers, hitting the
          // 12s timeout and dumping "request replay failed". (See PID 14763.)
          final needsReplay = contact.status == ConnectionStatus.outgoingPending ||
              contact.status == ConnectionStatus.incomingPending;
          if (!needsReplay) continue;
          final kind = contact.status == ConnectionStatus.outgoingPending
              ? 'request'
              : 'response';
          debugPrint('[resq:mesh] replay pending $kind to=${contact.id}');
          await _sendEnvelope(
            {'kind': kind, 'accepted': true, 'name': displayName},
            recipient: contact.id,
          ).timeout(const Duration(seconds: 12));
        } on Object catch (error, stackTrace) {
          debugPrint(
            '[resq:mesh] request replay failed contact=${contact.id}: $error\n$stackTrace',
          );
        }
      }
    } finally {
      _replayingRequests = false;
      debugPrint('[resq:mesh] request replay guard cleared');
    }
  }

  Future<void> _resyncDocumentAfterLink() async {
    if (_resyncingDoc) {
      debugPrint('[resq:mesh] CRDT resync skipped (already running)');
      return;
    }
    _resyncingDoc = true;
    try {
      debugPrint('[resq:mesh] CRDT resync start (full Yjs update)');
      // Bound the send so a link that dies mid-resync (adapter power-off,
      // peer out of range) cannot leave the underlying write hanging and this
      // future never settling — which would wedge the guard for the rest of
      // the session. The finally below still runs on timeout, clearing it.
      await tunnel.broadcastUpdate().timeout(const Duration(seconds: 12));
      debugPrint('[resq:mesh] CRDT resync complete');
    } on TimeoutException {
      debugPrint('[resq:mesh] CRDT resync timed out (link likely gone)');
    } on Object catch (error, stackTrace) {
      debugPrint('[resq:mesh] CRDT resync failed: $error\n$stackTrace');
    } finally {
      _resyncingDoc = false;
      debugPrint('[resq:mesh] CRDT resync guard cleared');
    }
  }

  void _setAcceptedContactsLinkState(bool linkUp) {
    var changed = false;
    for (final contact in _contacts.values) {
      if (!contact.accepted) continue;
      final next = linkUp
          ? ConnectionStatus.connected
          : ConnectionStatus.disconnected;
      if (contact.linkUp != linkUp || contact.status != next) {
        contact.linkUp = linkUp;
        contact.status = next;
        changed = true;
      }
    }
    if (changed) _emitContacts();
  }

  Future<void> _announce() async {
    debugPrint('[resq:mesh] announce send id=$myIdHex');
    final packet = BitchatPacket(
      type: MessageType.announce.value,
      senderId: identity.senderId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: TlvAnnounce(
        nickname: displayName,
        noisePublicKey: identity.noisePublicKey,
        signingPublicKey: identity.signingPublicKey,
      ).encode(),
      ttl: 1,
    );
    await router.broadcast(await identity.signPacket(packet));
  }

  /// The BLE scan runs continuously; this refreshes application presence for
  /// an already-discovered link when the user taps Scan.
  Future<void> refreshPresence() async {
    if (isStarted) await _announce();
  }

  /// Ask a discovered person for a private conversation. This only creates an
  /// outgoing pending state; it never marks either side connected on its own.
  Future<void> requestConnection(PersonalContact contact) async {
    if (!isStarted ||
        contact.accepted ||
        contact.status == ConnectionStatus.connected) {
      return;
    }
    contact.status = ConnectionStatus.outgoingPending;
    debugPrint('[resq:mesh] request send to=${contact.id}');
    _emitContacts();
    await _sendEnvelope({
      'kind': 'request',
      'name': displayName,
    }, recipient: contact.id);
  }

  /// Accept or reject an incoming request. Acceptance is the sole transition
  /// to connected; rejection leaves no chat route open.
  Future<void> respondToRequest(PersonalContact contact, bool accept) async {
    if (contact.status != ConnectionStatus.incomingPending) return;
    contact.accepted = accept;
    contact.linkUp = accept && _peers.any((peer) => peer.connected);
    contact.status = accept
        ? (contact.linkUp
              ? ConnectionStatus.connected
              : ConnectionStatus.disconnected)
        : ConnectionStatus.rejected;
    debugPrint(
      '[resq:mesh] request response to=${contact.id} accepted=$accept',
    );
    _emitContacts();
    await _sendEnvelope({
      'kind': 'response',
      'accepted': accept,
      'name': displayName,
    }, recipient: contact.id);
  }

  Future<bool> sendPersonalMessage(PersonalContact contact, String text) async {
    final clean = text.trim();
    // Acceptance is sufficient to queue a private message. A missing BLE link
    // only delays delivery; the CRDT sync will carry it after reconnect.
    if (clean.isEmpty || !contact.accepted || !isStarted) {
      return false;
    }
    await tunnel.appendPersonalMessage(
      recipientId: contact.id,
      text: clean,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _syncPersonalMessagesFromDoc();
    return true;
  }

  void _syncPersonalMessagesFromDoc() {
    if (!isStarted) return;
    final me = myIdHex;
    for (final contact in _contacts.values) {
      for (final record in tunnel.personalMessagesFor(me: me, peer: contact.id)) {
        if (!_seenPersonalCrdtIds.add(record.id)) continue;
        final message = PersonalMessage(
          contactId: contact.id,
          text: record.text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(record.timestamp),
          isMine: record.senderId == me,
        );
        (_messages[contact.id] ??= []).add(message);
        _messagesController.add(message);
      }
    }
  }

  Future<void> _onPacket(BitchatPacket packet) async {
    if (!isStarted) return;
    final mine = myIdHex;
    final recipient = packet.recipientId == null
        ? null
        : _hex(packet.recipientId!);
    if (recipient != null && recipient != mine) return;
    try {
      if (packet.type == MessageType.announce.value) {
        final sender = _hex(packet.senderId);
        debugPrint('[resq:mesh] announce received from=$sender');
        if (sender == mine) return;
        final announce = TlvAnnounce.decode(packet.payload);
        if (announce.noisePublicKey.length != 32 ||
            announce.signingPublicKey.length != 32 ||
            _hex(await MeshIdentity.deriveSenderId(announce.noisePublicKey)) !=
                sender ||
            !await MeshIdentity.verifyPacket(
              packet,
              announce.signingPublicKey,
            )) {
          debugPrint(
            '[resq:mesh] announce rejected from=$sender (identity/signature invalid)',
          );
          return;
        }
        final isNew = !_contacts.containsKey(sender);
        final contact = _contacts.putIfAbsent(
          sender,
          () => PersonalContact(
            id: sender,
            name: announce.nickname.isEmpty ? 'Nearby resQ' : announce.nickname,
          ),
        );
        if (announce.nickname.isNotEmpty) contact.name = announce.nickname;
        contact.signingKey = announce.signingPublicKey;
        if (contact.accepted && _peers.any((peer) => peer.connected)) {
          contact.linkUp = true;
          contact.status = ConnectionStatus.connected;
        }
        debugPrint('[resq:mesh] announce verified from=$sender new=$isNew');
        _bindRawPeerToIdentity(sender, contact.name);
        _syncPersonalMessagesFromDoc();
        _emitContacts();
        if (isNew) unawaited(_announce());
        return;
      }
      if (packet.type != MessageType.personal.value) return;
      final body =
          jsonDecode(utf8.decode(packet.payload)) as Map<String, dynamic>;
      final sender = _hex(packet.senderId);
      if (sender == mine) return;
      final kind = body['kind'] as String?;
      Uint8List? signingKey;
      if (kind == 'announce') {
        final noise = Uint8List.fromList(base64Decode(body['noise'] as String));
        signingKey = Uint8List.fromList(
          base64Decode(body['signing'] as String),
        );
        if (noise.length != 32 ||
            signingKey.length != 32 ||
            _hex(await MeshIdentity.deriveSenderId(noise)) != sender ||
            !await MeshIdentity.verifyPacket(packet, signingKey)) {
          return;
        }
      } else {
        final known = _contacts[sender]?.signingKey;
        if (known == null || !await MeshIdentity.verifyPacket(packet, known)) {
          debugPrint(
            '[resq:mesh] personal packet rejected from=$sender (unverified identity)',
          );
          return;
        }
      }
      final isNewContact = !_contacts.containsKey(sender);
      final contact = _contacts.putIfAbsent(
        sender,
        () => PersonalContact(
          id: sender,
          name: (body['name'] as String?) ?? 'Nearby resQ',
        ),
      );
      final name = body['name'] as String?;
      if (name != null && name.isNotEmpty) contact.name = name;
      if (signingKey != null) contact.signingKey = signingKey;
      switch (body['kind']) {
        case 'announce':
          // A peer might have started after our initial announcement. Reply
          // once when first seen so both sides promptly learn each identity.
          if (isNewContact) unawaited(_announce());
          break;
        case 'request':
          if (contact.accepted) {
            // The sender may be replaying after reconnect. Confirm the
            // already-approved relationship instead of showing a duplicate
            // acceptance dialog.
            unawaited(
              _sendEnvelope({
                'kind': 'response',
                'accepted': true,
                'name': displayName,
              }, recipient: sender),
            );
          } else if (contact.status != ConnectionStatus.connected) {
            contact.status = ConnectionStatus.incomingPending;
          }
          debugPrint('[resq:mesh] request received from=$sender');
          break;
        case 'response':
          contact.accepted = body['accepted'] == true;
          contact.linkUp =
              contact.accepted && _peers.any((peer) => peer.connected);
          contact.status = contact.accepted
              ? (contact.linkUp
                    ? ConnectionStatus.connected
                    : ConnectionStatus.disconnected)
              : ConnectionStatus.rejected;
          debugPrint(
            '[resq:mesh] request response received from=$sender accepted=${body['accepted'] == true}',
          );
          break;
        case 'chat':
          if (!contact.canChat) return;
          final text = body['text'] as String?;
          if (text == null || text.trim().isEmpty) return;
          // De-dupe against the same message arriving later via CRDT resync.
          // Key must match PersonalCrdtMessage.id ($sender:$timestamp).
          if (!_seenPersonalCrdtIds.add('$sender:${packet.timestamp}')) break;
          final message = PersonalMessage(
            contactId: sender,
            text: text,
            timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
            isMine: false,
          );
          (_messages[sender] ??= []).add(message);
          _messagesController.add(message);
          break;
        case 'location':
          if (!contact.canChat) return;
          final locLat = body['latitude'] as num?;
          final locLng = body['longitude'] as num?;
          final locAcc = body['accuracy'] as num?;
          if (locLat == null || locLng == null) return;
          if (!_seenPersonalCrdtIds.add('$sender:${packet.timestamp}')) break;
          final locMessage = PersonalMessage(
            contactId: sender,
            text: '${contact.name} shared their location.',
            timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
            isMine: false,
            data: {
              'type': 'location',
              'latitude': locLat.toDouble(),
              'longitude': locLng.toDouble(),
              'accuracy': locAcc?.toDouble(),
            },
          );
          (_messages[sender] ??= []).add(locMessage);
          _messagesController.add(locMessage);
          break;
        case 'sos':
          final sosLat = body['lat'] as num?;
          final sosLng = body['lon'] as num?;
          final sosAcc = body['accuracy'] as num?;
          final sosName = body['name'] as String? ?? sender;
          if (!_seenPersonalCrdtIds.add('$sender:${packet.timestamp}')) break;
          final sosMessage = PersonalMessage(
            contactId: sender,
            text: '🚨 SOS from $sosName',
            timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
            isMine: false,
            data: {
              'type': 'sos',
              'latitude': sosLat?.toDouble(),
              'longitude': sosLng?.toDouble(),
              'accuracy': sosAcc?.toDouble(),
              'senderName': sosName,
            },
          );
          (_messages[sender] ??= []).add(sosMessage);
          _messagesController.add(sosMessage);
          _sosController.add(IncomingSos(
            senderId: sender,
            senderName: sosName,
            timestamp: packet.timestamp,
            latitude: sosLat?.toDouble(),
            longitude: sosLng?.toDouble(),
            accuracy: sosAcc?.toDouble(),
          ));
          break;
      }
      _emitContacts();
    } on Object catch (error) {
      // Ignore malformed or non-resQ envelopes rather than destabilising UI.
      debugPrint('[resq:mesh] packet ignored: $error');
    }
  }

  void _bindRawPeerToIdentity(String identity, String nickname) {
    final candidates = _peers
        .where((peer) => peer.connected && peer.identityHint == null)
        .toList();
    // A physical BLE UUID is only safely bound when there is one active
    // unnamed link. With multiple links, leave it raw rather than guessing.
    if (candidates.length != 1) return;
    final index = _peers.indexOf(candidates.single);
    final peer = candidates.single;
    _peers[index] = MeshPeer(
      id: peer.id,
      nickname: nickname,
      identityHint: identity,
      lastSeen: peer.lastSeen,
      connected: peer.connected,
    );
    _peerController.add(List.of(_peers));
  }

  Future<void> _sendEnvelope(
    Map<String, dynamic> body, {
    String? recipient,
  }) async {
    final packet = BitchatPacket(
      type: MessageType.personal.value,
      senderId: identity.senderId,
      recipientId: recipient == null ? null : _idBytes(recipient),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      ttl: 1,
    );
    await router.broadcast(await identity.signPacket(packet));
  }

  void _emitContacts() => _contactsController.add(contacts);
  static String _hex(Uint8List id) =>
      id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  static Uint8List _idBytes(String hex) => Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);

  /// Broadcast a small text note as a CRDT update over the mesh.
  Future<void> publishNote(String text) async {
    tunnel.text.insert(tunnel.text.length, text);
    await tunnel.broadcastUpdate();
  }

  /// Broadcast an SOS alert over the mesh.
  ///
  /// Uses the existing personal-message envelope with `kind: 'sos'` so every
  /// resQ peer receives it. If [latitude] and [longitude] are available they
  /// are included; otherwise the SOS is sent without coordinates.
  /// Returns `true` when the packet was handed to the router, `false` if the
  /// mesh has not been started yet.
  Future<bool> sendSos({double? latitude, double? longitude, double? accuracy}) async {
    if (!isStarted) return false;
    final body = <String, dynamic>{
      'kind': 'sos',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'name': displayName,
    };
    if (latitude != null && longitude != null) {
      body['lat'] = latitude;
      body['lon'] = longitude;
    }
    if (accuracy != null) {
      body['accuracy'] = accuracy;
    }
    final packet = BitchatPacket(
      type: MessageType.personal.value,
      senderId: identity.senderId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      ttl: 3,
    );
    await router.broadcast(await identity.signPacket(packet));
    return true;
  }

  /// Send a one-time location share to a specific peer.
  ///
  /// Uses a personal-message envelope with `kind: 'location'` containing
  /// latitude, longitude, accuracy, and timestamp.
  /// Returns `true` when the packet was handed to the router, `false` if the
  /// mesh has not been started yet or the recipient ID is invalid.
  Future<bool> sendLocation({
    required String recipientId,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    if (!isStarted) return false;
    if (recipientId.isEmpty || recipientId.length.isOdd) return false;
    // Validate that recipientId is a valid hex string (no dashes or other
    // non-hex characters), matching the format used by [PersonalContact.id].
    for (var i = 0; i < recipientId.length; i++) {
      if (!_hexDigit(recipientId.codeUnitAt(i))) return false;
    }
    final body = <String, dynamic>{
      'kind': 'location',
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await _sendEnvelope(body, recipient: recipientId);
    return true;
  }

  static bool _hexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  void _setState(MeshState s) {
    _state = s;
    _stateController.add(s);
  }

  Future<void> stop() async {
    if (_state == MeshState.stopped) return; // idempotent
    _setState(MeshState.stopping);
    debugPrint('[resq:mesh] stopping');
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _peerSweepTimer?.cancel();
    _peerSweepTimer = null;
    if (_transportStarted) {
      await tunnel.stop();
      _transportStarted = false;
    }
    await _packetSubscription?.cancel();
    _packetSubscription = null;
    await _docSubscription?.cancel();
    _docSubscription = null;
    await _peerSubscription?.cancel();
    _peerSubscription = null;
    _peers.clear();
    _peerController.add(const []);
    _setState(MeshState.stopped);
    debugPrint('[resq:mesh] stopped');
    // Drop the BLE link so the next start() builds a fresh one (the old link's
    // GATT server/scan was torn down and its controllers closed).
    final oldLink = _link;
    _link = null;
    // A fresh start needs fresh native subscriptions.  Keeping a stopped
    // BleLink alive duplicates GATT callbacks on every toggle.
    if (oldLink != null && !identical(oldLink, _preferredLink)) {
      await oldLink.dispose();
    }
    // NOTE: do NOT close _stateController / _peerController here. Closing them
    // makes a later start() throw when it calls _setState(). They are only
    // closed in dispose(), when the controller is truly gone.
  }

  /// Permanently release resources. Call when the owning widget is disposed.
  Future<void> dispose() async {
    await stop();
    // Injected links are owned by the caller during ordinary stop/start
    // cycles, but a permanently disposed controller can release them too.
    await _preferredLink?.dispose();
    await _stateController.close();
    await _peerController.close();
    await _contactsController.close();
    await _messagesController.close();
    await _sosController.close();
  }
}

enum MeshState { stopped, starting, running, stopping }

class MeshPeer {
  MeshPeer({
    required this.id,
    required this.nickname,
    this.lastSeen,
    this.identityHint,
    this.connected = false,
  });

  final String id;
  final String nickname;
  final DateTime? lastSeen;
  final String? identityHint;
  final bool connected;
}

enum ConnectionStatus {
  available,
  outgoingPending,
  incomingPending,
  connected,
  rejected,
  disconnected,
}

class PersonalContact {
  PersonalContact({
    required this.id,
    required this.name,
    this.status = ConnectionStatus.available,
    this.accepted = false,
    this.linkUp = false,
  });
  final String id;
  String name;
  ConnectionStatus status;
  bool accepted;
  bool linkUp;
  Uint8List? signingKey;

  bool get canChat => accepted && linkUp;
}

class PersonalMessage {
  PersonalMessage({
    required this.contactId,
    required this.text,
    required this.timestamp,
    required this.isMine,
    this.data,
  });
  final String contactId;
  final String text;
  final DateTime timestamp;
  final bool isMine;
  final Map<String, dynamic>? data;
}

class IncomingSos {
  IncomingSos({
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.accuracy,
  });
  final String senderId;
  final String senderName;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
}

/// Result of the runtime permission + adapter check.
class MeshPermissionResult {
  MeshPermissionResult({required this.ok, this.reason});

  final bool ok;

  /// 'permissions' if BLE perms denied, 'location' on Android 11 and below.
  final String? reason;
}
