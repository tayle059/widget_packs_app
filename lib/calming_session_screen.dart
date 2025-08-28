import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalmingSessionScreen extends StatefulWidget {
  const CalmingSessionScreen({super.key});

  @override
  State<CalmingSessionScreen> createState() => _CalmingSessionScreenState();
}

enum BreathMode { box444, fourSevenEight }

class _CalmingSessionScreenState extends State<CalmingSessionScreen>
    with SingleTickerProviderStateMixin {
  // ===== PATTERNS =====
  BreathMode _mode = BreathMode.box444;
  bool _useCustom = false;
  int _customInhale = 4;
  int _customHold = 4;
  int _customExhale = 4;

  int get _inhale => _useCustom ? _customInhale : (_mode == BreathMode.box444 ? 4 : 4);
  int get _hold   => _useCustom ? _customHold   : (_mode == BreathMode.box444 ? 4 : 7);
  int get _exhale => _useCustom ? _customExhale : (_mode == BreathMode.box444 ? 4 : 8);

  // Saved custom presets
  List<_BreathPreset> _savedPresets = [];

  // ===== ANIMATION =====
  late final AnimationController _controller;
  late Animation<double> _breath;   // 0..1 scale (circle size)
  late Animation<double> _dimAnim;  // smooth 0.45 -> 0.10 -> 0.12 -> 0.45 (loop-friendly)

  Timer? _phaseTimer;
  String _phase = "Ready";
  bool _running = false;

  // Visual
  bool _focusMode = false; // Minimal center-dot UI

  // ===== AUDIO =====
  final AudioPlayer _bgPlayer = AudioPlayer();       // ambient loop
  final AudioPlayer _chimePlayer = AudioPlayer();    // one-shot chime
  double _volume = 0.7;
  bool _chimeEnabled = false;
  String? _currentSoundPath;                         // assets/sounds/xxx.ext
  List<_SoundItem> _availableSounds = [];            // discovered from AssetManifest
  String? _chimePath;                                // optional assets/sounds/chime.*

  // ===== SESSION TIMER =====
  int? _sessionMinutes;         // null => off
  int _sessionRemaining = 0;    // seconds
  Timer? _sessionTicker;

  // Small presets (still available inside pattern/timer sheets)
  static const _timerMaxMinutes = 30;

  // ===== PREFS KEYS =====
  static const _kPresetsKey = 'calming_custom_presets';

  @override
  void initState() {
    super.initState();

    // Global mixing context so chimes won't stop ambience
    AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain, // persistent background focus
        ),
        // iOS: playback + {mixWithOthers} is allowed
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );

    // Chime player: transient focus on Android, same iOS mix policy
    _chimePlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: _inhale + _hold + _exhale),
    );
    _buildSequence();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _running) {
        _controller.forward(from: 0); // loops; dimAnim start==end => no jump
      }
    });

    // audio defaults
    _bgPlayer.setReleaseMode(ReleaseMode.loop);
    _bgPlayer.setVolume(_volume);

    _loadSounds();
    _loadSavedPresets();
  }

  Future<void> _loadSavedPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kPresetsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = (json.decode(jsonStr) as List)
            .map((e) => _BreathPreset.fromJson(e))
            .toList();
        setState(() => _savedPresets = list);
      }
    } catch (_) {}
  }

  Future<void> _persistSavedPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _savedPresets.map((e) => e.toJson()).toList();
      await prefs.setString(_kPresetsKey, json.encode(list));
    } catch (_) {}
  }

  Future<void> _loadSounds() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);

      final all = manifestMap.keys
          .where((k) => k.startsWith('assets/sounds/'))
          .where((k) =>
      k.endsWith('.mp3') ||
          k.endsWith('.wav') ||
          k.endsWith('.m4a') ||
          k.endsWith('.ogg'))
          .toList()
        ..sort();

      _chimePath = all.firstWhere(
            (p) => p.toLowerCase().contains('chime'),
        orElse: () => '',
      );
      if (_chimePath!.isEmpty) _chimePath = null;

      _availableSounds = all
          .where((p) => p != _chimePath)
          .map((p) => _SoundItem(path: p, name: _prettyNameFromPath(p)))
          .toList();

      if (_availableSounds.isNotEmpty) {
        _currentSoundPath ??= _availableSounds.first.path;
      }

      setState(() {});
    } catch (_) {
      setState(() {
        _availableSounds = [];
        _currentSoundPath = null;
        _chimePath = null;
      });
    }
  }

  String _prettyNameFromPath(String path) {
    final file = path.split('/').last;
    final base = file.split('.').first;
    return base.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  void _buildSequence() {
    // Circle size follows inhale/hold/exhale with ease; start==end => seamless loop
    _breath = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.65, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _inhale.toDouble(),
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: _hold.toDouble(),
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.65).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _exhale.toDouble(),
      ),
    ]).animate(_controller);

    // NEW: loop-friendly dim. Start dark (end-of-exhale), brighten on inhale,
    // hover on hold, darken on exhale, and end where we started.
    _dimAnim = TweenSequence<double>([
      // Inhale: 0.45 -> 0.10 (ease-out, feels like “opening”)
      TweenSequenceItem(
        tween: Tween(begin: 0.45, end: 0.10).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: _inhale.toDouble(),
      ),
      // Hold: 0.10 -> 0.12 (tiny drift, avoids a harsh plateau)
      TweenSequenceItem(
        tween: Tween(begin: 0.10, end: 0.12).chain(CurveTween(curve: Curves.easeInOut)),
        weight: _hold.toDouble(),
      ),
      // Exhale: 0.12 -> 0.45 (ease-in, settles into darkness)
      TweenSequenceItem(
        tween: Tween(begin: 0.12, end: 0.45).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: _exhale.toDouble(),
      ),
    ]).animate(_controller);
  }

  void _applyPatternChanges() {
    final wasRunning = _running;
    _pause();
    _controller.duration = Duration(seconds: _inhale + _hold + _exhale);
    _buildSequence();
    if (wasRunning) _start();
  }

  void _start() {
    if (_running) return;
    setState(() => _running = true);
    _controller.duration = Duration(seconds: _inhale + _hold + _exhale);
    _controller.forward(from: 0);
    _schedulePhaseLabels();

    _playSelected();

    if (_sessionMinutes != null) {
      if (_sessionRemaining <= 0) {
        _sessionRemaining = _sessionMinutes! * 60;
      }
      _startSessionTicker();
    }
  }

  void _pause() {
    _controller.stop();
    _phaseTimer?.cancel();
    _sessionTicker?.cancel();
    if (mounted) {
      setState(() {
        _running = false;
        _phase = "Paused";
      });
    }
    _bgPlayer.pause();
  }

  void _reset() {
    _pause();
    _controller.value = 0;
    setState(() => _phase = "Ready");
    _sessionRemaining = _sessionMinutes != null ? _sessionMinutes! * 60 : 0;
    _stopAudio();
  }

  void _schedulePhaseLabels() {
    _phaseTimer?.cancel();

    String lastPhase = "";
    Future<void> setPhase(String p) async {
      if (lastPhase != p) {
        lastPhase = p;
        setState(() => _phase = p);
        HapticFeedback.lightImpact();
        if (_chimeEnabled && _chimePath != null) {
          try {
            await _chimePlayer.stop();
            await _chimePlayer.setReleaseMode(ReleaseMode.stop);
            await _chimePlayer.setVolume((_volume * 0.9).clamp(0.0, 1.0));
            await _chimePlayer.play(
              AssetSource(_chimePath!.replaceFirst('assets/', '')),
            );
          } catch (_) {}
        }
      }
    }

    setPhase("Inhale");
    _phaseTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      final total = _inhale + _hold + _exhale;
      final s = (_controller.value * total);

      if (s < _inhale) {
        setPhase("Inhale");
      } else if (s < _inhale + _hold) {
        setPhase("Hold");
      } else {
        setPhase("Exhale");
      }

      if (!_running) t.cancel();
      // No setState(): visuals are driven by the controller animations.
    });
  }

  // ===== SESSION TIMER helpers =====
  void _setSessionMinutes(int? minutes) {
    _sessionTicker?.cancel();
    setState(() {
      _sessionMinutes = minutes;
      _sessionRemaining = minutes != null ? minutes * 60 : 0;
    });
    if (_running && minutes != null) _startSessionTicker();
  }

  void _startSessionTicker() {
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_running) return;
      if (_sessionRemaining <= 0) {
        t.cancel();
        _onSessionComplete();
      } else {
        setState(() => _sessionRemaining--);
      }
    });
  }

  Future<void> _onSessionComplete() async {
    await _fadeOutAudio(const Duration(milliseconds: 900));
    await _playEndChime();

    setState(() {
      _running = false;
      _phase = "Complete";
    });
    _controller.stop();
    _phaseTimer?.cancel();
    _sessionTicker?.cancel();

    if (mounted) {
      // ignore: use_build_context_synchronously
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18 + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 42, color: Colors.green),
                const SizedBox(height: 10),
                Text(
                  "Session complete",
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  "Nice work. Ready for another round?",
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _reset();
                          _start();
                        },
                        child: const Text("Restart"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Close"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _fadeOutAudio(Duration duration) async {
    try {
      final steps = 8;
      final startVol = _volume.clamp(0.0, 1.0);
      for (var i = steps; i >= 0; i--) {
        final v = startVol * (i / steps);
        await _bgPlayer.setVolume(v);
        await Future.delayed(duration ~/ steps);
      }
      await _bgPlayer.stop();
      await _bgPlayer.setVolume(_volume); // restore user volume
    } catch (_) {}
  }

  Future<void> _playEndChime() async {
    if (_chimePath == null) return;
    try {
      await _chimePlayer.stop();
      await _chimePlayer.setReleaseMode(ReleaseMode.stop);
      await _chimePlayer.setVolume((_volume * 0.9).clamp(0.0, 1.0));
      await _chimePlayer.play(
        AssetSource(_chimePath!.replaceFirst('assets/', '')),
      );
    } catch (_) {}
  }

  // ===== AUDIO HELPERS =====
  Future<void> _playSelected() async {
    if (_currentSoundPath == null) return;
    try {
      await _bgPlayer.stop();
      await _bgPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgPlayer.setVolume(_volume);
      await _bgPlayer.play(
        AssetSource(_currentSoundPath!.replaceFirst('assets/', '')),
      );
    } catch (_) {}
  }

  Future<void> _stopAudio() async {
    try {
      await _bgPlayer.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _sessionTicker?.cancel();
    _controller.dispose();
    _bgPlayer.dispose();
    _chimePlayer.dispose();
    super.dispose();
  }

  // ===== Helpers for visual/countdown =====
  int _secondsLeftInPhase() {
    final total = _inhale + _hold + _exhale;
    final s = (_controller.value * total);
    if (s < _inhale) return (_inhale - s).ceil();
    if (s < _inhale + _hold) return (_inhale + _hold - s).ceil();
    return (_inhale + _hold + _exhale - s).ceil();
  }

  double _phasePortion() {
    final total = _inhale + _hold + _exhale;
    final s = (_controller.value * total);
    if (s < _inhale) return (s / _inhale).clamp(0, 1);
    if (s < _inhale + _hold) return ((s - _inhale) / _hold).clamp(0, 1);
    return ((s - _inhale - _hold) / _exhale).clamp(0, 1);
  }

  String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  // ======= Compact Sheets (Pattern & Timer) =======

  Future<void> _openPatternSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        BreathMode localMode = _mode;
        bool useCustom = _useCustom;
        int inh = _customInhale, hld = _customHold, exh = _customExhale;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply() {
              setState(() {
                _useCustom = useCustom;
                _mode = localMode;
                _customInhale = inh;
                _customHold = hld;
                _customExhale = exh;
              });
              _applyPatternChanges();
              Navigator.pop(ctx);
            }

            Future<void> savePreset() async {
              final nameController = TextEditingController();
              final result = await showDialog<String?>(
                context: context,
                builder: (dctx) => AlertDialog(
                  title: const Text('Save preset'),
                  content: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Preset name',
                      hintText: 'e.g. Relax 5-7-8',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () {
                        final n = nameController.text.trim();
                        Navigator.pop(dctx, n.isEmpty ? null : n);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              if (result == null) return;
              final p = _BreathPreset(name: result, inhale: inh, hold: hld, exhale: exh);
              setState(() {
                _savedPresets.removeWhere((e) => e.name.toLowerCase() == result.toLowerCase());
                _savedPresets.add(p);
              });
              await _persistSavedPresets();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved preset: ${p.name}')),
                );
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16 + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 42, height: 5, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(999))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text("Breath pattern", style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Apply',
                        onPressed: apply,
                        icon: const Icon(Icons.check_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text("4-4-4"),
                        selected: !useCustom && localMode == BreathMode.box444,
                        onSelected: (_) => setLocal(() { useCustom = false; localMode = BreathMode.box444; }),
                      ),
                      ChoiceChip(
                        label: const Text("4-7-8"),
                        selected: !useCustom && localMode == BreathMode.fourSevenEight,
                        onSelected: (_) => setLocal(() { useCustom = false; localMode = BreathMode.fourSevenEight; }),
                      ),
                      ChoiceChip(
                        label: const Text("Custom"),
                        selected: useCustom,
                        onSelected: (_) => setLocal(() { useCustom = true; }),
                      ),
                    ],
                  ),
                  if (useCustom) ...[
                    const SizedBox(height: 10),
                    _PhaseSliderCompact(
                      label: "Inhale",
                      value: inh.toDouble(),
                      min: 1,
                      max: 12,
                      onChanged: (v) => setLocal(() => inh = v.round()),
                    ),
                    _PhaseSliderCompact(
                      label: "Hold",
                      value: hld.toDouble(),
                      min: 0,
                      max: 12,
                      onChanged: (v) => setLocal(() => hld = v.round()),
                    ),
                    _PhaseSliderCompact(
                      label: "Exhale",
                      value: exh.toDouble(),
                      min: 1,
                      max: 12,
                      onChanged: (v) => setLocal(() => exh = v.round()),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        onPressed: savePreset,
                        label: const Text('Save preset'),
                      ),
                    ),
                  ],
                  if (_savedPresets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Saved", style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _savedPresets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final p = _savedPresets[i];
                          return InputChip(
                            label: Text("${p.name} (${p.inhale}-${p.hold}-${p.exhale})"),
                            onPressed: () => setLocal(() { useCustom = true; inh = p.inhale; hld = p.hold; exh = p.exhale; }),
                            onDeleted: () async {
                              setState(() => _savedPresets.removeAt(i));
                              await _persistSavedPresets();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openTimerSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        int local = _sessionMinutes ?? 0;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply() {
              _setSessionMinutes(local == 0 ? null : local);
              Navigator.pop(ctx);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16 + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 42, height: 5, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(999))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text("Session timer", style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Apply',
                        onPressed: apply,
                        icon: const Icon(Icons.check_circle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text("Off"),
                      Expanded(
                        child: Slider(
                          value: local.toDouble(),
                          onChanged: (v) => setLocal(() => local = v.round()),
                          min: 0,
                          max: _timerMaxMinutes.toDouble(),
                          divisions: _timerMaxMinutes,
                          label: local == 0 ? "Off" : "$local min",
                        ),
                      ),
                      Text("${_timerMaxMinutes}m"),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      local == 0 ? "Timer off" : "Selected: $local min",
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final ringColor = _phase == "Inhale"
        ? theme.colorScheme.primary
        : (_phase == "Hold"
        ? theme.colorScheme.tertiary
        : theme.colorScheme.secondary);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Calming Session"),
        actions: [
          // Show session countdown inline when active
          if (_sessionMinutes != null && _sessionRemaining > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(
                  _mmss(_sessionRemaining),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Pattern',
            icon: const Icon(Icons.tune),
            onPressed: _openPatternSheet,
          ),
          IconButton(
            tooltip: 'Timer',
            icon: const Icon(Icons.timer_outlined),
            onPressed: _openTimerSheet,
          ),
          // Focus Mode toggle
          IconButton(
            tooltip: _focusMode ? 'Disable Focus Mode' : 'Enable Focus Mode',
            icon: Icon(_focusMode ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _focusMode = !_focusMode),
          ),
        ],
      ),
      // Smooth background driven by the controller/dimAnim
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final bg = Color.lerp(
            theme.colorScheme.background,
            Colors.black,
            _dimAnim.value.clamp(0.0, 0.6),
          )!;
          return Container(color: bg, child: child);
        },
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // ===== AUDIO UI (kept compact) =====
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.spa_outlined),
                          const SizedBox(width: 8),
                          Text("Sound", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Text("Chime"),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: _chimeEnabled,
                            onChanged: (v) => setState(() => _chimeEnabled = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_availableSounds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text("Add audio files to assets/sounds/ and hot-restart."),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _currentSoundPath,
                          items: _availableSounds
                              .map((s) => DropdownMenuItem<String>(
                            value: s.path,
                            child: Text(s.name),
                          ))
                              .toList(),
                          onChanged: (v) async {
                            setState(() => _currentSoundPath = v);
                            await _playSelected();
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: "Ambience",
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _volume,
                              onChanged: (v) async {
                                setState(() => _volume = v);
                                await _bgPlayer.setVolume(v);
                              },
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              label: "Vol ${(_volume * 100).round()}%",
                            ),
                          ),
                          IconButton(
                            tooltip: 'Play',
                            onPressed: _availableSounds.isEmpty ? null : _playSelected,
                            icon: const Icon(Icons.play_arrow),
                          ),
                          IconButton(
                            tooltip: 'Stop',
                            onPressed: _stopAudio,
                            icon: const Icon(Icons.stop),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ===== BREATHING VISUAL =====
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_breath, _controller]),
                    builder: (_, __) {
                      final size = 260.0 * _breath.value;
                      final cyc = _controller.value; // 0..1 of whole cycle
                      final secsLeft = _secondsLeftInPhase();
                      final phasePortion = _phasePortion();

                      return SizedBox(
                        width: size,
                        height: size,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Bloom / petal-like glow (subtle)
                            Opacity(
                              opacity: _focusMode ? 0.25 : 0.45,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      ringColor.withOpacity(0.25),
                                      ringColor.withOpacity(0.05),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.1, 0.6, 1.0],
                                  ),
                                ),
                              ),
                            ),

                            // Ring + pacer dot
                            CustomPaint(
                              size: Size.square(size),
                              painter: _BreathPainter(
                                progress: cyc,
                                ringColor: ringColor,
                                baseColor: theme.colorScheme.secondaryContainer
                                    .withOpacity(_focusMode ? 0.25 : 0.5),
                                focusMode: _focusMode,
                              ),
                            ),

                            // Center content
                            if (_focusMode)
                            // Minimal dot
                              Container(
                                width: size * 0.08,
                                height: size * 0.08,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ringColor.withOpacity(0.85),
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                      color: ringColor.withOpacity(0.6),
                                    ),
                                  ],
                                ),
                              )
                            else
                            // Phase + countdown + per-phase progress + (optional) session remaining
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _phase,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${secsLeft}s",
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 6,
                                      value: phasePortion,
                                      color: ringColor,
                                      backgroundColor: ringColor.withOpacity(0.15),
                                    ),
                                  ),
                                  if (_sessionMinutes != null) ...[
                                    const SizedBox(height: 8),
                                    Opacity(
                                      opacity: 0.9,
                                      child: Text(
                                        "Session ${_mmss(_sessionRemaining)}",
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
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

class _BreathPainter extends CustomPainter {
  final double progress; // 0..1 over whole cycle
  final Color ringColor;
  final Color baseColor;
  final bool focusMode;

  _BreathPainter({
    required this.progress,
    required this.ringColor,
    required this.baseColor,
    required this.focusMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.045;

    // Base ring
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = baseColor;
    canvas.drawArc(
      Rect.fromLTWH(stroke, stroke, size.width - 2 * stroke, size.height - 2 * stroke),
      -math.pi / 2,
      2 * math.pi,
      false,
      basePaint,
    );

    // Active arc (0..progress)
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = ringColor.withOpacity(0.95);
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromLTWH(stroke, stroke, size.width - 2 * stroke, size.height - 2 * stroke),
      -math.pi / 2,
      sweep,
      false,
      activePaint,
    );

    // Pacer dot
    final r = (size.width - 2 * stroke) / 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final angle = -math.pi / 2 + sweep;
    final dx = cx + r * math.cos(angle);
    final dy = cy + r * math.sin(angle);

    final dotRadius = stroke * (focusMode ? 0.9 : 0.7);
    final dotPaint = Paint()..color = ringColor;
    canvas.drawCircle(Offset(dx, dy), dotRadius, dotPaint);

    // Dot glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          ringColor.withOpacity(0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(dx, dy), radius: dotRadius * 3));
    canvas.drawCircle(Offset(dx, dy), dotRadius * 3, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BreathPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.focusMode != focusMode;
  }
}

class _SoundItem {
  final String path;
  final String name;
  _SoundItem({required this.path, required this.name});
}

class _BreathPreset {
  final String name;
  final int inhale;
  final int hold;
  final int exhale;

  _BreathPreset({
    required this.name,
    required this.inhale,
    required this.hold,
    required this.exhale,
  });

  factory _BreathPreset.fromJson(Map<String, dynamic> j) => _BreathPreset(
    name: j['name'] as String,
    inhale: j['inhale'] as int,
    hold: j['hold'] as int,
    exhale: j['exhale'] as int,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'inhale': inhale,
    'hold': hold,
    'exhale': exhale,
  };
}

class _PhaseSliderCompact extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _PhaseSliderCompact({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 12,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: theme.textTheme.bodyMedium)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).round(),
              label: "${value.round()}s",
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text("${value.round()}s", textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
