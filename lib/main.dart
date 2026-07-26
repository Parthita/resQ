import 'dart:async';

import 'package:flutter/material.dart';

import 'core/battery_service.dart';
import 'core/device_sensor_service.dart';
import 'core/local_llm_service.dart';
import 'core/location_service.dart';
import 'core/model_store.dart';
import 'core/bitchat/ble_link.dart';
import 'core/nickname_store.dart';
import 'mesh_controller.dart';
import 'personal_chat_screen.dart';

void main() {
  runApp(const ResQApp());
}

class ResQApp extends StatefulWidget {
  const ResQApp({super.key});

  @override
  State<ResQApp> createState() => _ResQAppState();
}

class _ResQAppState extends State<ResQApp> {
  late final ModelStore _model;

  @override
  void initState() {
    super.initState();
    _model = ModelStore();
    unawaited(_model.refresh());
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
      home: ResQShell(model: _model),
    );
  }
}

class ResQShell extends StatefulWidget {
  const ResQShell({required this.model, super.key});

  final ModelStore model;

  @override
  State<ResQShell> createState() => _ResQShellState();
}

class _ResQShellState extends State<ResQShell> {
  int _selectedIndex = 0;
  late final MeshController _mesh;
  late final BatteryService _battery;
  late final LocationService _location;
  late final DeviceSensorService _deviceSensors;
  StreamSubscription<IncomingSos>? _sosSubscription;

  @override
  void initState() {
    super.initState();
    _mesh = MeshController();
    // Load persisted nickname so the mesh broadcasts the user's chosen name
    // instead of the default 'resQ'. Non-blocking; if unset, the controller
    // keeps its 'resQ' fallback and behavior is unchanged.
    unawaited(
      NicknameStore.load().then((saved) {
        if (saved != null && saved.isNotEmpty) _mesh.nickname = saved;
      }),
    );
    _battery = BatteryService();
    _location = LocationService();
    _deviceSensors = DeviceSensorService();
    unawaited(_battery.init());
    unawaited(_location.init());
    unawaited(_deviceSensors.init());
    _sosSubscription = _mesh.sosStream.listen((sos) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.sos_rounded, color: Color(0xFFC33D30), size: 42),
          title: const Text('Emergency SOS received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('From: ${sos.senderName}'),
              const SizedBox(height: 4),
              Text(
                'Time: ${DateTime.fromMillisecondsSinceEpoch(sos.timestamp)}',
              ),
              if (sos.latitude != null && sos.longitude != null) ...[
                const SizedBox(height: 8),
                Text('Latitude: ${sos.latitude!.toStringAsFixed(6)}'),
                Text('Longitude: ${sos.longitude!.toStringAsFixed(6)}'),
              ],
              if (sos.accuracy != null) ...[
                const SizedBox(height: 4),
                Text('Accuracy: +/- ${sos.accuracy!.toStringAsFixed(1)}m'),
              ],
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
    });
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    _mesh.dispose();
    _battery.dispose();
    _location.dispose();
    _deviceSensors.dispose();
    super.dispose();
  }

  void _setTab(int index) {
    setState(() => _selectedIndex = index);
  }

  void _openSensors() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SensorSheet(location: _location, deviceSensors: _deviceSensors),
    );
  }

  void _openSos() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: Color(0xFFC33D30), size: 42),
        title: const Text('Send an SOS?'),
        content: const Text(
          'resQ will share your latest saved location and an emergency alert with trusted contacts and nearby groups.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC33D30),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final pos = _location.position;
              final sent = await _mesh.sendSos(
                latitude: pos?.latitude,
                longitude: pos?.longitude,
                accuracy: pos?.accuracy,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    sent
                        ? 'SOS sent to nearby devices'
                        : 'Start the mesh first in the People tab before sending an SOS.',
                  ),
                ),
              );
            },
            child: const Text('Hold to send'),
          ),
        ],
      ),
    );
  }

  void _openShareLocation() {
    if (_mesh.state != MeshState.running) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mesh not active'),
          content: const Text('Start the mesh in the People tab first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final allPeers = _mesh.currentPeers;
    final connectedPeers = allPeers.where((p) => p.connected).toList();
    debugPrint('[share-location] currentPeers=${allPeers.length} connected=${connectedPeers.length}');
    for (final p in allPeers) {
      debugPrint(
        '[share-location] peer id=${p.id} name=${p.nickname} '
        'connected=${p.connected} identityHint=${p.identityHint}',
      );
    }

    // Build the set of reachable peers using the same source the chat screen
    // uses: PersonalContact objects (always carry a valid hex sender ID).
    //
    // Strategy (three sources, each stricter than the last):
    //   1. Direct match — BLE peers whose identityHint is already bound.
    //   2. Connected contacts — contacts with an established chat link.
    //   3. Fallback — any verified contact when BLE is connected but
    //      _bindRawPeerToIdentity failed to set identityHint on the inbound
    //      BLE peer (e.g. duplicate BLE UUIDs from connect + subscribe).
    final reachable = <String, String>{}; // senderId -> displayName
    int skippedNoIdentity = 0;

    // Source 1: direct identityHint match
    for (final peer in connectedPeers) {
      if (peer.identityHint != null) {
        reachable[peer.identityHint!] = peer.nickname;
        debugPrint('[share-location] source=identityHint id=${peer.identityHint} name=${peer.nickname}');
      } else {
        skippedNoIdentity++;
        debugPrint('[share-location] skip (no identityHint) id=${peer.id}');
      }
    }

    // Source 2: contacts with an active chat link
    for (final contact in _mesh.contacts) {
      if (contact.linkUp || contact.status == ConnectionStatus.connected) {
        reachable[contact.id] = contact.name;
        debugPrint('[share-location] source=contact id=${contact.id} name=${contact.name} status=${contact.status} linkUp=${contact.linkUp}');
      }
    }

    // Source 3: verified contacts when BLE connected but identityHint is missing
    if (connectedPeers.isNotEmpty && skippedNoIdentity > 0) {
      for (final contact in _mesh.contacts) {
        if (contact.signingKey != null && !reachable.containsKey(contact.id)) {
          reachable[contact.id] = contact.name;
          debugPrint('[share-location] source=fallback id=${contact.id} name=${contact.name}');
        }
      }
    }

    debugPrint('[share-location] reachable=${reachable.length}');

    if (reachable.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No connected devices'),
          content: const Text(
            "You're currently not connected to any nearby ResQ users.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share location with…'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reachable.length,
            itemBuilder: (context, index) {
              final entry = reachable.entries.elementAt(index);
              final displayName = entry.value;
              final shortId = entry.key.length > 8
                  ? entry.key.substring(0, 8)
                  : entry.key;
              return ListTile(
                leading: const Icon(Icons.phone_android_rounded),
                title: Text(displayName),
                subtitle: Text(
                  'ID: $shortId • Connected',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final pos = _location.position;
                  if (pos == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No GPS position available'),
                      ),
                    );
                    return;
                  }
                  final sent = await _mesh.sendLocation(
                    recipientId: entry.key,
                    latitude: pos.latitude,
                    longitude: pos.longitude,
                    accuracy: pos.accuracy,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        sent
                            ? 'Location shared with $displayName'
                            : 'Failed to share location',
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        mesh: _mesh,
        battery: _battery,
        location: _location,
        onAssistant: () => setState(() => _selectedIndex = 1),
        onShareLocation: _openShareLocation,
        onLibrary: () => setState(() => _selectedIndex = 3),
        onSensors: _openSensors,
        onSos: _openSos,
      ),
      AssistantScreen(model: widget.model),
      PeopleScreen(mesh: _mesh),
      LibraryScreen(model: widget.model),
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.mesh,
    required this.battery,
    required this.location,
    required this.onAssistant,
    required this.onShareLocation,
    required this.onLibrary,
    required this.onSensors,
    required this.onSos,
    super.key,
  });

  final MeshController mesh;
  final BatteryService battery;
  final LocationService location;
  final VoidCallback onAssistant;
  final VoidCallback onShareLocation;
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
                StreamBuilder<MeshState>(
                  stream: mesh.stateStream,
                  initialData: mesh.state,
                  builder: (context, snapshot) {
                    final state = snapshot.data ?? MeshState.stopped;
                    final isOnline = state == MeshState.running;
                    return Row(
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
                        StatusPill(
                          label: isOnline ? 'ONLINE' : 'OFFLINE',
                          icon: isOnline
                              ? Icons.wifi_rounded
                              : Icons.cloud_off_rounded,
                        ),
                      ],
                    );
                  },
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
                      Row(
                        children: [
                          StreamBuilder<List<MeshPeer>>(
                            stream: mesh.peersStream,
                            initialData: mesh.currentPeers,
                            builder: (context, snapshot) {
                              final peers = snapshot.data ?? [];
                              final connected = peers
                                  .where((p) => p.connected)
                                  .length;
                              return HeroMetric(
                                icon: Icons.bluetooth_connected_rounded,
                                label: connected > 0
                                    ? '$connected nearby'
                                    : 'No peers',
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          ListenableBuilder(
                            listenable: location,
                            builder: (context, _) {
                              final status = location.status;
                              String label;
                              if (status == GpsStatus.available &&
                                  location.lastFix != null) {
                                final diff = DateTime.now()
                                    .difference(location.lastFix!)
                                    .inMinutes;
                                label = diff < 1
                                    ? 'GPS now'
                                    : 'GPS ${diff}m ago';
                              } else if (status == GpsStatus.permissionDenied) {
                                label = 'No GPS perm';
                              } else if (status == GpsStatus.loading) {
                                label = 'GPS ...';
                              } else {
                                label = 'GPS off';
                              }
                              return HeroMetric(
                                icon: Icons.location_on_outlined,
                                label: label,
                              );
                            },
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
                    ListenableBuilder(
                      listenable: location,
                      builder: (context, _) {
                        String subtitle;
                        if (location.status == GpsStatus.available &&
                            location.lastFix != null) {
                          final diff = DateTime.now()
                              .difference(location.lastFix!)
                              .inMinutes;
                          subtitle = diff < 1
                              ? 'Last fix: now'
                              : 'Last fix: ${diff}m ago';
                        } else if (location.status ==
                            GpsStatus.permissionDenied) {
                          subtitle = 'Location denied';
                        } else {
                          subtitle = 'No GPS fix';
                        }
                        return QuickAction(
                          label: 'Share location',
                          subtitle: subtitle,
                          icon: Icons.my_location_rounded,
                          color: const Color(0xFF1C6B83),
                          onTap: onShareLocation,
                        );
                      },
                    ),
                    QuickAction(
                      label: 'Ask resQ',
                      subtitle: 'Local AI assistant',
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
                StreamBuilder<MeshState>(
                  stream: mesh.stateStream,
                  initialData: mesh.state,
                  builder: (context, meshSnapshot) {
                    final isMeshRunning =
                        meshSnapshot.data == MeshState.running;
                    final contacts = mesh.contacts;
                    final peerCount = mesh.connectedCount;
                    return ListenableBuilder(
                      listenable: Listenable.merge([battery, location]),
                      builder: (context, _) {
                        final batteryStatus = battery.status;
                        String batteryTitle;
                        String batteryDetail;
                        if (batteryStatus == BatteryStatus.loading) {
                          batteryTitle = 'Battery ...';
                          batteryDetail = 'Reading battery';
                        } else if (batteryStatus == BatteryStatus.unavailable ||
                            batteryStatus == BatteryStatus.error) {
                          batteryTitle = 'Battery unavailable';
                          batteryDetail = 'Could not read battery';
                        } else {
                          final charge = battery.isCharging
                              ? 'Charging'
                              : 'On battery';
                          batteryTitle = 'Battery ${battery.level}%';
                          batteryDetail = battery.isPowerSave
                              ? '$charge • Power saver on'
                              : charge;
                        }

                        final gpsStatus = location.status;
                        String gpsTitle;
                        String gpsDetail;
                        if (gpsStatus == GpsStatus.loading) {
                          gpsTitle = 'GPS ...';
                          gpsDetail = 'Acquiring position';
                        } else if (gpsStatus == GpsStatus.permissionDenied) {
                          gpsTitle = 'GPS permission denied';
                          gpsDetail = 'Enable in Settings';
                        } else if (gpsStatus == GpsStatus.unavailable) {
                          gpsTitle = 'GPS disabled';
                          gpsDetail = 'Turn on location';
                        } else if (gpsStatus == GpsStatus.error) {
                          gpsTitle = 'GPS error';
                          gpsDetail = 'Could not read GPS';
                        } else {
                          final pos = location.position;
                          if (pos != null) {
                            final lat = pos.latitude.toStringAsFixed(4);
                            final lng = pos.longitude.toStringAsFixed(4);
                            gpsTitle = '$lat, $lng';
                            final acc = pos.accuracy;
                            gpsDetail = acc > 0
                                ? 'Accuracy +/- ${acc.toStringAsFixed(0)}m'
                                : 'Position acquired';
                          } else {
                            gpsTitle = 'GPS acquired';
                            gpsDetail = 'Waiting for fix';
                          }
                        }

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: [
                                InfoRow(
                                  icon: Icons.group_outlined,
                                  title: isMeshRunning
                                      ? (contacts.isNotEmpty
                                            ? contacts.first.name
                                            : 'Your mesh')
                                      : 'Mesh offline',
                                  detail: isMeshRunning
                                      ? '${contacts.length} contacts, $peerCount nearby'
                                      : 'Start mesh in People tab',
                                  color: const Color(0xFF2A5D4A),
                                ),
                                const Divider(height: 28),
                                InfoRow(
                                  icon: Icons.battery_5_bar_rounded,
                                  title: batteryTitle,
                                  detail: batteryDetail,
                                  color: const Color(0xFF1C6B83),
                                ),
                                const Divider(height: 28),
                                InfoRow(
                                  icon: Icons.location_on_outlined,
                                  title: gpsTitle,
                                  detail: gpsDetail,
                                  color: const Color(0xFF75613B),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: onLibrary,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Manage model and settings'),
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
  const AssistantScreen({required this.model, super.key});

  final ModelStore model;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      content:
          'I can answer questions using the local model. Nothing in this conversation leaves this phone.',
      isAssistant: true,
    ),
  ];
  bool _isGenerating = false;
  late final AnimationController _thinkingAnimation;

  @override
  void initState() {
    super.initState();
    _thinkingAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _thinkingAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isThinking =>
      _isGenerating && _messages.isNotEmpty && _messages.last.isAssistant;

  Future<void> _toggleModel() async {
    if (widget.model.isLoaded) {
      try {
        await widget.model.unload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model unloaded from memory.')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unload model: $error')),
        );
      }
    } else if (widget.model.hasModel) {
      try {
        await widget.model.load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model loaded and ready.')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load model: $error')));
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(content: text, isAssistant: false));
      _controller.clear();
      _isGenerating = true;
    });

    if (!widget.model.hasModel) {
      setState(() {
        _isGenerating = false;
        _messages.add(
          const _ChatMessage(
            content:
                'Import a GGUF model from Settings before asking the offline assistant.',
            isAssistant: true,
          ),
        );
      });
      return;
    }

    if (!widget.model.isLoaded) {
      setState(() {
        _isGenerating = false;
        _messages.add(
          const _ChatMessage(
            content: 'Tap the model chip above to load the local model first.',
            isAssistant: true,
          ),
        );
      });
      return;
    }

    final prompt = _generalPrompt(text);

    setState(() {
      _messages.add(const _ChatMessage(content: '', isAssistant: true));
    });

    try {
      await for (final token in widget.model.generate(prompt: prompt)) {
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

  void _openSettings(BuildContext context) {
    final shell = context.findAncestorStateOfType<_ResQShellState>();
    shell?._setTab(3);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.model,
      builder: (context, _) {
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
                            'Private. Local. Offline.',
                            style: TextStyle(color: Color(0xFF68736D)),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _openSettings(context),
                      icon: const Icon(Icons.settings_rounded),
                      tooltip: 'Settings',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E7E0),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF68736D),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Offline assistant',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF68736D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _toggleModel,
                  child: Ink(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.model.isBusy
                          ? const Color(0xFFE8E7E0)
                          : widget.model.isLoaded
                          ? const Color(0xFFDFF0E0)
                          : widget.model.hasModel
                          ? const Color(0xFFFFF3D6)
                          : const Color(0xFFE8E7E0),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.model.isLoaded
                              ? Icons.memory_rounded
                              : widget.model.hasModel
                              ? Icons.memory_outlined
                              : Icons.auto_awesome_outlined,
                          color: widget.model.isLoaded
                              ? const Color(0xFF2A5D4A)
                              : const Color(0xFF75613B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.model.isBusy
                                ? 'Loading model…'
                                : widget.model.isLoaded
                                ? 'Model loaded — tap to unload'
                                : widget.model.hasModel
                                ? 'Model stored — tap to load'
                                : 'No local model imported',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (widget.model.hasModel)
                          Icon(
                            widget.model.isLoaded
                                ? Icons.power_settings_new_rounded
                                : Icons.play_arrow_rounded,
                            color: widget.model.isLoaded
                                ? const Color(0xFF2A5D4A)
                                : const Color(0xFF75613B),
                          ),
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
                    final isThinking =
                        _isThinking && index - 1 == _messages.length - 1;
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
                        child: isThinking
                            ? _ThinkingDots(animation: _thinkingAnimation)
                            : Text(
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
                    _isGenerating
                        ? IconButton.filledTonal(
                            onPressed: () {
                              widget.model.stopGeneration();
                              setState(() => _isGenerating = false);
                            },
                            icon: const Icon(Icons.stop_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFFFE0DF),
                              foregroundColor: const Color(0xFFC33D30),
                            ),
                          )
                        : IconButton.filled(
                            onPressed: _send,
                            icon: const Icon(Icons.arrow_upward_rounded),
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
  const PeopleScreen({required this.mesh, super.key});

  final MeshController mesh;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  MeshState _state = MeshState.stopped;
  String _statusText = 'Mesh is off';
  bool _permDenied = false;
  bool _locationDenied = false;
  bool _btOff = false;
  List<MeshPeer> _peerList = const [];

  /// Collapse raw MeshPeers that share a verified resQ senderId
  /// (identityHint) into a single row. Prefer the connected, named entry.
  List<MeshPeer> _coalescePeers(List<MeshPeer> peers) {
    final byIdentity = <String, MeshPeer>{};
    for (final peer in peers) {
      final key = peer.identityHint ?? peer.id;
      final existing = byIdentity[key];
      if (existing == null) {
        byIdentity[key] = peer;
      } else {
        // keep the most informative: connected over not, named over raw uuid
        byIdentity[key] = MeshPeer(
          id: existing.identityHint ?? existing.id,
          nickname: existing.connected
              ? existing.nickname
              : peer.nickname,
          lastSeen: peer.lastSeen,
          identityHint: existing.identityHint ?? peer.identityHint,
          connected: existing.connected || peer.connected,
        );
      }
    }
    return byIdentity.values.toList();
  }

  @override
  void initState() {
    super.initState();
    widget.mesh.stateStream.listen((s) {
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
    widget.mesh.peersStream.listen((peers) {
      if (mounted) setState(() => _peerList = peers);
    });
  }

  Future<void> _toggleMesh() async {
    if (_state == MeshState.running || _state == MeshState.starting) {
      await widget.mesh.stop();
      return;
    }
    final result = await widget.mesh.requestPermissions();
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
    try {
      await widget.mesh.start();
    } on BluetoothOffException {
      if (!mounted) return;
      setState(() => _btOff = true);
      return;
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth mesh could not start: $error')),
      );
    }
  }

  Future<void> _handleContact(PersonalContact contact) async {
    switch (contact.status) {
      case ConnectionStatus.available:
      case ConnectionStatus.rejected:
      case ConnectionStatus.disconnected:
        await widget.mesh.requestConnection(contact);
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
        if (accepted != null) {
          await widget.mesh.respondToRequest(contact, accepted);
        }
        return;
      case ConnectionStatus.connected:
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                PersonalChatScreen(controller: widget.mesh, contact: contact),
          ),
        );
        return;
      case ConnectionStatus.outgoingPending:
        break;
    }
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(
      text: widget.mesh.displayName == 'resQ' ? '' : widget.mesh.displayName,
    );
    if (!mounted) return;
    final saved = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            hintText: 'e.g. Rescuer 2',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final trimmed = saved.trim();
    widget.mesh.nickname = trimmed.isEmpty ? null : trimmed;
    await NicknameStore.save(trimmed.isEmpty ? null : trimmed);
    if (mounted) setState(() {});
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
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Set your display name',
                onPressed: _editNickname,
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
            onAction: () => widget.mesh.refreshPresence(),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<PersonalContact>>(
            stream: widget.mesh.contactsStream,
            initialData: widget.mesh.contacts,
            builder: (context, snapshot) {
              final contacts = snapshot.data ?? const [];
              // The BLE layer reports one MeshPeer per peripheral.uuid, and a
              // real resQ device opens BOTH an inbound and an outbound GATT
              // link (two different uuids) plus a rotating scan MAC. They all
              // collapse to ONE person once the signed announce verifies and
              // stamps identityHint (=resQ senderId). Coalesce here so the UI
              // shows a single row per real peer instead of 2-3 duplicate
              // "resQ" entries. (See the 3uuid->1identity logs.)
              final rawPeers = contacts.isEmpty
                  ? _coalescePeers(_peerList)
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
                          onConnect: () => widget.mesh.refreshPresence(),
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.model, super.key});

  final ModelStore model;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<void> _importModel() async {
    try {
      final imported = await widget.model.import();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported
                ? 'Model imported. Go to Assistant to load it.'
                : 'Model import was cancelled.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import model: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.model,
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
                        'Settings',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Model and device configuration',
                        style: TextStyle(color: Color(0xFF68736D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Chat model'),
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
                        color: widget.model.isLoaded
                            ? const Color(0xFFE2F0E4)
                            : const Color(0xFFE8E7E0),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        widget.model.isLoaded
                            ? Icons.memory_rounded
                            : Icons.memory_outlined,
                        color: widget.model.isLoaded
                            ? const Color(0xFF2A5D4A)
                            : const Color(0xFF68736D),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.model.isLoaded
                                ? 'Model loaded in memory'
                                : widget.model.hasModel
                                ? 'Model stored (not loaded)'
                                : 'No GGUF model imported',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.model.isBusy
                                ? 'Working…'
                                : widget.model.hasModel
                                ? '${_formatBytes(widget.model.status.sizeBytes)} • ${widget.model.isLoaded ? 'loaded' : 'tap load in Assistant'}'
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
                      onPressed: widget.model.isBusy ? null : _importModel,
                      child: Text(widget.model.hasModel ? 'Replace' : 'Import'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Import a GGUF model (e.g. Qwen2.5-0.5B-Q4_K_M) to enable offline AI assistance. The model stays on this device and never sends data to any server.',
              style: TextStyle(color: Color(0xFF68736D), height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
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

String _generalPrompt(String question) =>
    'Answer the following question as a helpful offline assistant. Be concise and clear.\n\nQuestion: $question';

class SensorSheet extends StatelessWidget {
  const SensorSheet({
    required this.location,
    required this.deviceSensors,
    super.key,
  });

  final LocationService location;
  final DeviceSensorService deviceSensors;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
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
            ListenableBuilder(
              listenable: deviceSensors,
              builder: (context, _) {
                final heading =
                    deviceSensors.compassStatus == SensorStatus.available
                    ? deviceSensors.heading
                    : null;
                final dir = deviceSensors.cardinalDirection;
                final degrees = heading != null
                    ? '${heading.toStringAsFixed(0)} degrees'
                    : deviceSensors.compassStatus == SensorStatus.loading
                    ? 'Compass initializing...'
                    : 'Compass unavailable';
                return Container(
                  height: 155,
                  decoration: BoxDecoration(
                    color: const Color(0xFF17483B),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.navigation_rounded,
                        color: Color(0xFFB9E4C3),
                        size: 44,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dir,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        degrees,
                        style: const TextStyle(color: Color(0xFFC4E3CC)),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: location,
              builder: (context, _) {
                final pos = location.position;
                final accuracy = pos?.accuracy;
                final altitude = pos?.altitude;
                final locStatus = location.status;
                final speed = location.speed;

                String accValue;
                if (locStatus == GpsStatus.loading) {
                  accValue = 'Loading...';
                } else if (locStatus == GpsStatus.permissionDenied) {
                  accValue = 'Permission denied';
                } else if (locStatus == GpsStatus.unavailable) {
                  accValue = 'GPS disabled';
                } else if (accuracy != null && accuracy > 0) {
                  accValue = '+/- ${accuracy.toStringAsFixed(1)} m';
                } else {
                  accValue = 'Waiting...';
                }

                String altValue;
                if (locStatus == GpsStatus.loading) {
                  altValue = 'Loading...';
                } else if (locStatus != GpsStatus.available) {
                  altValue = 'Unavailable';
                } else if (altitude != null) {
                  altValue = '${altitude.toStringAsFixed(0)} m';
                } else {
                  altValue = 'Unavailable';
                }

                String speedValue;
                if (locStatus == GpsStatus.loading) {
                  speedValue = 'Loading...';
                } else if (locStatus != GpsStatus.available ||
                    speed == null ||
                    speed < 0) {
                  speedValue = 'Unavailable';
                } else {
                  speedValue = '${(speed * 3.6).toStringAsFixed(1)} km/h';
                }

                String latLngValue;
                if (pos != null && locStatus == GpsStatus.available) {
                  latLngValue =
                      '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                } else if (locStatus == GpsStatus.loading) {
                  latLngValue = 'Loading...';
                } else if (locStatus == GpsStatus.permissionDenied) {
                  latLngValue = 'Permission denied';
                } else if (locStatus == GpsStatus.unavailable) {
                  latLngValue = 'GPS disabled';
                } else {
                  latLngValue = 'Unavailable';
                }

                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    SensorMetric(
                      icon: Icons.my_location_rounded,
                      label: 'GPS accuracy',
                      value: accValue,
                    ),
                    SensorMetric(
                      icon: Icons.landscape_rounded,
                      label: 'Elevation',
                      value: altValue,
                    ),
                    SensorMetric(
                      icon: Icons.speed_rounded,
                      label: 'Speed',
                      value: speedValue,
                    ),
                    SensorMetric(
                      icon: Icons.pin_drop_outlined,
                      label: 'Position',
                      value: latLngValue,
                      valueFontSize: 12,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: deviceSensors,
              builder: (context, _) {
                final isAvailable =
                    deviceSensors.flashlightStatus == SensorStatus.available;
                final isOn = deviceSensors.isFlashlightOn;
                return Card(
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
                    subtitle: Text(
                      isAvailable
                          ? (isOn ? 'On' : 'Off')
                          : 'Not available on this device',
                    ),
                    trailing: Switch(
                      value: isOn,
                      onChanged: isAvailable
                          ? (_) => deviceSensors.toggleFlashlight()
                          : null,
                    ),
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

class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final phase = (animation.value * 3).floor();
        return Text(
          phase == 0
              ? '.'
              : phase == 1
              ? '..'
              : '...',
          style: const TextStyle(
            color: Color(0xFF68736D),
            fontSize: 28,
            height: 0.6,
            letterSpacing: 2,
          ),
        );
      },
    );
  }
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

class SensorMetric extends StatelessWidget {
  const SensorMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.valueFontSize = 16,
    super.key,
  });
  final IconData icon;
  final String label;
  final String value;
  final double valueFontSize;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF2A5D4A), size: 19),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: valueFontSize,
              ),
            ),
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
