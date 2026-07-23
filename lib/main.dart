import 'package:flutter/material.dart';

void main() {
  runApp(const ResQApp());
}

class ResQApp extends StatelessWidget {
  const ResQApp({super.key});

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
      home: const ResQShell(),
    );
  }
}

class ResQShell extends StatefulWidget {
  const ResQShell({super.key});

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
        onAssistant: () => setState(() => _selectedIndex = 1),
        onPeople: () => setState(() => _selectedIndex = 2),
        onLibrary: () => setState(() => _selectedIndex = 3),
        onSensors: _openSensors,
        onSos: _openSos,
      ),
      const AssistantScreen(),
      const PeopleScreen(),
      const LibraryScreen(),
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
    required this.onAssistant,
    required this.onPeople,
    required this.onLibrary,
    required this.onSensors,
    required this.onSos,
    super.key,
  });

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
                    const StatusPill(
                      label: 'OFFLINE',
                      icon: Icons.cloud_off_rounded,
                    ),
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
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Column(
                      children: [
                        InfoRow(
                          icon: Icons.group_outlined,
                          title: 'Weekend trek',
                          detail: '6 members, 3 nearby',
                          color: Color(0xFF2A5D4A),
                        ),
                        Divider(height: 28),
                        InfoRow(
                          icon: Icons.description_outlined,
                          title: 'Himachal trail guide',
                          detail: 'Ready for offline chat',
                          color: Color(0xFF75613B),
                        ),
                        Divider(height: 28),
                        InfoRow(
                          icon: Icons.battery_5_bar_rounded,
                          title: 'Battery 74%',
                          detail: 'Battery saver is off',
                          color: Color(0xFF1C6B83),
                        ),
                      ],
                    ),
                  ),
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
  const AssistantScreen({super.key});

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
  bool _guideSelected = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(content: text, isAssistant: false));
      _messages.add(
        _ChatMessage(
          content: _guideSelected
              ? 'Based on Himachal trail guide.pdf, the document describes a reliable water point before the third camp. Check the condition locally before relying on it. [p. 14]'
              : 'I am working from the local model only. Add a document if you want a source-grounded answer.',
          isAssistant: true,
        ),
      );
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Document picker will connect here.'),
                    ),
                  ),
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
              onTap: () => setState(() => _guideSelected = !_guideSelected),
              child: Ink(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _guideSelected
                      ? const Color(0xFFE2F0E4)
                      : const Color(0xFFE8E7E0),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      _guideSelected
                          ? Icons.description_rounded
                          : Icons.auto_awesome_rounded,
                      color: const Color(0xFF2A5D4A),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _guideSelected
                            ? 'Using: Himachal trail guide.pdf'
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
                        onTap: () => _controller.text = 'Summarize this guide',
                      ),
                      PromptChip(
                        label: 'Find water sources',
                        onTap: () => _controller.text = 'Find water sources',
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
                    decoration: const InputDecoration(hintText: 'Ask anything'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  void _showPairing(BuildContext context, String device) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, size: 36),
        title: Text('Verify $device'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Make sure both phones show the same code before connecting.'),
            SizedBox(height: 20),
            Text(
              '482 391',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Codes match'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          const Row(
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
              StatusPill(label: 'VISIBLE', icon: Icons.visibility_outlined),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFF17483B),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discovering nearby devices',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Bluetooth is on. Names stay hidden until you connect.',
                          style: TextStyle(
                            color: Color(0xFFC4E3CC),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.pause_circle_outline_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          SectionTitle(title: 'Nearby devices', action: 'Scan'),
          const SizedBox(height: 10),
          NearbyDevice(
            name: 'resQ-7F2A',
            detail: 'Seen now | BLE',
            onConnect: () => _showPairing(context, 'resQ-7F2A'),
          ),
          const SizedBox(height: 10),
          NearbyDevice(
            name: 'resQ-19B8',
            detail: 'Seen 1 min ago | BLE',
            onConnect: () => _showPairing(context, 'resQ-19B8'),
          ),
          const SizedBox(height: 10),
          NearbyDevice(
            name: 'resQ-4D63',
            detail: 'Seen 3 min ago | Wi-Fi ready',
            onConnect: () => _showPairing(context, 'resQ-4D63'),
          ),
          const SizedBox(height: 28),
          SectionTitle(title: 'Your groups', action: 'Create'),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F0E4),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.hiking_rounded,
                  color: Color(0xFF2A5D4A),
                ),
              ),
              title: const Text(
                'Weekend trek',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('6 members | 3 nearby'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Group chat will open here.')),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Messages are encrypted before they leave your phone. Nearby devices can relay them without reading them.',
            style: TextStyle(color: Color(0xFF68736D), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Choose a PDF, photo, or note to add.'),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
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
                    'Your library is designed for local encrypted storage.',
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
          const SectionTitle(title: 'Documents'),
          const SizedBox(height: 10),
          const LibraryItem(
            icon: Icons.picture_as_pdf_rounded,
            title: 'Himachal trail guide',
            subtitle: 'PDF | 2.8 MB | Ready to chat',
            color: Color(0xFFC33D30),
          ),
          const SizedBox(height: 10),
          const LibraryItem(
            icon: Icons.menu_book_rounded,
            title: 'First aid field notes',
            subtitle: 'Guide | Saved for offline use',
            color: Color(0xFF2A5D4A),
          ),
          const SizedBox(height: 10),
          const LibraryItem(
            icon: Icons.article_outlined,
            title: 'Community rights reference',
            subtitle: 'PDF | Added yesterday',
            color: Color(0xFF1C6B83),
          ),
          const SizedBox(height: 28),
          const SectionTitle(title: 'Observations'),
          const SizedBox(height: 10),
          const LibraryItem(
            icon: Icons.image_search_rounded,
            title: 'Food label - camp store',
            subtitle: 'Photo summary | Today, 09:42',
            color: Color(0xFF75613B),
          ),
          const SizedBox(height: 10),
          const LibraryItem(
            icon: Icons.edit_note_rounded,
            title: 'Meeting point notes',
            subtitle: 'Note | Shared with Weekend trek',
            color: Color(0xFF5E4B7A),
          ),
        ],
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
    super.key,
  });
  final String name;
  final String detail;
  final VoidCallback onConnect;
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
      trailing: TextButton(onPressed: onConnect, child: const Text('Connect')),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.action, super.key});
  final String title;
  final String? action;
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
      if (action != null) TextButton(onPressed: () {}, child: Text(action!)),
    ],
  );
}

class LibraryItem extends StatelessWidget {
  const LibraryItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
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
      trailing: const Icon(Icons.more_horiz_rounded),
    ),
  );
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
}
