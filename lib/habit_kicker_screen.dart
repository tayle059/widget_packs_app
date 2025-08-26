import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';

class HabitKickerScreen extends StatefulWidget {
  const HabitKickerScreen({super.key});

  @override
  State<HabitKickerScreen> createState() => _HabitKickerScreenState();
}

class _HabitKickerScreenState extends State<HabitKickerScreen> {
  final _controller = TextEditingController();
  final _confetti = ConfettiController(duration: const Duration(seconds: 1));

  List<_HabitItem> _items = [];
  bool _dailyReset = true; // reset “done” each day

  static const _suggested = <String>[
    'Drink water',
    'Walk 5 minutes',
    'Stretch 5 minutes',
    'Read 1 page',
    'Deep breathing',
    'Tidy your desk',
    'No sugar snack',
    'Journal 1 line',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // load items
    final raw = prefs.getString('habit_kicker_items');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => _HabitItem.fromJson(e as Map<String, dynamic>))
          .toList();
      _items = list;
    } else {
      _items = [
        _HabitItem('Drink water'),
        _HabitItem('Stretch 5 minutes'),
        _HabitItem('Write 3 gratitudes'),
      ];
    }

    // settings
    _dailyReset = prefs.getBool('habit_kicker_daily_reset') ?? true;

    // daily reset logic
    final lastIso = prefs.getString('habit_kicker_last_date');
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    if (lastIso != null) {
      final last = DateTime.tryParse(lastIso);
      if (_dailyReset && last != null) {
        final lastKey = DateTime(last.year, last.month, last.day);
        if (todayKey.difference(lastKey).inDays >= 1) {
          _items = _items.map((h) => h.copyWith(done: false)).toList();
        }
      }
    }

    await prefs.setString('habit_kicker_last_date', today.toIso8601String());
    setState(() {});
    _save(); // save defaults if fresh
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'habit_kicker_items',
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
    await prefs.setBool('habit_kicker_daily_reset', _dailyReset);
  }

  void _toggle(int i) {
    setState(() => _items[i] = _items[i].copyWith(done: !_items[i].done));
    _save();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_items.any((h) => h.title.toLowerCase() == text.toLowerCase())) {
      _controller.clear();
      return;
    }
    setState(() {
      _items.add(_HabitItem(text));
      _controller.clear();
    });
    _save();
  }

  void _remove(int i) {
    setState(() => _items.removeAt(i));
    _save();
  }

  void _addSuggested(String s) {
    if (_items.any((h) => h.title.toLowerCase() == s.toLowerCase())) return;
    setState(() => _items.add(_HabitItem(s)));
    _save();
  }

  void _completeAll() {
    if (_items.isEmpty) return;
    setState(() => _items = _items.map((h) => h.copyWith(done: true)).toList());
    _save();
    _confetti.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final total = _items.length;
    final done = _items.where((h) => h.done).length;
    final progress = total == 0 ? 0.0 : done / total;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit Kicker'),
        actions: [
          IconButton(
            tooltip: 'Complete all',
            onPressed: total == 0 ? null : _completeAll,
            icon: const Icon(Icons.emoji_events_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'toggle_reset') {
                setState(() => _dailyReset = !_dailyReset);
                _save();
              } else if (v == 'reset_today') {
                setState(() => _items = _items.map((h) => h.copyWith(done: false)).toList());
                _save();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'toggle_reset',
                checked: _dailyReset,
                child: const Text('Daily reset'),
              ),
              const PopupMenuItem(
                value: 'reset_today',
                child: Text('Reset today'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Progress bar + counter
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('$done / $total done',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('${(progress * 100).round()}%',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progress),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Suggested habits chips
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Suggestions', style: theme.textTheme.labelLarge),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _suggested.map((s) {
                      final exists = _items.any((h) => h.title.toLowerCase() == s.toLowerCase());
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(s),
                          avatar: Icon(exists ? Icons.check : Icons.add, size: 18),
                          onPressed: exists ? null : () => _addSuggested(s),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // Add habit row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Add a habit...',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _add, child: const Text('Add')),
                  ],
                ),
                const SizedBox(height: 12),

                // List
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No habits yet. Add your first!'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            return Dismissible(
                              key: ValueKey('${item.title}-$i'),
                              background: Container(color: Colors.red.withOpacity(0.2)),
                              onDismissed: (_) => _remove(i),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                tileColor: theme.colorScheme.surfaceVariant,
                                leading: Checkbox(value: item.done, onChanged: (_) => _toggle(i)),
                                title: Text(
                                  item.title,
                                  style: TextStyle(
                                    decoration: item.done ? TextDecoration.lineThrough : null,
                                    color: item.done ? Colors.grey : null,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _remove(i),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Complete All CTA (duplicate of app bar icon, nice for thumb reach)
                if (total > 0)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _completeAll,
                      icon: const Icon(Icons.celebration),
                      label: const Text('Complete all'),
                    ),
                  ),
              ],
            ),
          ),

          // Confetti overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 30,
              gravity: 0.7,
              colors: const [Colors.green, Colors.blue, Colors.purple, Colors.orange],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitItem {
  final String title;
  final bool done;
  _HabitItem(this.title, {this.done = false});
  _HabitItem copyWith({String? title, bool? done}) =>
      _HabitItem(title ?? this.title, done: done ?? this.done);
  Map<String, dynamic> toJson() => {'title': title, 'done': done};
  factory _HabitItem.fromJson(Map<String, dynamic> m) =>
      _HabitItem(m['title'] as String, done: m['done'] as bool? ?? false);
}
