import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WellnessToolkitScreen extends StatefulWidget {
  const WellnessToolkitScreen({super.key});

  @override
  State<WellnessToolkitScreen> createState() => _WellnessToolkitScreenState();
}

class _WellnessToolkitScreenState extends State<WellnessToolkitScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // ---- Keys
  static const _kJournalList = 'wellness:journal_list'; // list<json>
  static const _kMoodList = 'wellness:mood_list';       // list<json>
  static const _kGroundingMapPrefix = 'wellness:grounding:'; // + yyyy-mm-dd

  // ---- Journal state (today)
  final _stressCtrl = TextEditingController();
  final _gratCtrl = TextEditingController();
  List<_JournalEntry> _journalHistory = [];

  // ---- Mood state (today + history)
  String? _todayMood; // 'happy' | 'neutral' | 'sad'
  List<_MoodEntry> _moodHistory = [];

  // ---- Grounding (today counters)
  // Targets 5-4-3-2-1
  static const _targets = {
    'see': 5,
    'touch': 4,
    'hear': 3,
    'smell': 2,
    'taste': 1,
  };
  Map<String, int> _grounding = {'see': 0, 'touch': 0, 'hear': 0, 'smell': 0, 'taste': 0};

  bool _loading = true;
  String get _todayKey => _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    _stressCtrl.dispose();
    _gratCtrl.dispose();
    super.dispose();
  }

  // ----------------- Load / Save -----------------

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    // Journal history
    final jraw = prefs.getString(_kJournalList);
    if (jraw != null) {
      final list = (jsonDecode(jraw) as List)
          .map((e) => _JournalEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _journalHistory = _latestN(list, 7);
      // Pre-fill today's fields if entry exists
      final today = _journalHistory.where((e) => e.date == _todayKey).toList();
      if (today.isNotEmpty) {
        _stressCtrl.text = today.first.stress ?? '';
        _gratCtrl.text = today.first.gratitude ?? '';
      }
    }

    // Mood history
    final mraw = prefs.getString(_kMoodList);
    if (mraw != null) {
      final list = (jsonDecode(mraw) as List)
          .map((e) => _MoodEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _moodHistory = _latestN(list, 7);
      final today = _moodHistory.where((e) => e.date == _todayKey).toList();
      _todayMood = today.isNotEmpty ? today.first.mood : null;
    }

    // Grounding (today)
    final graw = prefs.getString('$_kGroundingMapPrefix$_todayKey');
    if (graw != null) {
      final m = jsonDecode(graw) as Map<String, dynamic>;
      _grounding = {
        'see': (m['see'] ?? 0) as int,
        'touch': (m['touch'] ?? 0) as int,
        'hear': (m['hear'] ?? 0) as int,
        'smell': (m['smell'] ?? 0) as int,
        'taste': (m['taste'] ?? 0) as int,
      };
    }

    setState(() => _loading = false);
  }

  Future<void> _saveJournal() async {
    final prefs = await SharedPreferences.getInstance();
    final jraw = prefs.getString(_kJournalList);
    List<_JournalEntry> list = [];
    if (jraw != null) {
      list = (jsonDecode(jraw) as List)
          .map((e) => _JournalEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // Upsert today's entry
    final idx = list.indexWhere((e) => e.date == _todayKey);
    final entry = _JournalEntry(date: _todayKey, stress: _stressCtrl.text.trim(), gratitude: _gratCtrl.text.trim());
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    // Keep last 30 for storage economy
    list.sort((a, b) => b.date.compareTo(a.date));
    if (list.length > 30) list = list.take(30).toList();

    await prefs.setString(_kJournalList, jsonEncode(list.map((e) => e.toJson()).toList()));
    setState(() {
      _journalHistory = _latestN(list, 7);
    });
    _snack('Saved today’s journal.');
  }

  Future<void> _setMood(String mood) async {
    final prefs = await SharedPreferences.getInstance();
    final mraw = prefs.getString(_kMoodList);
    List<_MoodEntry> list = [];
    if (mraw != null) {
      list = (jsonDecode(mraw) as List)
          .map((e) => _MoodEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final idx = list.indexWhere((e) => e.date == _todayKey);
    final entry = _MoodEntry(date: _todayKey, mood: mood);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    if (list.length > 60) list = list.take(60).toList();

    await prefs.setString(_kMoodList, jsonEncode(list.map((e) => e.toJson()).toList()));
    setState(() {
      _todayMood = mood;
      _moodHistory = _latestN(list, 7);
    });
  }

  Future<void> _saveGrounding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kGroundingMapPrefix$_todayKey', jsonEncode(_grounding));
  }

  // ----------------- Helpers -----------------

  static List<T> _latestN<T extends _Dated>(List<T> list, int n) {
    final copy = [...list]..sort((a, b) => b.date.compareTo(a.date));
    return copy.take(n).toList();
  }

  static String _dateOnly(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wellness Toolkit')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wellness Toolkit'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Journal'),
            Tab(text: 'Grounding'),
            Tab(text: 'Mood'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _journalTab(),
          _groundingTab(),
          _moodTab(),
        ],
      ),
    );
  }

  // ---- Tab 1: Stress & Gratitude Journal ----
  Widget _journalTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Today • $_todayKey', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        _LabeledBox(
          label: 'What stressed you today?',
          child: TextField(
            controller: _stressCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Write a sentence or two…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _LabeledBox(
          label: 'What are you grateful for?',
          child: TextField(
            controller: _gratCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'One small thing counts!',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _saveJournal,
              icon: const Icon(Icons.save),
              label: const Text('Save today'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () {
                _stressCtrl.clear();
                _gratCtrl.clear();
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
            )
          ],
        ),
        const SizedBox(height: 18),
        Text('Recent entries', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_journalHistory.isEmpty)
          const Text('No history yet.')
        else
          ..._journalHistory.map((e) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.date, style: theme.textTheme.labelLarge),
                      if ((e.stress ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Stress: ${e.stress}')
                      ],
                      if ((e.gratitude ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Gratitude: ${e.gratitude}')
                      ],
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  // ---- Tab 2: Sensory Grounding 5-4-3-2-1 ----
  Widget _groundingTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _GroundRow(
            label: '5 things you can SEE',
            keyName: 'see',
            value: _grounding['see'] ?? 0,
            max: _targets['see']!,
            onChanged: (v) => _updateGround('see', v),
          ),
          const SizedBox(height: 10),
          _GroundRow(
            label: '4 things you can TOUCH',
            keyName: 'touch',
            value: _grounding['touch'] ?? 0,
            max: _targets['touch']!,
            onChanged: (v) => _updateGround('touch', v),
          ),
          const SizedBox(height: 10),
          _GroundRow(
            label: '3 things you can HEAR',
            keyName: 'hear',
            value: _grounding['hear'] ?? 0,
            max: _targets['hear']!,
            onChanged: (v) => _updateGround('hear', v),
          ),
          const SizedBox(height: 10),
          _GroundRow(
            label: '2 things you can SMELL',
            keyName: 'smell',
            value: _grounding['smell'] ?? 0,
            max: _targets['smell']!,
            onChanged: (v) => _updateGround('smell', v),
          ),
          const SizedBox(height: 10),
          _GroundRow(
            label: '1 thing you can TASTE',
            keyName: 'taste',
            value: _grounding['taste'] ?? 0,
            max: _targets['taste']!,
            onChanged: (v) => _updateGround('taste', v),
          ),
          const Spacer(),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _resetGroundToday,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset today'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saveGrounding,
                icon: const Icon(Icons.check),
                label: const Text('Save progress'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _updateGround(String key, int v) {
    final max = _targets[key]!;
    setState(() {
      _grounding[key] = v.clamp(0, max);
    });
    _saveGrounding();
  }

  Future<void> _resetGroundToday() async {
    setState(() {
      _grounding = {'see': 0, 'touch': 0, 'hear': 0, 'smell': 0, 'taste': 0};
    });
    await _saveGrounding();
  }

  // ---- Tab 3: Mood Check-in ----
  Widget _moodTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('How are you feeling today?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MoodButton('😊', 'happy', _todayMood, _setMood),
            _MoodButton('😐', 'neutral', _todayMood, _setMood),
            _MoodButton('😞', 'sad', _todayMood, _setMood),
          ],
        ),
        const SizedBox(height: 16),
        if (_todayMood != null)
          Center(child: Text('Logged: $_todayMood on $_todayKey')),
        const SizedBox(height: 18),
        Text('Last 7 days', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_moodHistory.isEmpty)
          const Text('No mood history yet.')
        else
          ..._moodHistory.map(
            (e) => ListTile(
              leading: Text(_emojiFor(e.mood), style: const TextStyle(fontSize: 22)),
              title: Text(e.date),
              subtitle: Text(e.mood),
            ),
          ),
      ],
    );
  }

  // ----------------- Small widgets -----------------

  static String _emojiFor(String mood) {
    switch (mood) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😞';
      default:
        return '😐';
    }
  }
}

class _LabeledBox extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledBox({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _GroundRow extends StatelessWidget {
  final String label;
  final String keyName;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _GroundRow({
    required this.label,
    required this.keyName,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Minus',
              onPressed: () => onChanged(value - 1),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$value / $max', style: theme.textTheme.titleMedium),
            IconButton(
              tooltip: 'Plus',
              onPressed: () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

abstract class _Dated {
  String get date;
}

class _JournalEntry implements _Dated {
  @override
  final String date; // yyyy-mm-dd
  final String? stress;
  final String? gratitude;
  _JournalEntry({required this.date, this.stress, this.gratitude});

  Map<String, dynamic> toJson() => {'date': date, 'stress': stress, 'gratitude': gratitude};

  factory _JournalEntry.fromJson(Map<String, dynamic> m) => _JournalEntry(
        date: m['date'] as String,
        stress: m['stress'] as String?,
        gratitude: m['gratitude'] as String?,
      );
}

class _MoodEntry implements _Dated {
  @override
  final String date; // yyyy-mm-dd
  final String mood; // happy | neutral | sad
  _MoodEntry({required this.date, required this.mood});

  Map<String, dynamic> toJson() => {'date': date, 'mood': mood};

  factory _MoodEntry.fromJson(Map<String, dynamic> m) =>
      _MoodEntry(date: m['date'] as String, mood: m['mood'] as String);
}

class _MoodButton extends StatelessWidget {
  final String emoji;
  final String mood;
  final String? currentMood;
  final Function(String) onSelect;

  const _MoodButton(this.emoji, this.mood, this.currentMood, this.onSelect, {super.key});

  @override
  Widget build(BuildContext context) {
    final isSelected = currentMood == mood;
    return GestureDetector(
      onTap: () => onSelect(mood),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}
