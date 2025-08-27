import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class GetUpReminderScreen extends StatefulWidget {
  const GetUpReminderScreen({super.key});

  @override
  State<GetUpReminderScreen> createState() => _GetUpReminderScreenState();
}

class _GetUpReminderScreenState extends State<GetUpReminderScreen> {
  final _notifier = FlutterLocalNotificationsPlugin();
  Timer? _timer;
  int _minutes = 30;
  String _message = "⏰ Time to get up and stretch!";
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifier.initialize(settings);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _minutes), (_) {
      _showNotification();
    });
    setState(() => _active = true);
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() => _active = false);
  }

  Future<void> _showNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifier.show(0, 'Get Up Reminder', _message, details);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Get Up Reminder")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButton<int>(
              value: _minutes,
              onChanged: (v) => setState(() => _minutes = v!),
              items: const [15, 30, 45, 60]
                  .map((m) => DropdownMenuItem(value: m, child: Text("$m minutes")))
                  .toList(),
            ),
            TextField(
              decoration: const InputDecoration(labelText: "Custom message"),
              onChanged: (v) => _message = v,
            ),
            const SizedBox(height: 20),
            _active
                ? ElevatedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text("Stop Reminders"),
              onPressed: _stopTimer,
            )
                : ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text("Start Reminders"),
              onPressed: _startTimer,
            ),
          ],
        ),
      ),
    );
  }
}
