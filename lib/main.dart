import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'affirmation_screen.dart';
import 'water_intake_screen.dart';
import 'calming_session_screen.dart';
import 'habit_kicker_screen.dart';
import 'top_news_screen.dart';



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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();

  // Single source of truth for the tiles
  static final List<_WidgetSpec> widgets = [
    _WidgetSpec('Affirmation', Icons.wb_sunny_outlined, screen: const AffirmationScreen()),
    _WidgetSpec('Calming Session', Icons.self_improvement, screen: const CalmingSessionScreen()),
    _WidgetSpec('Habit Kicker', Icons.check_circle_outline, screen: const HabitKickerScreen()),
    _WidgetSpec('Get Up Reminder', Icons.alarm),
    _WidgetSpec('Water Intake', Icons.water_drop_outlined, screen: const WaterIntakeScreen()),
    _WidgetSpec('Learning Bits', Icons.menu_book_outlined),
    _WidgetSpec('Top News', Icons.article_outlined, screen: const TopNewsScreen()),
    _WidgetSpec('Stock Option', Icons.show_chart),
    _WidgetSpec('Feed the Pets', Icons.pets),
    _WidgetSpec('Wellness Toolkit', Icons.favorite_border),
  ];
}

class _HomeScreenState extends State<HomeScreen> {
  int _daysUsed = 0;
  int _streak = 0;
  int _longest = 0;

  @override
  void initState() {
    super.initState();
    _initCounters();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    child: const Icon(Icons.person),
                  ),
                  const Spacer(),
                  // Streak badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Text('🔥'),
                        const SizedBox(width: 6),
                        Text('Streak: $_streak',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(width: 10),
                        Text('Best: $_longest',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Days used pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Days used: $_daysUsed',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 3x3 grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.builder(
                  itemCount: HomeScreen.widgets.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final spec = HomeScreen.widgets[index];
                    final pastels = [
                      const Color(0xFFFFE2D6),
                      const Color(0xFFE2F3F4),
                      const Color(0xFFFFF0B3),
                      const Color(0xFFEDE3FF),
                      const Color(0xFFDFF5C8),
                    ];
                    final bg = pastels[index % pastels.length];

                    return _WidgetTile(
                      title: spec.title,
                      icon: spec.icon,
                      background: bg,
                      onTap: () {
                        if (spec.screen != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => spec.screen!),
                          );
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WidgetDetailScreen(spec: spec),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ),

            // Congrats banner
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.celebration),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '🎉 Congrats! You finished your Morning Pack today!',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Allow each widget to optionally link to a real screen
class _WidgetSpec {
  final String title;
  final IconData icon;
  final Widget? screen;
  const _WidgetSpec(this.title, this.icon, {this.screen});
}

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
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: Colors.black87),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
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

