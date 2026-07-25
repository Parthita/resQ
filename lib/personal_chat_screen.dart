import 'dart:async';

import 'package:flutter/material.dart';

import 'mesh_controller.dart';

/// A one-to-one conversation. It is only reachable after both people have
/// completed the invitation flow in [PeopleScreen].
class PersonalChatScreen extends StatefulWidget {
  const PersonalChatScreen({
    required this.controller,
    required this.contact,
    super.key,
  });

  final MeshController controller;
  final PersonalContact contact;

  @override
  State<PersonalChatScreen> createState() => _PersonalChatScreenState();
}

class _PersonalChatScreenState extends State<PersonalChatScreen> {
  final _text = TextEditingController();
  StreamSubscription<PersonalMessage>? _messageSubscription;
  StreamSubscription<List<PersonalContact>>? _contactSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = widget.controller.messagesStream.listen((message) {
      if (message.contactId == widget.contact.id && mounted) setState(() {});
    });
    _contactSubscription = widget.controller.contactsStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _contactSubscription?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await widget.controller.sendPersonalMessage(
      widget.contact,
      _text.text,
    );
    if (!mounted) return;
    if (sent) {
      _text.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This person is no longer connected.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.contact.status == ConnectionStatus.connected;
    final messages = widget.controller.messagesFor(widget.contact.id);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contact.name),
            Text(
              connected ? 'Connected nearby' : 'Bluetooth disconnected',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Private conversation — only this connection appears here.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Align(
                        alignment: message.isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: message.isMine
                                ? const Color(0xFF2A5D4A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.isMine ? Colors.white : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: connected,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message privately',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: connected ? _send : null,
                    icon: const Icon(Icons.send),
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
