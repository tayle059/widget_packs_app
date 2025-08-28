import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Screens
import 'feed_pets_screen.dart';
import 'affirmation_screen.dart';
import 'water_intake_screen.dart';
import 'calming_session_screen.dart';
import 'habit_kicker_screen.dart';
import 'top_news_screen.dart';
import 'wellness_toolkit_screen.dart';
import 'notes_transcribe_screen.dart';
import 'learning_bits_screen.dart';
import 'stock_option_screen.dart';
import 'get_up_reminder_screen.dart';

// Route observer to know when we return to Home
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() {
  runApp(const WidgetPacksApp());
}

class WidgetPacksApp extends StatelessWidget {
  const WidgetPacksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Widget Packs',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(height: 1.25),
          labelLarge: TextStyle(fontWeight: FontWeight.w600),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
      navigatorObservers: [routeObserver],
    );
  }
}

/// Model/spec for a widget tile
class _WidgetSpec {
  final String id; // stable ID to persist order/visibility
  final String title;
  final IconData icon;
  final Widget? screen;
  const _WidgetSpec(this.id, this.title, this.icon, {this.screen});
}

/// Default widget catalog (order here is the “factory order” used if no prefs yet)
const List<_WidgetSpec> _catalog = [
  _WidgetSpec('affirmation', 'Affirmation', Icons.wb_sunny_outlined, screen: AffirmationScreen()),
  _WidgetSpec('calming', 'Calming Session', Icons.self_improvement, screen: CalmingSessionScreen()),
  _WidgetSpec('habit', 'Habit Kicker', Icons.check_circle_outline, screen: HabitKickerScreen()),
  _WidgetSpec('getup', 'Get Up Reminder', Icons.alarm, screen: GetUpReminderScreen()),
  _WidgetSpec('water', 'Water Intake', Icons.water_drop_outlined, screen: WaterIntakeScreen()),
  _WidgetSpec('learning', 'Learning Bits', Icons.menu_book_outlined, screen: LearningBitsScreen()),
  _WidgetSpec('news', 'Top News', Icons.article_outlined, screen: TopNewsScreen()),
  _WidgetSpec('stocks', 'Stock Option', Icons.show_chart, screen: StockOptionScreen()),
  _WidgetSpec('pets', 'Feed the Pets', Icons.pets, screen: FeedPetsScreen()),
  _WidgetSpec('wellness', 'Wellness Toolkit', Icons.favorite_border, screen: WellnessToolkitScreen()),
  _WidgetSpec('notes', 'Notes / Transcribe', Icons.mic_none, screen: NotesTranscribeScreen()),
];

const _prefsOrderKey = 'home_order_v1';
const _prefsHiddenKey = 'home_hidden_v1';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _daysUsed = 0, _streak = 0, _longest = 0;

  // layout state
  List<String> _order = _catalog.map((e) => e.id).toList();
  Set<String> _hidden = {};

  // profile state
  String? _profileName;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _initCounters();
    _loadLayoutPrefs();
    _loadProfile();
  }

  Future<void> _initCounters() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final lastIso = prefs.getString('last_open_date');
    final last = lastIso != null ? DateTime.tryParse(lastIso) : null;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    int daysUsed = prefs.getInt('days_used') ?? 0;
    int streak = prefs.getInt('streak_current') ?? 0;
    int longest = prefs.getInt('streak_longest') ?? 0;

    if (last == null) {
      daysUsed = 1;
      streak = 1;
      longest = 1;
    } else if (!sameDay(today, last)) {
      daysUsed += 1;
      final gap = today.difference(DateTime(last.year, last.month, last.day)).inDays;
      if (gap == 1) {
        streak += 1;
      } else if (gap > 1) {
        streak = 1;
      }
      if (streak > longest) longest = streak;
    }

    await prefs.setInt('days_used', daysUsed);
    await prefs.setInt('streak_current', streak);
    await prefs.setInt('streak_longest', longest);
    await prefs.setString('last_open_date', today.toIso8601String());

    if (!mounted) return;
    setState(() {
      _daysUsed = daysUsed;
      _streak = streak;
      _longest = longest;
    });
  }

  Future<void> _loadLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(_prefsOrderKey);
    final savedHidden = prefs.getStringList(_prefsHiddenKey) ?? [];
    final catalogIds = _catalog.map((e) => e.id).toSet();

    List<String> order;
    if (savedOrder == null) {
      order = _catalog.map((e) => e.id).toList();
    } else {
      order = savedOrder.where(catalogIds.contains).toList();
      for (final id in catalogIds) {
        if (!order.contains(id)) order.add(id);
      }
    }
    setState(() {
      _order = order;
      _hidden = savedHidden.where(catalogIds.contains).toSet();
    });
  }

  Future<void> _saveLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsOrderKey, _order);
    await prefs.setStringList(_prefsHiddenKey, _hidden.toList());
  }

  List<_WidgetSpec> _visibleTiles() {
    final mapById = {for (final w in _catalog) w.id: w};
    final result = <_WidgetSpec>[];
    for (final id in _order) {
      if (!_hidden.contains(id) && mapById.containsKey(id)) {
        result.add(mapById[id]!);
      }
    }
    return result;
  }

  void _openCustomize() async {
    final updated = await Navigator.of(context).push<List<dynamic>>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, a, __) =>
            FadeTransition(opacity: a, child: CustomizeWidgetsScreen(order: _order, hidden: _hidden)),
      ),
    );
    if (updated != null && updated.length == 2) {
      setState(() {
        _order = (updated[0] as List).cast<String>();
        _hidden = (updated[1] as List).cast<String>().toSet();
      });
      await _saveLayoutPrefs();
    }
  }

  // -------- Profile (name + avatar) --------

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileName = prefs.getString('profile_name');
      _avatarPath  = prefs.getString('profile_avatar_path');
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _profileName ?? '');
    await prefs.setString('profile_avatar_path', _avatarPath ?? '');
  }

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final saved = await File(picked.path).copy(dest.path);

      setState(() => _avatarPath = saved.path);
      await _saveProfile();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not pick image')),
      );
    }
  }

  void _editName(String name) async {
    setState(() => _profileName = name.trim().isEmpty ? null : name.trim());
    await _saveProfile();
  }

  Future<void> _clearAvatar() async {
    setState(() => _avatarPath = null);
    await _saveProfile();
  }

  String _initialsFromName(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '';
    final parts = n.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return n.characters.first.toUpperCase();
    final first = parts.first.characters.first.toUpperCase();
    final last = parts.length > 1 ? parts.last.characters.first.toUpperCase() : '';
    return '$first$last';
  }

  Future<void> _openProfileSheet() async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ProfileSheet(
        name: _profileName ?? '',
        avatarPath: _avatarPath,
        onPickPhoto: _pickAvatar,
        onClearPhoto: _clearAvatar,
        onSaveName: _editName,
      ),
    );
  }

  // -----------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = _visibleTiles();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _openProfileSheet,
                    child: _Avatar(
                      radius: 22,
                      name: _profileName,
                      avatarPath: _avatarPath,
                      initialsBuilder: _initialsFromName,
                    ),
                  ),
                  const Spacer(),
                  // Streak badge (gradient)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primaryContainer, scheme.secondaryContainer],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text('Streak: $_streak', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(width: 10),
                        Text('Best: $_longest', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Days used pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text('Days used: $_daysUsed',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: _openCustomize,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: tiles.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final spec = tiles[index];
                    final bg = _pastels[index % _pastels.length];

                    return GestureDetector(
                      onLongPress: _openCustomize, // long-press to edit
                      child: _WidgetTile(
                        title: spec.title,
                        icon: spec.icon,
                        background: bg,
                        onTap: () {
                          if (spec.screen != null) {
                            Navigator.of(context).push(PageRouteBuilder(
                              transitionDuration: const Duration(milliseconds: 220),
                              pageBuilder: (_, a, __) =>
                                  FadeTransition(opacity: a, child: spec.screen!),
                            ));
                          } else {
                            Navigator.of(context).push(PageRouteBuilder(
                              transitionDuration: const Duration(milliseconds: 220),
                              pageBuilder: (_, a, __) =>
                                  FadeTransition(opacity: a, child: WidgetDetailScreen(spec: spec)),
                            ));
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

            // 🦥 Mascot bar
            const _MascotBar(),
          ],
        ),
      ),
    );
  }
}

// Reusable pastel palette
const _pastels = [
  Color(0xFFFFE2D6),
  Color(0xFFE2F3F4),
  Color(0xFFFFF0B3),
  Color(0xFFEDE3FF),
  Color(0xFFDFF5C8),
];

// Nicer, elevated square tiles
class _WidgetTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  const _WidgetTile({
    super.key,
    required this.title,
    required this.icon,
    required this.background,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: background,
      elevation: 1.5,
      shadowColor: scheme.shadow.withOpacity(0.15),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: Colors.black87),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Avatar widget
class _Avatar extends StatelessWidget {
  final double radius;
  final String? name;
  final String? avatarPath;
  final String Function(String?) initialsBuilder;

  const _Avatar({
    super.key,
    required this.radius,
    required this.name,
    required this.avatarPath,
    required this.initialsBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget child;
    if (avatarPath != null && avatarPath!.isNotEmpty && File(avatarPath!).existsSync()) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(avatarPath!),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
        ),
      );
    } else {
      final initials = initialsBuilder(name);
      child = Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(colors: [
            scheme.primaryContainer,
            scheme.secondaryContainer,
          ]),
        ),
        alignment: Alignment.center,
        child: Text(
          initials.isEmpty ? '🙂' : initials,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: initials.isEmpty ? radius : radius * 0.95,
            letterSpacing: -0.5,
          ),
        ),
      );
    }

    return Semantics(
      label: 'User avatar',
      child: child,
    );
  }
}

// Fallback placeholder for tiles without a real screen yet
class WidgetDetailScreen extends StatelessWidget {
  final _WidgetSpec spec;
  const WidgetDetailScreen({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(spec.title)),
      body: Center(
        child: Text(
          'TODO: Implement "${spec.title}"',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Sloth Mascot bar with rotating “nice things”
/// - Auto-rotates every 10s
/// - Tap bubble to shuffle now
/// - Long-press to pause/resume
/// - Starts at a random message AND randomizes again whenever you return to Home
class _MascotBar extends StatefulWidget {
  const _MascotBar({super.key});

  @override
  State<_MascotBar> createState() => _MascotBarState();
}

class _MascotBarState extends State<_MascotBar> with RouteAware {
  static const _interval = Duration(seconds: 10); // slower pace
  static const _messages = <String>[
    // Core set
    "You're doing great. One small step at a time. 🌱",
    "Remember to breathe—slow and easy. 💨",
    "Proud of you for showing up today. 🙌",
    "Tiny progress still counts. Keep going. ➕",
    "Your future self says: thank you. 🧡",
    "Water break? Your body will love it. 💧",
    "It’s okay to rest. Rest is productive. 😴",
    "You’ve got this—softly but surely. 🐢",

    // Funny + motivational expansion (~50+)
    "Be the sloth you want to see in the world. 🦥",
    "Hydrate like your WiFi depends on it. 📶💧",
    "Coffee is basically bean soup—own it. ☕",
    "Slow progress is still progress. Snails unite! 🐌",
    "Your checklist fears you. ✔️😎",
    "Even your phone needs recharging. So can you. 🔋",
    "Stretch! You’re not a statue… probably. 🗿",
    "Dance break: nobody’s watching (except maybe the cat). 🕺",
    "Reminder: naps are a valid life strategy. 🛏️",
    "You're 100% undefeated at surviving days. 🎯",
    "Mistakes = proof you’re trying. Keep trying. 🔧",
    "Eat the frog… but maybe after coffee. 🐸",
    "Every big goal is just a bunch of small wins stacked. 🪜",
    "Hydration station, next stop YOU. 🚰",
    "Smile… it confuses your stress. 😁",
    "Your brain is basically electric Jell-O. Take care of it. ⚡🍮",
    "One day at a time. One snack at a time. 🍪",
    "Hey, posture check. Your back will thank you. 🪑",
    "Nobody asked, but you’re crushing it anyway. 💪",
    "The WiFi of life has reconnected. Stay online. 🌐",
    "Courage is doing the scary thing anyway. 🦁",
    "Remember: sloths win by simply refusing to quit. 🦥",
    "Your vibe is stronger than your to-do list. ✨",
    "Good news: naps are calorie-free. 💤",
    "Keep scrolling life upwards, not sideways. 🚀",
    "Be kind—you never know who skipped lunch. 🥪",
    "A little progress each day adds up like compound interest. 📈",
    "If you’re reading this, you’re not giving up. 🎉",
    "Brains are weird. Rest them often. 🧠",
    "Start messy. Perfect later. 🖌️",
    "Laugh breaks are productivity hacks. 😂",
    "Seriously: drink that water. Your skin knows. 💧",
    "Don't forget to unclench your jaw. 😬➡️😌",
    "Your dreams called—they said thanks for not ghosting. 📞",
    "Keep calm and sloth on. 🦥",
    "Nobody has it all figured out. Not even Google. 🔍",
    "Mood swings? Call it emotional cardio. 🏃‍♂️",
    "Turn the page, don’t burn the book. 📚",
    "Give today a plot twist. 🎬",
    "Self-care ≠ selfish. It’s system maintenance. 🛠️",
    "Trust the process—even the weird parts. 🔄",
    "Big journeys begin with awkward first steps. 👣",
    "Fail forward faster. 🚴",
    "Celebrate weird little wins. Folded laundry counts. 🧺",
    "Confidence is just 10 seconds of courage on repeat. ⏱️",
    "Growth looks boring up close. Zoom out. 🔍",
    "Eat. Stretch. Nap. Repeat. 🦥",
    "Stress is just your brain flexing. Flex back. 💪",
    "Upgrade your thoughts, not just your phone. 📱",
    "Nobody regrets resting. Ever. 💤",
    "Consistency beats motivation. Show up anyway. 🏆",
    "Your pace is perfect for you. Keep going. ⏳",
    "You’re not behind—your path is unique. 🗺️",
    "Done is a lot better than perfect. ✅",
    "Pause. Sip. Reset. 🔄💧",
    "Your comfort zone called; it’s proud you stepped out. 📦➡️🌈",
    "Keep the promises you make to yourself. 🤝",
    "Let tiny habits carry you on lazy days. 🧩",
    "New day, same awesome you—with patches. ✨",
    "Gratitude is a cheat code for the brain. 🎮",
    "Breathe in calm, breathe out chaos. 🌬️",
    "Your to-do list works for you, not the other way around. 📝",
  ];

  int _index = 0;
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _index = Random().nextInt(_messages.length); // random at creation
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  // Called when a child route (pushed on top) is popped and this route shows again
  @override
  void didPopNext() {
    setState(() {
      _index = Random().nextInt(_messages.length); // re-randomize on return
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      if (!_paused && mounted) {
        setState(() => _index = (_index + 1) % _messages.length);
      }
    });
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  void _advanceNow() {
    setState(() => _index = (_index + 1) % _messages.length);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sloth avatar (emoji by default)
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            // Swap to Image.asset('assets/sloth.png') if you add one to pubspec.yaml
            child: const Text('🦥', style: TextStyle(fontSize: 30)),
          ),
          const SizedBox(width: 10),
          // Speech bubble
          Expanded(
            child: GestureDetector(
              onTap: _advanceNow,
              onLongPress: _togglePause,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Text(
                    _messages[_index],
                    key: ValueKey(_index),
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.25),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            size: 22,
            color: scheme.outline,
          ),
        ],
      ),
    );
  }
}

/// Customize screen (reorder + hide)
class CustomizeWidgetsScreen extends StatefulWidget {
  final List<String> order;
  final Set<String> hidden;
  const CustomizeWidgetsScreen({super.key, required this.order, required this.hidden});

  @override
  State<CustomizeWidgetsScreen> createState() => _CustomizeWidgetsScreenState();
}

class _CustomizeWidgetsScreenState extends State<CustomizeWidgetsScreen> {
  late List<String> _order;
  late Set<String> _hidden;
  final _mapById = {for (final w in _catalog) w.id: w};

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.order);
    _hidden = Set<String>.from(widget.hidden);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
  }

  void _toggle(String id, bool v) {
    setState(() {
      if (v) {
        _hidden.remove(id);
      } else {
        _hidden.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Widgets'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop<List<dynamic>>([_order, _hidden.toList()]);
            },
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Drag the handles to reorder. Use the switch to show/hide items on the home screen.',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              itemCount: _order.length,
              onReorder: _onReorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final id = _order[index];
                final spec = _mapById[id]!;
                final visible = !_hidden.contains(id);
                return ListTile(
                  key: ValueKey(id),
                  tileColor: scheme.surfaceVariant,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(spec.icon),
                  title: Text(spec.title),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: visible,
                        onChanged: (v) => _toggle(id, v),
                      ),
                      const SizedBox(width: 6),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _order = _catalog.map((e) => e.id).toList();
                        _hidden.clear();
                      });
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to Default'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Profile bottom sheet
class _ProfileSheet extends StatefulWidget {
  final String name;
  final String? avatarPath;
  final Future<void> Function() onPickPhoto;
  final Future<void> Function() onClearPhoto;
  final void Function(String) onSaveName;

  const _ProfileSheet({
    super.key,
    required this.name,
    required this.avatarPath,
    required this.onPickPhoto,
    required this.onClearPhoto,
    required this.onSaveName,
  });

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _initials(String? n) {
    final s = n?.trim();
    if (s == null || s.isEmpty) return '';
    final parts = s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (parts.isEmpty) return s.characters.first.toUpperCase();
    final first = parts.first.characters.first.toUpperCase();
    final last = parts.length > 1 ? parts.last.characters.first.toUpperCase() : '';
    return '$first$last';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: media.viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Avatar(
                radius: 30,
                name: _controller.text,
                avatarPath: widget.avatarPath,
                initialsBuilder: _initials,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'e.g., Alex Carter',
                  ),
                  onSubmitted: (v) => widget.onSaveName(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await widget.onPickPhoto();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose Photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await widget.onClearPhoto();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                widget.onSaveName(_controller.text);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
