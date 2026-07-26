import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mesh_controller.dart';

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
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _messageVersion = ValueNotifier<int>(0);

  StreamSubscription<PersonalMessage>? _messageSubscription;
  StreamSubscription<List<PersonalContact>>? _contactSubscription;

  bool _canSend = false;
  bool _hasNewMessages = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    _updateCanSend();

    _messageVersion.value = widget.controller.messagesCount(widget.contact.id);
    _messageSubscription = widget.controller.messagesStream.listen((message) {
      if (message.contactId != widget.contact.id) return;
      if (!mounted) return;
      final prevCount = _messageVersion.value;
      final newCount = widget.controller.messagesCount(widget.contact.id);
      _messageVersion.value = newCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _afterMessageArrived(prevCount < newCount);
      });
    });
    _contactSubscription = widget.controller.contactsStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom(animated: false);
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _contactSubscription?.cancel();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageVersion.dispose();
    super.dispose();
  }

  void _onTextChanged() => _updateCanSend();

  void _updateCanSend() {
    final can = _text.text.trim().isNotEmpty;
    if (can != _canSend) {
      setState(() => _canSend = can);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return true;
    return max - _scrollController.position.pixels <= 120;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isNearBottom() && _hasNewMessages) {
      setState(() => _hasNewMessages = false);
    }
  }

  void _afterMessageArrived(bool isNewMessage) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    if (_isNearBottom()) {
      _hasNewMessages = false;
      _scrollToBottom(animated: true);
    } else if (isNewMessage) {
      setState(() => _hasNewMessages = true);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    if (animated) {
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(max);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    _focusNode.requestFocus();

    final sent = await widget.controller.sendPersonalMessage(
      widget.contact,
      text,
    );

    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This person is no longer connected.')),
      );
      return;
    }
    if (_isNearBottom()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animated: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.contact.status == ConnectionStatus.connected;
    return Scaffold(
      appBar: _AppBar(contact: widget.contact, connected: connected),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.unfocus(),
              child: ValueListenableBuilder<int>(
                valueListenable: _messageVersion,
                builder: (context, version, _) {
                  final messages = widget.controller.messagesFor(
                    widget.contact.id,
                  );
                  if (messages.isEmpty) {
                    return const _EmptyState();
                  }
                  return Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isLast = index == messages.length - 1;
                          return _MessageBubble(
                            key: ValueKey(
                              'msg_${message.timestamp.millisecondsSinceEpoch}_${message.text.length}_${message.hashCode}',
                            ),
                            message: message,
                            isLast: isLast,
                          );
                        },
                      ),
                      if (_hasNewMessages)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: _NewMessagesIndicator(
                            onTap: _scrollToBottomOnTap,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          _InputRow(
            connected: connected,
            canSend: _canSend,
            textController: _text,
            focusNode: _focusNode,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  void _scrollToBottomOnTap() {
    setState(() => _hasNewMessages = false);
    _scrollToBottom(animated: true);
    _focusNode.requestFocus();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Start the conversation.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewMessagesIndicator extends StatelessWidget {
  const _NewMessagesIndicator({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              'New messages',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar({required this.contact, required this.connected});

  final PersonalContact contact;
  final bool connected;

  @override
  Size get preferredSize => AppBar().preferredSize;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(contact.name),
          Text(
            connected ? 'Connected nearby' : 'Bluetooth disconnected',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.connected,
    required this.canSend,
    required this.textController,
    required this.focusNode,
    required this.onSend,
  });

  final bool connected;
  final bool canSend;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  focusNode: focusNode,
                  enabled: connected,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Message privately',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: IconButton.filled(
                  onPressed: connected && canSend ? onSend : null,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.isLast,
  });

  final PersonalMessage message;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isLocation = message.data?['type'] == 'location';
    final isSos = message.data?['type'] == 'sos';
    final isMine = message.isMine;

    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = isSos
        ? colorScheme.error
        : isMine
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final fgColor = isSos
        ? colorScheme.onError
        : isMine
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final tsColor = isSos
        ? colorScheme.onError.withValues(alpha: 0.7)
        : isMine
        ? colorScheme.onPrimary.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.5);
    final fontWeight = (isLocation || isSos) ? FontWeight.w700 : null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 6 : 3),
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: _BubbleShape(
              bgColor: bgColor,
              fgColor: fgColor,
              tsColor: tsColor,
              fontWeight: fontWeight,
              message: message,
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleShape extends StatelessWidget {
  const _BubbleShape({
    required this.bgColor,
    required this.fgColor,
    required this.tsColor,
    required this.fontWeight,
    required this.message,
  });

  final Color bgColor;
  final Color fgColor;
  final Color tsColor;
  final FontWeight? fontWeight;
  final PersonalMessage message;

  @override
  Widget build(BuildContext context) {
    final isLocation = message.data?['type'] == 'location';
    final isSos = message.data?['type'] == 'sos';
    final isMine = message.isMine;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: (isLocation || isSos)
            ? () => _showMessageDetail(context, message)
            : null,
        onLongPress: () => _showContextMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: fgColor,
                  fontWeight: fontWeight,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(fontSize: 11, color: tsColor),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_rounded, size: 14, color: tsColor),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24 && now.day == dt.day && now.month == dt.month) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} $h:$m';
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessageDetail(BuildContext context, PersonalMessage message) {
  final data = message.data;
  if (data == null) return;
  final type = data['type'] as String?;
  final lat = data['latitude'] as double?;
  final lng = data['longitude'] as double?;
  final acc = data['accuracy'] as double?;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        type == 'sos' ? Icons.sos_rounded : Icons.location_on_rounded,
        color: type == 'sos'
            ? const Color(0xFFC33D30)
            : const Color(0xFF1C6B83),
        size: 38,
      ),
      title: Text(type == 'sos' ? 'Emergency SOS' : 'Shared Location'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lat != null) Text('Latitude: ${lat.toStringAsFixed(6)}'),
          if (lng != null) Text('Longitude: ${lng.toStringAsFixed(6)}'),
          if (acc != null && acc > 0)
            Text('Accuracy: +/- ${acc.toStringAsFixed(1)}m'),
          Text('Time: ${message.timestamp}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
