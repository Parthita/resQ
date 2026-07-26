import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'bitchat_packet.dart';
import 'flood_router.dart';
import 'message_type.dart';

/// A single chat message as stored in the CRDT array.
class ChatMessage {
  ChatMessage({
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  final String senderId;
  final String text;
  final int timestamp;

  /// Encode as a JSON string so it round-trips through `YArray<String>` safely
  /// (any text is allowed; we never hand-roll delimiters).
  String toWire() => jsonEncode({'s': senderId, 't': timestamp, 'm': text});

  static ChatMessage fromWire(String wire) {
    final m = jsonDecode(wire) as Map<String, dynamic>;
    return ChatMessage(
      senderId: m['s'] as String,
      text: m['m'] as String,
      timestamp: m['t'] as int,
    );
  }
}

/// Private conversation record replicated through the CRDT. Each device only
/// renders records addressed to itself or authored by itself.
class PersonalCrdtMessage {
  PersonalCrdtMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String text;
  final int timestamp;

  String toWire() => jsonEncode({
    'id': id,
    'from': senderId,
    'to': recipientId,
    't': timestamp,
    'm': text,
  });

  static PersonalCrdtMessage fromWire(String wire) {
    final map = jsonDecode(wire) as Map<String, dynamic>;
    return PersonalCrdtMessage(
      id: map['id'] as String,
      senderId: map['from'] as String,
      recipientId: map['to'] as String,
      text: map['m'] as String,
      timestamp: map['t'] as int,
    );
  }
}

/// Tunnel that carries Yjs CRDT updates over the BitChat mesh.
///
/// This is the project's novelty: native BitChat has no document-sync
/// primitive; we bolt Yjs CRDT on top of the existing flood mesh so two
/// phones converge a shared document over BLE with no server.
///
/// Wire model:
///   - Each sync message is a BitchatPacket of a dedicated type carrying a
///     Yjs update (Uint8List) as its payload. We reuse the flood router so
///     updates propagate and dedupe like any other packet.
///   - Sender: on local doc change, produce an incremental
///     [encodeStateAsUpdate] and broadcast it.
///   - Receiver: apply the update to the local doc inside a transaction.
///
/// GOTCHA (proven in yjs_spike_test): yjs_dart's applyUpdate instantiates
/// shared types from the binary as a generic YMap. The receiving doc MUST
/// pre-declare the named type (getText/getMap/getArray) before applying
/// updates, or a later getText() throws a YMap/YText cast error. We declare
/// the chat types up front in [declareDefaultTypes].
class SyncDocTunnel {
  SyncDocTunnel({
    required this.router,
    required this.senderId,
    this.docName = 'sync',
  });

  final FloodRouter router;
  final Uint8List senderId;
  final String docName;

  final Doc doc = Doc();

  bool _typesReady = false;

  // On-device persistence: the Yjs doc is saved after every local/remote
  // mutation so chat history (including personal DMs) survives an app
  // restart, not just a BLE link drop.
  static const String _docFileName = 'resq_mesh_doc.yjs';
  bool _loaded = false;

  Future<String> get _docPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_docFileName';
  }

  /// Persist a full Yjs state snapshot to disk. Best-effort: a failure (e.g.
  /// headless test env with no real documents dir) degrades to in-memory only.
  // ponytail: writes the whole doc each time (simple, O(docSize)). Fine at
  // this app's scale; switch to incremental updates only if docs grow large.
  Future<void> _persist() async {
    try {
      final bytes = encodeStateAsUpdate(doc);
      final file = File(await _docPath);
      await file.writeAsBytes(bytes);
    } on Object catch (error) {
      debugPrint('[resq:crdt] persist failed: $error');
    }
  }

  /// Load a previously saved snapshot into this doc. Called once at start,
  /// before the router begins delivering packets.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(await _docPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          doc.transact((tr) => applyUpdate(doc, bytes), this);
          debugPrint('[resq:crdt] loaded persisted doc (${bytes.length} bytes)');
        }
      }
    } on Object catch (error) {
      // Any load failure (missing file, corrupt bytes, no platform dir) must
      // not block mesh startup. Degrades to an empty in-memory doc.
      debugPrint('[resq:crdt] load failed: $error');
    }
  }

  /// Append-only chat log. Pre-declared so incoming updates bind correctly.
  late final YArray<String> messages;

  /// Per-peer presence: senderId(hex) -> nickname.
  late final YMap presence;
  late final YArray<String> personalMessages;

  final StreamController<void> _changed = StreamController<void>.broadcast();
  final StreamController<String> _deliveredDoc =
      StreamController<String>.broadcast();

  /// Fires after ANY local or remote doc mutation (observe covers both), so
  /// the UI can rebuild the chat from the YArray.
  Stream<void> get changed => _changed.stream;

  /// Pre-declare the named types used by the chat on the local doc. Idempotent
  /// (the YArray/YMap are created lazily and observe is wired only once).
  Future<void> declareDefaultTypes() async {
    if (_typesReady) return;
    // legacy text channel (docName) MUST be declared before any update is
    // applied, or yjs_dart instantiates it as a YMap and getText() throws.
    doc.getText(docName);
    messages = doc.getArray('messages')!;
    presence = doc.getMap('presence')!;
    personalMessages = doc.getArray('personal_messages')!;
    // Persist on every local/remote mutation so a restart (or long BLE gap)
    // restores the full chat history. observe fires for both sides; the
    // actual file write is coalesced by _schedulePersist. The disk hydrate
    // itself happens once in load() before the router starts delivering.
    messages.observe((_, _) {
      _changed.add(null);
      _schedulePersist();
    });
    presence.observe((_, _) {
      _changed.add(null);
      _schedulePersist();
    });
    _typesReady = true;
  }

  Timer? _persistTimer;

  /// Coalesce rapid mutations (e.g. a burst of incoming fragments) into one
  /// file write per ~500ms instead of one write per update.
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persist());
    });
  }

  /// Convenience: get the synced text type (declare it if missing).
  YText get text {
    final t = doc.getText(docName)!;
    return t;
  }

  /// Begin: declare types, listen for incoming sync packets, start router.
  Future<void> start() async {
    declareDefaultTypes();
    await load();
    router.delivered.listen(_onDelivered);
    await router.start();
  }

  void _onDelivered(BitchatPacket packet) {
    if (packet.type != MessageType.syncDoc.value) return;
    // ensure the types exist on this doc before applying
    declareDefaultTypes();
    doc.transact((tr) {
      applyUpdate(doc, packet.payload);
    }, this);
    unawaited(_persist());
    _deliveredDoc.add(docName);
    _changed.add(null);
  }

  /// Append a message locally AND broadcast the update over the mesh.
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    declareDefaultTypes();
    final msg = ChatMessage(
      senderId: _hex(senderId),
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    doc.transact((tr) {
      messages.push([msg.toWire()]);
    }, this);
    _changed.add(null);
    await broadcastUpdate();
    unawaited(_persist());
  }

  /// Record/refresh a peer's nickname in the shared presence map.
  Future<void> setPresence(String senderHex, String nickname) async {
    declareDefaultTypes();
    doc.transact((tr) {
      presence.set(senderHex, nickname);
    }, this);
    _changed.add(null);
    await broadcastUpdate();
    unawaited(_persist());
  }

  /// Snapshot the chat log as ordered [ChatMessage]s for the UI.
  List<ChatMessage> get messageList {
    final out = <ChatMessage>[];
    for (var i = 0; i < messages.length; i++) {
      try {
        out.add(ChatMessage.fromWire(messages.get(i)));
      } on Object {
        // skip a malformed entry rather than crashing the UI
      }
    }
    return out;
  }

  Future<void> appendPersonalMessage({
    required String recipientId,
    required String text,
    required int timestamp,
  }) async {
    declareDefaultTypes();
    final sender = _hex(senderId);
    final message = PersonalCrdtMessage(
      id: '$sender:$timestamp',
      senderId: sender,
      recipientId: recipientId,
      text: text,
      timestamp: timestamp,
    );
    doc.transact((tr) => personalMessages.push([message.toWire()]), this);
    _changed.add(null);
    await broadcastUpdate();
    unawaited(_persist());
  }

  List<PersonalCrdtMessage> personalMessagesFor({
    required String me,
    required String peer,
  }) {
    declareDefaultTypes();
    final out = <PersonalCrdtMessage>[];
    for (var i = 0; i < personalMessages.length; i++) {
      try {
        final message = PersonalCrdtMessage.fromWire(personalMessages.get(i));
        if ((message.senderId == me && message.recipientId == peer) ||
            (message.senderId == peer && message.recipientId == me)) {
          out.add(message);
        }
      } on Object {}
    }
    return out;
  }

  /// Broadcast the current full-or-incremental state as a sync packet.
  Future<void> broadcastUpdate() async {
    declareDefaultTypes();
    final update = encodeStateAsUpdate(doc);
    final packet = BitchatPacket(
      type: MessageType.syncDoc.value,
      senderId: senderId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: update,
      ttl: 8, // survive a few hops across the mesh
    );
    await router.broadcast(packet);
  }

  Future<void> stop() async {
    _persistTimer?.cancel();
    await router.stop();
    await _changed.close();
    await _deliveredDoc.close();
  }

  static String _hex(Uint8List b) =>
      b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}
