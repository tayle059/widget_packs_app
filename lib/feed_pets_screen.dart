import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedPetsScreen extends StatefulWidget {
  const FeedPetsScreen({super.key});

  @override
  State<FeedPetsScreen> createState() => _FeedPetsScreenState();
}

class _FeedPetsScreenState extends State<FeedPetsScreen> {
  // Keys for persistence
  static const _kDateKey = 'feed_pets:last_date';
  static const _kFoodKey = 'feed_pets:food';
  static const _kWaterKey = 'feed_pets:water';
  static const _kLitterKey = 'feed_pets:litter';
  static const _kStreakKey = 'feed_pets:streak';

  bool _loading = true;

  bool _food = false;
  bool _water = false;
  bool _litter = false;
  int _streak = 0;
  DateTime _today = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    final lastDateStr = prefs.getString(_kDateKey);
    final lastDate = lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;

    bool food = prefs.getBool(_kFoodKey) ?? false;
    bool water = prefs.getBool(_kWaterKey) ?? false;
    bool litter = prefs.getBool(_kLitterKey) ?? false;
    int streak = prefs.getInt(_kStreakKey) ?? 0;

    final today = _dateOnly(DateTime.now());

    // If we crossed days, reset tasks and update streak if yesterday was complete
    if (lastDate == null || _dateOnly(lastDate) != today) {
      // If last day was exactly yesterday AND all tasks were completed, increment streak
      if (lastDate != null &&
          _dateOnly(lastDate).difference(today).inDays == -1 &&
          (food && water && litter)) {
        streak += 1;
      } else if (lastDate != null &&
          _dateOnly(lastDate).difference(today).inDays != -1) {
        // Break streak if we skipped a day (or more) and didn't complete all
        streak = (food && water && litter) ? streak : 0;
      }

      // New day → reset tasks
      food = false;
      water = false;
      litter = false;

      await prefs.setString(_kDateKey, today.toIso8601String());
      await prefs.setBool(_kFoodKey, food);
      await prefs.setBool(_kWaterKey, water);
      await prefs.setBool(_kLitterKey, litter);
      await prefs.setInt(_kStreakKey, streak);
    }

    setState(() {
      _today = today;
      _food = food;
      _water = water;
      _litter = litter;
      _streak = streak;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDateKey, _today.toIso8601String());
    await prefs.setBool(_kFoodKey, _food);
    await prefs.setBool(_kWaterKey, _water);
    await prefs.setBool(_kLitterKey, _litter);
  }

  void _toggle(String which, bool value) {
    setState(() {
      if (which == 'food') _food = value;
      if (which == 'water') _water = value;
      if (which == 'litter') _litter = value;
    });
    _save();
  }

  Future<void> _markAllDone() async {
    setState(() {
      _food = true;
      _water = true;
      _litter = true;
    });
    await _save();
  }

  Future<void> _resetToday() async {
    setState(() {
      _food = false;
      _water = false;
      _litter = false;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feed the Pets')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final allDone = _food && _water && _litter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed the Pets'),
        actions: [
          IconButton(
            tooltip: 'Reset today',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetToday,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Responsive header — no overflow thanks to Wrap
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.start,
              children: [
                _Badge(
                  icon: Icons.pets,
                  label: 'Streak',
                  value: '$_streak',
                ),
                _Badge(
                  icon: Icons.today,
                  label: 'Today',
                  value:
                  '${_today.month}/${_today.day}/${_today.year.toString().substring(2)}',
                ),
                if (!allDone)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FilledButton.icon(
                      onPressed: _markAllDone,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Mark all done'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Tasks
            _TaskTile(
              color: const Color(0xFFFFE2D6),
              icon: Icons.restaurant,
              title: 'Food',
              value: _food,
              onChanged: (v) => _toggle('food', v),
            ),
            const SizedBox(height: 10),
            _TaskTile(
              color: const Color(0xFFE2F3F4),
              icon: Icons.water_drop,
              title: 'Fresh Water',
              value: _water,
              onChanged: (v) => _toggle('water', v),
            ),
            const SizedBox(height: 10),
            _TaskTile(
              color: const Color(0xFFEDE3FF),
              icon: Icons.cleaning_services_outlined,
              title: 'Litter / Cleanup',
              value: _litter,
              onChanged: (v) => _toggle('litter', v),
            ),

            const Spacer(),

            // Congrats card
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: allDone ? 1 : 0.0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.celebration),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Great job! Pets are all set for today 🐾'),
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

class _TaskTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TaskTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: CheckboxListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        controlAffinity: ListTileControlAffinity.leading,
        secondary: Icon(icon, color: Colors.black87),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Badge({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(value, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
