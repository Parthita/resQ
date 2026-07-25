import 'dart:async';

import 'package:flutter/material.dart';

import 'core/document_store.dart';
import 'core/local_document_repository.dart';
import 'core/local_llm_service.dart';
import 'core/model_store.dart';
import 'core/offline_contracts.dart';
import 'core/bitchat/ble_link.dart';
import 'mesh_controller.dart';
import 'personal_chat_screen.dart';

void main() {
  runApp(const ResQApp());
}

class ResQApp extends StatefulWidget {
  const ResQApp({this.loadDocuments = true, super.key});

  final bool loadDocuments;

  @override
  State<ResQApp> createState() => _ResQAppState();
}

class _ResQAppState extends State<ResQApp> {
  late final DocumentStore _documents;
  late final ModelStore _model;

  @override
  void initState() {
    super.initState();
    _documents = DocumentStore();
    _model = ModelStore();
    unawaited(_model.refresh());
    if (widget.loadDocuments) {
      unawaited(_documents.load());
    }
  }

  @override
  void dispose() {
    _documents.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2A5D4A);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFF8F7F1),
    );

    return MaterialApp(
      title: 'resQ',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF2F1EA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF16251F),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFAF9F4),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
        ),
      ),
      home: ResQShell(documents: _documents, model: _model),
    );
  }
}

class ResQShell extends StatefulWidget {
  const ResQShell({required this.documents, required this.model, super.key});

  final DocumentStore documents;
  final ModelStore model;

  @override
  State<ResQShell> createState() => _ResQShellState();
}

class _ResQShellState extends State<ResQShell> {
  int _selectedIndex = 0;

  void _openSensors() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SensorSheet(),
    );
  }

  void _openSos() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: Color(0xFFC33D30), size: 42),
        title: const Text('Send an SOS?'),
        content: const Text(
          'resQ will share your latest saved location and an emergency alert with trusted contacts and nearby groups.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC33D30),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('SOS queued for nearby delivery.'),
                ),
              );
            },
            child: const Text('Hold to send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        documents: widget.documents,
        onAssistant: () => setState(() => _selectedIndex = 1),
        onPeople: () => setState(() => _selectedIndex = 2),
        onLibrary: () => setState(() => _selectedIndex = 3),
        onSensors: _openSensors,
        onSos: _openSos,
      ),
      AssistantScreen(documents: widget.documents, model: widget.model),
      const PeopleScreen(),
      LibraryScreen(documents: widget.documents, model: widget.model),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.documents,
    required this.onAssistant,
    required this.onPeople,
    required this.onLibrary,
    required this.onSensors,
    required this.onSos,
    super.key,
  });

  final DocumentStore documents;
  final VoidCallback onAssistant;
  final VoidCallback onPeople;
  final VoidCallback onLibrary;
  final VoidCallback onSensors;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.terrain_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'resQ',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          Text(
                            'Offline when it matters',
                            style: TextStyle(color: Color(0xFF68736D)),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(label: 'OFFLINE', icon: Icons.cloud_off_rounded),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF17483B), Color(0xFF2A6A55)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your local network',
                        style: TextStyle(
                          color: Color(0xFFC4E3CC),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ready when the signal disappears.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          HeroMetric(
                            icon: Icons.bluetooth_connected_rounded,
                            label: '3 nearby',
                          ),
                          SizedBox(width: 12),
                          HeroMetric(
                            icon: Icons.location_on_outlined,
                            label: 'GPS saved',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Quick actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onSensors,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    QuickAction(
                      label: 'SOS',
                      subtitle: 'Alert people nearby',
                      icon: Icons.sos_rounded,
                      color: const Color(0xFFC33D30),
                      onTap: onSos,
                    ),
                    QuickAction(
                      label: 'Share location',
                      subtitle: 'Last fix: now',
                      icon: Icons.my_location_rounded,
                      color: const Color(0xFF1C6B83),
                      onTap: onPeople,
                    ),
                    QuickAction(
                      label: 'Ask resQ',
                      subtitle: 'Docs + local AI',
                      icon: Icons.auto_awesome_rounded,
                      color: const Color(0xFF75613B),
                      onTap: onAssistant,
                    ),
                    QuickAction(
                      label: 'Sensor kit',
                      subtitle: 'Compass and GPS',
                      icon: Icons.explore_rounded,
                      color: const Color(0xFF305B49),
                      onTap: onSensors,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'At a glance',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: documents,
                  builder: (context, _) {
                    final documentCount = documents.documents.length;
                    final documentTitle = documentCount == 0
                        ? 'No documents yet'
                        : '$documentCount offline ${documentCount == 1 ? 'document' : 'documents'}';
                    final documentDetail = documents.isLoading
                        ? 'Loading your library'
                        : documentCount == 0
                        ? 'Import a PDF to chat with it'
                        : 'Ready for document chat';

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            const InfoRow(
                              icon: Icons.group_outlined,
                              title: 'Weekend trek',
                              detail: '6 members, 3 nearby',
                              color: Color(0xFF2A5D4A),
                            ),
                            const Divider(height: 28),
                            InfoRow(
                              icon: Icons.description_outlined,
                              title: documentTitle,
                              detail: documentDetail,
                              color: const Color(0xFF75613B),
                            ),
                            const Divider(height: 28),
                            const InfoRow(
                              icon: Icons.battery_5_bar_rounded,
                              title: 'Battery 74%',
                              detail: 'Battery saver is off',
                              color: Color(0xFF1C6B83),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onLibrary,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Add a guide, note, or observation'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    required this.documents,
    required this.model,
    super.key,
  });

  final DocumentStore documents;
  final ModelStore model;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      content:
          'I can answer from your local guides and documents. Nothing in this conversation leaves this phone.',
      isAssistant: true,
    ),
  ];
  String? _selectedDocumentId;
  bool _isGenerating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LocalDocument? get _selectedDocument {
    final documentId = _selectedDocumentId;
    if (documentId == null) return null;

    for (final document in widget.documents.documents) {
      if (document.id == documentId) return document;
    }
    return null;
  }

  Future<void> _importDocument() async {
    try {
      final document = await widget.documents.pickAndImportPdf();
      if (!mounted || document == null) return;
      setState(() => _selectedDocumentId = document.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_indexMessage(document))));
    } on DocumentStorageException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _selectDocument() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              'Choose assistant context',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('General offline assistant'),
              trailing: _selectedDocument == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () {
                setState(() => _selectedDocumentId = null);
                Navigator.pop(sheetContext);
              },
            ),
            for (final document in widget.documents.documents)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: Text(document.name),
                subtitle: Text(
                  '${_formatBytes(document.byteCount)} | ${_documentStatus(document)}',
                ),
                trailing: _selectedDocument?.id == document.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  setState(() => _selectedDocumentId = document.id);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final document = _selectedDocument;
    setState(() {
      _messages.add(_ChatMessage(content: text, isAssistant: false));
      _controller.clear();
      _isGenerating = true;
    });

    if (!widget.model.isReady) {
      setState(() {
        _isGenerating = false;
        _messages.add(
          const _ChatMessage(
            content:
                'Import a GGUF model from Library before asking the offline assistant.',
            isAssistant: true,
          ),
        );
      });
      return;
    }

    List<DocumentSearchHit> hits = const [];
    if (document != null) {
      if (document.indexState != DocumentIndexState.ready) {
        setState(() {
          _isGenerating = false;
          _messages.add(
            _ChatMessage(content: _indexMessage(document), isAssistant: true),
          );
        });
        return;
      }
      hits = await widget.documents.search(document, text);
      if (!mounted) return;
    }

    if (document != null && hits.isEmpty) {
      setState(() {
        _isGenerating = false;
        _messages.add(
          _ChatMessage(
            content:
                'I could not find relevant text in ${document.name}. Try a more specific question or switch to general assistant.',
            isAssistant: true,
          ),
        );
      });
      return;
    }

    setState(() {
      _messages.add(const _ChatMessage(content: '', isAssistant: true));
    });

    try {
      await for (final token in widget.model.generate(
        prompt: document == null
            ? _generalPrompt(text)
            : _groundedPrompt(question: text, hits: hits),
      )) {
        if (!mounted) return;
        setState(() {
          final last = _messages.removeLast();
          _messages.add(last.copyWith(content: '${last.content}$token'));
        });
      }
    } on LocalModelException catch (error) {
      if (!mounted) return;
      setState(() {
        final last = _messages.removeLast();
        _messages.add(
          last.copyWith(content: 'Local model error: ${error.message}'),
        );
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.documents, widget.model]),
      builder: (context, _) {
        final selectedDocument = _selectedDocument;
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assistant',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Private. Local. Source-aware.',
                            style: TextStyle(color: Color(0xFF68736D)),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _importDocument,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Add a document',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _selectDocument,
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectedDocument != null
                          ? const Color(0xFFE2F0E4)
                          : const Color(0xFFE8E7E0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedDocument != null
                              ? Icons.description_rounded
                              : Icons.auto_awesome_rounded,
                          color: const Color(0xFF2A5D4A),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedDocument != null
                                ? 'Using: ${selectedDocument.name}'
                                : 'General offline assistant',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  itemCount: _messages.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          PromptChip(
                            label: 'Summarize this guide',
                            onTap: () =>
                                _controller.text = 'Summarize this guide',
                          ),
                          PromptChip(
                            label: 'Find water sources',
                            onTap: () =>
                                _controller.text = 'Find water sources',
                          ),
                          PromptChip(
                            label: 'Explain simply',
                            onTap: () => _controller.text =
                                'Explain the key safety instructions simply',
                          ),
                        ],
                      );
                    }
                    final message = _messages[index - 1];
                    return Align(
                      alignment: message.isAssistant
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 340),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: message.isAssistant
                              ? Colors.white
                              : const Color(0xFF204F40),
                          borderRadius: BorderRadius.circular(20).copyWith(
                            bottomLeft: message.isAssistant
                                ? const Radius.circular(4)
                                : null,
                            bottomRight: message.isAssistant
                                ? null
                                : const Radius.circular(4),
                          ),
                        ),
                        child: Text(
                          message.content,
                          style: TextStyle(
                            color: message.isAssistant
                                ? const Color(0xFF1B2923)
                                : Colors.white,
                            height: 1.35,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(color: Color(0xFFF2F1EA)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: 'Ask anything',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isGenerating ? null : _send,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final MeshController _mesh = MeshController();
  MeshState _state = MeshState.stopped;
  String _statusText = 'Mesh is off';
  bool _permDenied = false;
  bool _locationDenied = false;
  bool _btOff = false;
  List<MeshPeer> _peerList = const [];

  @override
  void initState() {
    super.initState();
    _mesh.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        _statusText = switch (s) {
          MeshState.stopped => 'Mesh is off',
          MeshState.starting => 'Starting Bluetooth mesh…',
          MeshState.running => 'Mesh active — discovering peers',
          MeshState.stopping => 'Stopping mesh…',
        };
      });
    });
    _mesh.peersStream.listen((peers) {
      if (mounted) setState(() => _peerList = peers);
    });
  }

  Future<void> _toggleMesh() async {
    if (_state == MeshState.running || _state == MeshState.starting) {
      await _mesh.stop();
      return;
    }
    // 1) runtime permission + adapter check (the half the manifest alone can't do)
    final result = await _mesh.requestPermissions();
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _permDenied = result.reason == 'permissions';
        _locationDenied = result.reason == 'location';
        _permDenied = _permDenied || _locationDenied;
        _btOff = result.reason == 'bluetooth_off';
      });
      return;
    }
    setState(() {
      _permDenied = false;
      _locationDenied = false;
      _btOff = false;
    });
    // 2) start BLE + flood router + CRDT tunnel
    try {
      await _mesh.start();
    } on BluetoothOffException {
      if (!mounted) return;
      setState(() => _btOff = true);
      return;
    }
  }

  Future<void> _handleContact(PersonalContact contact) async {
    switch (contact.status) {
      case ConnectionStatus.available:
      case ConnectionStatus.rejected:
      case ConnectionStatus.disconnected:
        await _mesh.requestConnection(contact);
        return;
      case ConnectionStatus.incomingPending:
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${contact.name} wants to connect'),
            content: const Text(
              'Accept to open a private nearby conversation.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Accept'),
              ),
            ],
          ),
        );
        if (accepted != null) await _mesh.respondToRequest(contact, accepted);
        return;
      case ConnectionStatus.connected:
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                PersonalChatScreen(controller: _mesh, contact: contact),
          ),
        );
        return;
      case ConnectionStatus.outgoingPending:
        break;
    }
  }

  @override
  void dispose() {
    _mesh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOn = _state == MeshState.running;
    final statusLabel = isOn ? 'VISIBLE' : 'OFFLINE';
    final statusIcon = isOn
        ? Icons.visibility_outlined
        : Icons.visibility_off_outlined;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'People',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Nearby, trusted, and in your groups',
                      style: TextStyle(color: Color(0xFF68736D)),
                    ),
                  ],
                ),
              ),
              StatusPill(label: statusLabel, icon: statusIcon),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            color: isOn ? const Color(0xFF17483B) : const Color(0xFF3A3A3A),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF8BC49A),
                    child: Icon(
                      Icons.wifi_tethering_rounded,
                      color: Color(0xFF153F33),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _btOff
                              ? 'Bluetooth is off. Turn it on, then tap play again.'
                              : _locationDenied
                              ? 'Location permission is required to scan on Android 11 and older.'
                              : _permDenied
                              ? 'Bluetooth permission denied. Enable it in Settings.'
                              : 'Uses BLE to find nearby resQ phones and sync offline.',
                          style: const TextStyle(
                            color: Color(0xFFC4E3CC),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleMesh,
                    icon: Icon(
                      isOn
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 28),
          SectionTitle(
            title: 'Nearby people',
            action: 'Scan',
            onAction: () => _mesh.refreshPresence(),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<PersonalContact>>(
            stream: _mesh.contactsStream,
            initialData: _mesh.contacts,
            builder: (context, snapshot) {
              final contacts = snapshot.data ?? const [];
              // Android can surface several rotating BLE addresses for the
              // same phone (scan address, inbound central, outbound GATT).
              // A verified BitChat sender id is the stable person identity,
              // so raw transport aliases are only shown before verification.
              final rawPeers = contacts.isEmpty
                  ? _peerList
                  : const <MeshPeer>[];
              if (contacts.isNotEmpty || rawPeers.isNotEmpty) {
                return Column(
                  children: [
                    ...rawPeers.map(
                      (peer) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: NearbyDevice(
                          name: peer.nickname,
                          detail: peer.connected
                              ? 'Connected • verifying identity…'
                              : 'resQ device detected • connecting…',
                          onConnect: () => _mesh.refreshPresence(),
                          actionLabel: 'Refresh',
                        ),
                      ),
                    ),
                    ...contacts.map(
                      (contact) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: NearbyDevice(
                          name: contact.name,
                          detail: _contactDetail(contact.status),
                          onConnect: () => _handleContact(contact),
                          actionLabel:
                              contact.status == ConnectionStatus.connected
                              ? 'Chat'
                              : 'Connect',
                        ),
                      ),
                    ),
                  ],
                );
              }
              return _nearbyEmpty();
            },
          ),
          const SizedBox(height: 28),
          const Text(
            'Connection requests must be accepted before private chat is available. A Bluetooth loss immediately marks the conversation disconnected.',
            style: TextStyle(color: Color(0xFF68736D), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _nearbyEmpty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        _state == MeshState.running
            ? 'Scanning… no resQ people in range yet.'
            : 'Turn Bluetooth discovery on to find people nearby.',
        style: const TextStyle(color: Color(0xFF68736D), height: 1.3),
      ),
    );
  }

  String _contactDetail(ConnectionStatus status) => switch (status) {
    ConnectionStatus.available => 'Nearby • tap to request connection',
    ConnectionStatus.outgoingPending => 'Request sent • waiting for acceptance',
    ConnectionStatus.incomingPending => 'Connection request waiting',
    ConnectionStatus.connected => 'Connected • private chat ready',
    ConnectionStatus.rejected => 'Request declined • tap to request again',
    ConnectionStatus.disconnected => 'Bluetooth disconnected',
  };
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    required this.documents,
    required this.model,
    super.key,
  });

  final DocumentStore documents;
  final ModelStore model;

  Future<void> _importDocument(BuildContext context) async {
    try {
      final document = await documents.pickAndImportPdf();
      if (context.mounted && document != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${document.name} saved for offline use.')),
        );
      }
    } on DocumentStorageException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _importModel(BuildContext context) async {
    try {
      await model.importAndLoad();
      if (!context.mounted) return;
      final status = model.status;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isLoaded
                ? 'Local model loaded. Assistant answers now run on this phone.'
                : 'Model import was cancelled.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load local model: $error')),
        );
      }
    }
  }

  Future<void> _deleteDocument(
    BuildContext context,
    LocalDocument document,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this document?'),
        content: Text(
          '${document.name} will be deleted from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    await documents.delete(document);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${document.name} removed from this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([documents, model]),
      builder: (context, _) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Library',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Everything stays on this device',
                        style: TextStyle(color: Color(0xFF68736D)),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => _importDocument(context),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Import a PDF',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE8E4D3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: Color(0xFF75613B)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Imported PDFs are copied into private app storage.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5D4D2E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SectionTitle(
              title: 'Documents',
              action: documents.isLoading ? null : 'Import PDF',
              onAction: () => _importDocument(context),
            ),
            const SizedBox(height: 10),
            if (documents.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (documents.documents.isEmpty)
              EmptyDocumentState(onImport: () => _importDocument(context))
            else
              for (final document in documents.documents) ...[
                LibraryItem(
                  icon: Icons.picture_as_pdf_rounded,
                  title: document.name,
                  subtitle:
                      'PDF | ${_formatBytes(document.byteCount)} | ${_documentStatus(document)}',
                  color: const Color(0xFFC33D30),
                  onDelete: () => _deleteDocument(context, document),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 28),
            const SectionTitle(title: 'Local model'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F0E4),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.memory_rounded,
                        color: Color(0xFF2A5D4A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.isReady
                                ? 'GGUF model loaded'
                                : 'No GGUF model loaded',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            model.isBusy
                                ? 'Copying and preparing the model'
                                : model.status.hasModel
                                ? '${_formatBytes(model.status.sizeBytes)} stored privately'
                                : 'Import a small quantized GGUF model',
                            style: const TextStyle(
                              color: Color(0xFF68736D),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: model.isBusy
                          ? null
                          : () => _importModel(context),
                      child: Text(model.status.hasModel ? 'Replace' : 'Import'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Observations'),
            const SizedBox(height: 10),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_camera_back_outlined,
                      color: Color(0xFF75613B),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Photos, OCR, and saved observations will appear here.',
                        style: TextStyle(color: Color(0xFF68736D)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SensorSheet extends StatelessWidget {
  const SensorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F7F1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFB9BBB5),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Sensor kit',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Live information from your phone',
              style: TextStyle(color: Color(0xFF68736D)),
            ),
            const SizedBox(height: 22),
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFF17483B),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.navigation_rounded,
                    color: Color(0xFFB9E4C3),
                    size: 44,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'NW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '315 degrees',
                    style: TextStyle(color: Color(0xFFC4E3CC)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.55,
              children: const [
                SensorMetric(
                  icon: Icons.my_location_rounded,
                  label: 'GPS accuracy',
                  value: '+/- 8 m',
                ),
                SensorMetric(
                  icon: Icons.landscape_rounded,
                  label: 'Elevation',
                  value: '1,240 m',
                ),
                SensorMetric(
                  icon: Icons.speed_rounded,
                  label: 'Speed',
                  value: '0.0 km/h',
                ),
                SensorMetric(
                  icon: Icons.air_rounded,
                  label: 'Pressure',
                  value: '1008 hPa',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: const Icon(
                  Icons.flashlight_on_rounded,
                  color: Color(0xFFC58B26),
                ),
                title: const Text(
                  'Flashlight',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Quick access when visibility is low'),
                trailing: Switch(value: false, onChanged: (_) {}),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.icon, super.key});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE2F0E4),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF2A5D4A)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2A5D4A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class HeroMetric extends StatelessWidget {
  const HeroMetric({required this.icon, required this.label, super.key});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFC4E3CC)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Ink(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 23),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    super.key,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              detail,
              style: const TextStyle(color: Color(0xFF68736D), fontSize: 12),
            ),
          ],
        ),
      ),
      const Icon(Icons.chevron_right_rounded, color: Color(0xFF89918C)),
    ],
  );
}

class PromptChip extends StatelessWidget {
  const PromptChip({required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(label),
    onPressed: onTap,
    side: BorderSide.none,
    backgroundColor: const Color(0xFFE5E5DE),
  );
}

class NearbyDevice extends StatelessWidget {
  const NearbyDevice({
    required this.name,
    required this.detail,
    required this.onConnect,
    this.actionLabel = 'Connect',
    super.key,
  });
  final String name;
  final String detail;
  final VoidCallback onConnect;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFE2F0E4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.phone_android_rounded,
          color: Color(0xFF2A5D4A),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(detail),
      trailing: TextButton(onPressed: onConnect, child: Text(actionLabel)),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      if (action != null)
        TextButton(onPressed: onAction ?? () {}, child: Text(action!)),
    ],
  );
}

class LibraryItem extends StatelessWidget {
  const LibraryItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onDelete,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: onDelete == null
          ? const Icon(Icons.more_horiz_rounded)
          : IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Remove document',
            ),
    ),
  );
}

class EmptyDocumentState extends StatelessWidget {
  const EmptyDocumentState({required this.onImport, super.key});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE2F0E4),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.picture_as_pdf_outlined,
              color: Color(0xFF2A5D4A),
              size: 30,
            ),
            const SizedBox(height: 12),
            const Text(
              'Bring your own local knowledge.',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Import a PDF. resQ copies it into private app storage and keeps it available offline.',
              style: TextStyle(color: Color(0xFF466253), height: 1.35),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class SensorMetric extends StatelessWidget {
  const SensorMetric({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF2A5D4A), size: 19),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF68736D), fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _ChatMessage {
  const _ChatMessage({required this.content, required this.isAssistant});
  final String content;
  final bool isAssistant;

  _ChatMessage copyWith({String? content}) {
    return _ChatMessage(
      content: content ?? this.content,
      isAssistant: isAssistant,
    );
  }
}

String _documentStatus(LocalDocument document) {
  return switch (document.indexState) {
    DocumentIndexState.pending => 'Waiting to index',
    DocumentIndexState.indexing => 'Indexing local text',
    DocumentIndexState.ready => 'Ready for search',
    DocumentIndexState.needsOcr => 'OCR needed',
    DocumentIndexState.failed => 'Could not read PDF',
  };
}

String _indexMessage(LocalDocument document) {
  return switch (document.indexState) {
    DocumentIndexState.pending || DocumentIndexState.indexing =>
      '${document.name} is indexing its local text. Try again in a moment.',
    DocumentIndexState.ready =>
      '${document.name} is ready for offline document search.',
    DocumentIndexState.needsOcr =>
      '${document.name} has no selectable text. Offline OCR is needed before resQ can search it.',
    DocumentIndexState.failed =>
      'resQ could not read ${document.name}. The PDF may be protected or malformed.',
  };
}

String _generalPrompt(String question) =>
    '''
Answer the following question as a helpful offline assistant. Be concise and clear.

Question: $question
''';

String _groundedPrompt({
  required String question,
  required List<DocumentSearchHit> hits,
}) {
  final context = hits
      .map((hit) => '[Page ${hit.section.pageNumber}]\n${hit.section.text}')
      .join('\n\n');
  return '''
Retrieved document context:
$context

Question: $question

Answer only from the retrieved context. Cite supporting pages in square brackets, such as [Page 4]. If the context is insufficient, say so clearly.
''';
}

String _formatBytes(int byteCount) {
  const bytesInKilobyte = 1024;
  const bytesInMegabyte = bytesInKilobyte * 1024;

  if (byteCount >= bytesInMegabyte) {
    return '${(byteCount / bytesInMegabyte).toStringAsFixed(1)} MB';
  }
  if (byteCount >= bytesInKilobyte) {
    return '${(byteCount / bytesInKilobyte).toStringAsFixed(1)} KB';
  }
  return '$byteCount B';
}
