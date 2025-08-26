import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WaterIntakeScreen extends StatefulWidget {
  const WaterIntakeScreen({super.key});

  @override
  State<WaterIntakeScreen> createState() => _WaterIntakeScreenState();
}

class _WidgetKeys {
  static const waterGlasses = 'water_glasses';
}

class _WaterIntakeScreenState extends State<WaterIntakeScreen> {
  int _glasses = 0;

  @override
  void initState() {
    super.initState();
    _loadGlasses();
  }

  Future<void> _loadGlasses() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _glasses = prefs.getInt(_WidgetKeys.waterGlasses) ?? 0);
  }

  Future<void> _addGlass() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _glasses++);
    await prefs.setInt(_WidgetKeys.waterGlasses, _glasses);
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _glasses = 0);
    await prefs.setInt(_WidgetKeys.waterGlasses, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Water Intake')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Glasses today: $_glasses',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.water_drop),
              label: const Text('Add Glass'),
              onPressed: _addGlass,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
