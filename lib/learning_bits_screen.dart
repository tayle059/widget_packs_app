import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;
import 'package:shared_preferences/shared_preferences.dart';

class LearningBitsScreen extends StatefulWidget {
  const LearningBitsScreen({super.key});

  @override
  State<LearningBitsScreen> createState() => _LearningBitsScreenState();
}

class _LearningBitsScreenState extends State<LearningBitsScreen> {
  // Pref keys
  static const _kHistory = 'learning_bits:history';     // list<json> of {_date, id}
  static const _kBookmarks = 'learning_bits:bookmarks'; // json-encoded list<String>
  static const _kStreak = 'learning_bits:streak';       // int
  static const _kLastSeenDate = 'learning_bits:last_seen_date'; // yyyy-mm-dd
  static const _kDoneToday = 'learning_bits:done_today'; // bool

  // Loaded from assets
  List<_Bit> _allBits = [];
  Set<String> _categories = {'All'};

  // UI state
  bool _loading = true;
  String _search = '';
  String _category = 'All';
  int _index = 0; // current index within filtered list

  // Persistence state
  List<_Seen> _history = []; // last 14 days
  Set<String> _bookmarks = {};
  int _streak = 0;
  bool _doneToday = false;

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  }

  List<_Bit> get _filtered {
    final q = _search.trim().toLowerCase();
    return _allBits.where((b) {
      final matchesCat = (_category == 'All') || (b.category == _category);
      final matchesText = q.isEmpty ||
          b.title.toLowerCase().contains(q) ||
          b.body.toLowerCase().contains(q);
      return matchesCat && matchesText;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    setState(() => _loading = true);
    await _loadBitsFromAssets();
    await _loadPrefs();
    _ensureTodaySelection();
    setState(() => _loading = false);
  }

  Future<void> _loadBitsFromAssets() async {
    final raw = await rootBundle.loadString('assets/learning_bits.json');
    final list = (jsonDecode(raw) as List)
        .map((e) => _Bit.fromJson(e as Map<String, dynamic>))
        .toList();
    _allBits = list;
    _categories = {'All', ..._allBits.map((b) => b.category).toSet()};
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // history
    final hRaw = prefs.getString(_kHistory);
    if (hRaw != null) {
      _history = (jsonDecode(hRaw) as List)
          .map((e) => _Seen.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // bookmarks
    final bRaw = prefs.getString(_kBookmarks);
    if (bRaw != null) {
      _bookmarks = Set<String>.from(jsonDecode(bRaw) as List);
    }

    _streak = prefs.getInt(_kStreak) ?? 0;
    _doneToday = prefs.getBool(_kDoneToday) ?? false;

    // auto-handle streak rollover when day changes
    final lastDate = prefs.getString(_kLastSeenDate);
    final today = _todayKey;
    if (lastDate != today) {
      // If last seen was exactly yesterday and doneYesterday == true, the streak was already counted then.
      // We reset doneToday flag for a new day.
      _doneToday = false;
      await prefs.setString(_kLastSeenDate, today);
      await prefs.setBool(_kDoneToday, _doneToday);
    }
  }

  void _ensureTodaySelection() {
    // Choose today’s suggested bit (based on date hash), but clamp to current filter
    final daily = _dailyIndex();
    final dailyBit = _allBits[daily];

    final list = _filtered;
    if (list.isEmpty) {
      _index = 0;
      return;
    }

    final idxInFiltered = list.indexWhere((b) => b.id == dailyBit.id);
    _index = idxInFiltered >= 0 ? idxInFiltered : 0;

    // Record it as seen today (does not mark 'done', it just remembers what we opened)
    _recordSeen(list[_index]);
  }

  int _dailyIndex() {
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    return seed % _allBits.length;
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHistory, jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBookmarks, jsonEncode(_bookmarks.toList()));
  }

  Future<void> _saveStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStreak, _streak);
  }

  Future<void> _saveDoneToday(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    _doneToday = v;
    await prefs.setBool(_kDoneToday, v);
    await prefs.setString(_kLastSeenDate, _todayKey);
  }

  void _recordSeen(_Bit bit) {
    final today = _todayKey;
    final idx = _history.indexWhere((s) => s.date == today);
    final seen = _Seen(date: today, id: bit.id);
    if (idx >= 0) {
      _history[idx] = seen;
    } else {
      _history.insert(0, seen);
    }
    if (_history.length > 14) _history = _history.take(14).toList();
    _saveHistory();
  }

  void _next() {
    final list = _filtered;
    if (list.isEmpty) return;
    setState(() {
      _index = (_index + 1) % list.length;
      _recordSeen(list[_index]);
    });
  }

  void _prev() {
    final list = _filtered;
    if (list.isEmpty) return;
    setState(() {
      _index = (_index - 1) < 0 ? list.length - 1 : _index - 1;
      _recordSeen(list[_index]);
    });
  }

  void _toggleBookmark(String id) {
    setState(() {
      if (_bookmarks.contains(id)) {
        _bookmarks.remove(id);
      } else {
        _bookmarks.add(id);
      }
    });
    _saveBookmarks();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  // Mark “Done Today” and handle streak logic:
  // - If not done yet today: mark done + increment streak.
  // - If already done: do nothing.
  Future<void> _markDoneToday() async {
    if (_doneToday) return;
    setState(() => _streak += 1);
    await _saveStreak();
    await _saveDoneToday(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Learning Bits')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final list = _filtered;
    final bit = list.isEmpty ? null : list[_index.clamp(0, (list.length - 1).clamp(0, 1 << 30))];
    final isBookmarked = bit != null && _bookmarks.contains(bit.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Bits'),
        actions: [
          // Done today / streak
          if (bit != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _doneToday ? null : _markDoneToday,
                icon: const Icon(Icons.check_circle),
                label: Text(_doneToday ? 'Done • $_streak' : 'Mark done • $_streak'),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Filter row
            Row(
              children: [
                // Category dropdown
                DropdownButton<String>(
                  value: _category,
                  onChanged: (v) {
                    setState(() {
                      _category = v ?? 'All';
                      _ensureTodaySelection();
                    });
                  },
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                ),
                const SizedBox(width: 12),
                // Search field
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (bit == null)
              const Expanded(child: Center(child: Text('No results. Try another category or search.')))
            else
              Expanded(
                child: Column(
                  children: [
                    // Card with current bit
                    Material(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(bit.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(bit.category, style: theme.textTheme.labelMedium),
                            const SizedBox(height: 10),
                            Text(bit.body,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Controls
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _prev,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Prev'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
                          icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                          onPressed: () => _toggleBookmark(bit.id),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy),
                          onPressed: () => _copy('${bit.title}\n${bit.body}'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _next,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Tabs: Recent / Bookmarks
                    Expanded(
                      child: DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(tabs: [
                              Tab(text: 'Recent'),
                              Tab(text: 'Bookmarks'),
                            ]),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _history.isEmpty
                                      ? const Center(child: Text('No recent items yet'))
                                      : ListView.builder(
                                    padding: const EdgeInsets.only(top: 8),
                                    itemCount: _history.length,
                                    itemBuilder: (_, i) {
                                      final s = _history[i];
                                      final b = _allBits.firstWhere(
                                            (x) => x.id == s.id,
                                        orElse: () => _allBits.first,
                                      );
                                      return ListTile(
                                        title: Text(b.title),
                                        subtitle: Text('${b.category} • ${s.date}'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.copy),
                                          onPressed: () => _copy('${b.title}\n${b.body}'),
                                        ),
                                        onTap: () {
                                          final idx = _filtered.indexWhere((x) => x.id == b.id);
                                          if (idx >= 0) setState(() => _index = idx);
                                        },
                                      );
                                    },
                                  ),
                                  _bookmarks.isEmpty
                                      ? const Center(child: Text('No bookmarks yet'))
                                      : ListView(
                                    padding: const EdgeInsets.only(top: 8),
                                    children: _bookmarks.map((id) {
                                      final b = _allBits.firstWhere(
                                            (x) => x.id == id,
                                        orElse: () => _allBits.first,
                                      );
                                      return ListTile(
                                        title: Text(b.title),
                                        subtitle: Text('${b.category} • ${b.body}',
                                            maxLines: 2, overflow: TextOverflow.ellipsis),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.bookmark_remove),
                                          onPressed: () => _toggleBookmark(id),
                                        ),
                                        onTap: () {
                                          final idx = _filtered.indexWhere((x) => x.id == b.id);
                                          if (idx >= 0) setState(() => _index = idx);
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

// Models

class _Bit {
  final String id;
  final String category;
  final String title;
  final String body;

  const _Bit({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
  });

  factory _Bit.fromJson(Map<String, dynamic> m) => _Bit(
    id: m['id'] as String,
    category: m['category'] as String,
    title: m['title'] as String,
    body: m['body'] as String,
  );
}

class _Seen {
  final String date; // yyyy-mm-dd
  final String id;
  const _Seen({required this.date, required this.id});

  Map<String, dynamic> toJson() => {'date': date, 'id': id};
  factory _Seen.fromJson(Map<String, dynamic> m) => _Seen(
    date: m['date'] as String,
    id: m['id'] as String,
  );
}
