import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:url_launcher/url_launcher.dart';

class TopNewsScreen extends StatefulWidget {
  const TopNewsScreen({super.key});
  @override
  State<TopNewsScreen> createState() => _TopNewsScreenState();
}

class _TopNewsScreenState extends State<TopNewsScreen> {
  bool _loading = true;
  String? _error;
  List<_Article> _items = const [];

  static const _feeds = <String>[
    'https://feeds.bbci.co.uk/news/world/rss.xml',
    'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
    'https://www.reuters.com/world/us/rss',
    'https://www.npr.org/rss/rss.php?id=1001',
    'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en',
    'https://apnews.com/hub/ap-top-news?output=rss',
  ];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; _items = const []; });
    try {
      final lists = await Future.wait(_feeds.map(_fetchFeed));
      final all = lists.expand((e) => e).toList()
        ..sort((a, b) => (b.published ?? DateTime(0)).compareTo(a.published ?? DateTime(0)));

      // de-dupe by title, keep top 3
      final seen = <String>{};
      final deduped = <_Article>[];
      for (final a in all) {
        final t = (a.title ?? '').trim();
        if (t.isEmpty || seen.contains(t)) continue;
        seen.add(t);
        deduped.add(a);
        if (deduped.length == 3) break;
      }

      setState(() => _items = deduped);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<List<_Article>> _fetchFeed(String url) async {
    final res = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'WidgetPacksApp/1.0 (+https://example.com)'
    });
    if (res.statusCode != 200) return [];
    final body = utf8.decode(res.bodyBytes);

    // RSS
    try {
      final rss = RssFeed.parse(body);
      final items = rss.items ?? const <RssItem>[];
      return items.map((i) => _Article(
        title: i.title,
        link: i.link,
        source: rss.title,
        published: i.pubDate != null ? DateTime.tryParse(i.pubDate!) : null,
      )).toList();
    } catch (_) {}

    // Atom
    try {
      final atom = AtomFeed.parse(body);
      final items = atom.items ?? const <AtomItem>[];
      return items.map((i) => _Article(
        title: i.title,
        link: i.links?.isNotEmpty == true ? i.links!.first.href : null,
        source: atom.title,
        published: i.published ?? i.updated,
      )).toList();
    } catch (_) {}

    return [];
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top News'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $_error', textAlign: TextAlign.center),
                ))
              : _items.isEmpty
                  ? const Center(child: Text('No headlines found'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final a = _items[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: theme.colorScheme.surfaceVariant,
                          title: Text(a.title ?? '—'),
                          subtitle: a.source == null ? null : Text(a.source!),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _open(a.link),
                        );
                      },
                    ),
    );
  }
}

class _Article {
  final String? title;
  final String? link;
  final String? source;
  final DateTime? published;
  _Article({this.title, this.link, this.source, this.published});
}
