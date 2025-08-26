import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AffirmationScreen extends StatelessWidget {
  const AffirmationScreen({super.key});

  static const _openers = [
    "I choose","I welcome","I trust","I honor","I embrace","I allow","I amplify",
    "I cultivate","I create","I embody","I focus on","I am grounded in","I am guided by",
    "I celebrate","I commit to","I return to","I nourish","I stand in","I feel","I practice",
    "I radiate","I grow through","I prioritize","I lead with","I breathe into","I move with",
    "I give myself","I am open to","I rise with","I choose again","I remember","I release",
    "I invite","I expand into","I lean into","I align with","I act with","I carry","I protect",
    "I show up with","I make space for","I strengthen","I refine","I welcome more","I light up",
    "I return with","I deepen"
  ];
  static const _qualities = [
    "calm","clarity","courage","joy","patience","kindness","focus","resilience","self-worth",
    "confidence","compassion","discipline","gratitude","creativity","curiosity","presence",
    "purpose","energy","balance","forgiveness","self-trust","abundance","playfulness",
    "resourcefulness","optimism","consistency","trust in timing","inner peace","boundaries",
    "self-care","momentum","hope","humility","strength","faith in myself","lightness",
    "acceptance","adaptability","persistence","love","integrity","honesty","delight","flow",
    "bravery","wisdom","grace","compassion for me"
  ];
  static const _closers = [
    "in every small step.","with each breath.","in this season.","through action today.",
    "as I learn.","even when it’s hard.","without rushing.","one choice at a time.",
    "with gratitude.","and let go of fear.","and follow through.","with a quiet mind.",
    "starting now.","in how I speak.","in how I move.","and celebrate progress."
  ];

  String _dailyAffirmation(DateTime now) {
    final dayOfYear = int.parse(DateFormat("D").format(now)); // 1..366
    int pick(int offset, int mod) => (dayOfYear + offset) % mod;
    final a = _openers[pick(3, _openers.length)];
    final b = _qualities[pick(17, _qualities.length)];
    final c = _closers[pick(29, _closers.length)];
    return "$a $b $c";
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final text = _dailyAffirmation(now);
    final prettyDate = DateFormat.yMMMMd().format(now);

    return Scaffold(
      appBar: AppBar(title: const Text("Affirmation of the Day")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(prettyDate, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Theme.of(context).colorScheme.secondaryContainer,
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      height: 1.3, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "A new affirmation appears every day automatically.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
