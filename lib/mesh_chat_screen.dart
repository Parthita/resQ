import 'package:flutter/material.dart';

import 'core/bitchat/sync_doc_tunnel.dart';
import 'mesh_controller.dart';

/// A real, server-less mesh chat room backed by the Yjs CRDT tunnel.
///
/// Every message you send is appended to a shared YArray in the local Y.Doc,
/// then the Yjs update is broadcast over the BitChat flood mesh. Peers apply
/// the update to their own doc; the [SyncDocTunnel.changed] stream fires on
/// BOTH local and remote mutations, so this view rebuilds and shows the
/// message — proving the CRDT converged with no server.
class MeshChatScreen extends StatefulWidget {
  const MeshChatScreen({required this.controller, super.key});

  final MeshController controller;

  @override
  State<MeshChatScreen> createState() => _MeshChatScreenState();
}

class _MeshChatScreenState extends State<MeshChatScreen> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Listen for mesh state changes so the chat recovers if it was opened
    // before the mesh finished starting (peersStream is a broadcast stream
    // with no replay, so we also seed from currentPeers below).
    widget.controller.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// My sender id hex ('' if the mesh hasn't started yet — safe to call).
  String get _myHex => widget.controller.myIdHex;

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    // The mesh must be running for the tunnel to exist.
    if (!widget.controller.isStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn the mesh on first.')),
      );
      return;
    }
    _text.clear();
    widget.controller.tunnel.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final tunnel = widget.controller.tunnel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Chat'),
        centerTitle: false,
        actions: [
          StreamBuilder<List<MeshPeer>>(
            stream: widget.controller.peersStream,
            builder: (ctx, snap) {
              // seed from the current snapshot so a late-mounting screen still
              // shows peers that were discovered before it mounted
              final peers = snap.data ?? widget.controller.currentPeers;
              final connected = peers.where((p) => p.connected).length;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  avatar: const Icon(Icons.bluetooth_connected, size: 16),
                  label: Text(
                    connected == 0
                        ? 'no peers'
                        : '$connected connected',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<void>(
              stream: tunnel.changed,
              builder: (ctx, _) {
                final messages = tunnel.messageList;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nSay something — it syncs to every '
                      'connected resQ phone over BLE.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF68736D)),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (ctx, index) {
                    // newest at the bottom visually; reverse list so index 0
                    // (oldest) is top.
                    final msg = messages[messages.length - 1 - index];
                    final isMe = msg.senderId == _myHex;
                    final who = isMe
                        ? 'You'
                        : msg.senderId.substring(0, 6);
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFF2A5D4A)
                              : const Color(0xFFEDEDE5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              who,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMe
                                    ? Colors.white70
                                    : const Color(0xFF2A5D4A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              msg.text,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : const Color(0xFF16251F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Message the mesh…',
                        filled: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _send,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
