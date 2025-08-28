import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
RouteObserver<ModalRoute<void>>();

class AffirmationScreen extends StatefulWidget {
  const AffirmationScreen({super.key});

  @override
  State<AffirmationScreen> createState() => _AffirmationScreenState();
}

class _AffirmationScreenState extends State<AffirmationScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  // Dynamically loaded from AssetManifest
  List<String> _photos = [];

  static const _affirmations = <String>[
    "I choose progress over perfection.",
    "I am allowed to take up space and time.",
    "I trust myself to figure things out.",
    "Small steps compound into big results.",
    "I release what I can’t control.",
    "My pace is valid; my path is mine.",
    "I treat myself with patience and care.",
    "Today, I’ll focus on one good thing.",
    "I have everything I need to start.",
    "I am worthy of rest and joy.",
    "I’m learning, growing, and evolving.",
    "I honor my energy and listen to my body.",
    "I am resilient; I adapt and recover.",
    "I show up for myself today.",
    "I celebrate tiny wins—they add up.",
  ];

  final _rand = Random();
  int? _photoIndex; // null until photos load
  late int _quoteIndex;

  late final AnimationController _fade;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fade, curve: Curves.easeInOut);

    _quoteIndex = _rand.nextInt(_affirmations.length);
    _loadPhotos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _fade.dispose();
    super.dispose();
  }

  @override
  void didPush() => _randomizeOnOpen();
  @override
  void didPopNext() => _randomizeOnOpen();

  void _randomizeOnOpen() {
    _quoteIndex = _rand.nextInt(_affirmations.length);
    if (_photos.isNotEmpty) {
      _photoIndex = _rand.nextInt(_photos.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _precache(_photoIndex!);
      });
    }
    _fade.forward(from: 0);
    setState(() {});
  }

  Future<void> _loadPhotos() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);

      final images = manifestMap.keys
          .where((k) => k.startsWith('assets/nature/'))
          .where((k) =>
      k.endsWith('.jpg') ||
          k.endsWith('.jpeg') ||
          k.endsWith('.png') ||
          k.endsWith('.webp'))
          .toList();

      images.shuffle(_rand);

      if (!mounted) return;
      setState(() {
        _photos = images;
        _photoIndex = _photos.isNotEmpty ? _rand.nextInt(_photos.length) : null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_photoIndex != null) _precache(_photoIndex!);
        _fade.forward(from: 0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photos = [];
        _photoIndex = null;
      });
      _fade.forward(from: 0);
    }
  }

  void _precache(int index) {
    if (!mounted || index < 0 || index >= _photos.length) return;
    precacheImage(Image.asset(_photos[index]).image, context);
  }

  /// 🔘 One-button action: new random photo + new random quote
  Future<void> _nextAffirmation() async {
    if (_photos.isEmpty && _affirmations.isEmpty) return;
    await _fade.reverse();

    setState(() {
      // New photo index
      if (_photos.isNotEmpty) {
        var nextPhoto = _photoIndex ?? 0;
        if (_photos.length > 1) {
          while (nextPhoto == _photoIndex) {
            nextPhoto = _rand.nextInt(_photos.length);
          }
        }
        _photoIndex = nextPhoto;
      }

      // New quote index
      var nextQuote = _quoteIndex;
      if (_affirmations.length > 1) {
        while (nextQuote == _quoteIndex) {
          nextQuote = _rand.nextInt(_affirmations.length);
        }
      }
      _quoteIndex = nextQuote;
    });

    if (_photoIndex != null) _precache(_photoIndex!);
    _fade.forward();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const textColor = Colors.white;
    final overlayColor = scheme.primary.withOpacity(0.35); // matches button

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Affirmation'),
        actions: [
          IconButton(
            tooltip: 'Affirmation',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _nextAffirmation,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background (image if available; gradient fallback otherwise)
          if (_photoIndex != null && _photoIndex! < _photos.length)
            AnimatedBuilder(
              animation: _fadeAnim,
              builder: (context, child) => Opacity(
                opacity: _fadeAnim.value,
                child: child,
              ),
              child: Image.asset(
                _photos[_photoIndex!],
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

          // Soft overlay gradient for legibility
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black54, Colors.transparent, Colors.black54],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
              child: Column(
                children: [
                  const Spacer(),

                  // Quote with semi-transparent background (matches button color)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: Container(
                      key: ValueKey(_quoteIndex),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: overlayColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _affirmations[_quoteIndex],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          shadows: [
                            Shadow(
                              blurRadius: 10,
                              color: Colors.black54,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Single big Affirmation button
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.primary.withOpacity(0.92),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Affirmation'),
                          onPressed: _nextAffirmation,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
