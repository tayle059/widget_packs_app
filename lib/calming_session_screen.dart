import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CalmingSessionScreen extends StatefulWidget {
  const CalmingSessionScreen({super.key});

  @override
  State<CalmingSessionScreen> createState() => _CalmingSessionScreenState();
}

enum BreathMode { box444, fourSevenEight }

class _CalmingSessionScreenState extends State<CalmingSessionScreen>
    with SingleTickerProviderStateMixin {
  BreathMode _mode = BreathMode.box444;

  // Durations (seconds) for each mode
  int get _inhale => _mode == BreathMode.box444 ? 4 : 4;
  int get _hold   => _mode == BreathMode.box444 ? 4 : 7;
  int get _exhale => _mode == BreathMode.box444 ? 4 : 8;

  late final AnimationController _controller;
  late Animation<double> _breath; // 0..1 scale
  Timer? _phaseTimer;
  String _phase = "Ready";
  bool _running = false;

  // background “dim” factor (0 normal → 1 darkest). We’ll ease it on Exhale.
  double _dim = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: _inhale + _hold + _exhale),
    );
    _buildSequence();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _running) {
        _controller.forward(from: 0);
      }
    });
  }

  void _buildSequence() {
    _breath = TweenSequence<double>([
      // Inhale: small -> big
      TweenSequenceItem(
        tween: Tween(begin: 0.65, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _inhale.toDouble(),
      ),
      // Hold: stay big
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: _hold.toDouble(),
      ),
      // Exhale: big -> small
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.65).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _exhale.toDouble(),
      ),
    ]).animate(_controller);
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _controller.duration = Duration(seconds: _inhale + _hold + _exhale);
    _controller.forward(from: 0);
    _schedulePhaseLabels();
  }

  void _pause() {
    setState(() => _running = false);
    _controller.stop();
    _phaseTimer?.cancel();
    setState(() => _phase = "Paused");
  }

  void _reset() {
    _pause();
    _controller.value = 0;
    setState(() {
      _phase = "Ready";
      _dim = 0;
    });
  }

  void _changeMode(BreathMode m) {
    final wasRunning = _running;
    _pause();
    setState(() => _mode = m);
    _buildSequence();
    if (wasRunning) _start();
  }

  void _schedulePhaseLabels() {
    _phaseTimer?.cancel();

    // fire haptic + label when crossing boundaries
    String lastPhase = "";
    void setPhase(String p) {
      if (lastPhase != p) {
        lastPhase = p;
        setState(() => _phase = p);
        HapticFeedback.lightImpact(); // haptic on phase change
      }
    }

    setPhase("Inhale");
    _phaseTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final total = _inhale + _hold + _exhale;
      final s = (_controller.value * total);

      // Compute phase
      if (s < _inhale) {
        setPhase("Inhale");
        _dim = 0.0;
      } else if (s < _inhale + _hold) {
        setPhase("Hold");
        _dim = 0.1;
      } else {
        setPhase("Exhale");
        // darken background smoothly during exhale
        final exhaleProgress = (s - (_inhale + _hold)) / _exhale; // 0..1
        _dim = 0.1 + 0.35 * exhaleProgress; // up to ~0.45
      }

      if (!_running) t.cancel();
      setState(() {}); // repaint background dim
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = Color.lerp(
      theme.colorScheme.background,
      Colors.black,
      _dim.clamp(0.0, 0.6),
    )!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Calming Session"),
        actions: [
          PopupMenuButton<BreathMode>(
            icon: const Icon(Icons.settings_suggest),
            initialValue: _mode,
            onSelected: _changeMode,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: BreathMode.box444,
                child: Text("4-4-4 (box breathing)"),
              ),
              PopupMenuItem(
                value: BreathMode.fourSevenEight,
                child: Text("4-7-8"),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: bg,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Text(
                _phase == "Ready"
                    ? (_mode == BreathMode.box444 ? "4-4-4 box breathing" : "4-7-8 breathing")
                    : _phase,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _mode == BreathMode.box444
                    ? "Inhale 4s • Hold 4s • Exhale 4s"
                    : "Inhale 4s • Hold 7s • Exhale 8s",
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _breath,
                    builder: (_, __) {
                      final size = 220.0 * _breath.value;
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.secondaryContainer,
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 28,
                              spreadRadius: 2,
                              color: theme.colorScheme.secondaryContainer.withOpacity(0.6),
                            )
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _phase,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _running ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Start"),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _running ? _pause : null,
                    icon: const Icon(Icons.pause),
                    label: const Text("Pause"),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Reset"),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
