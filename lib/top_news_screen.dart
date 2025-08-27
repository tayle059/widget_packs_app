import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime? _tryParseDate(dynamic v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class TopNewsScreen extends StatefulWidget {
  const TopNewsScreen({super.key});
  @override
  State<TopNewsScreen> createState() => _TopNewsScreenState();
}

class _TopNewsScreenState extends State<TopNewsScreen> {
  static const _httpTimeout = Duration(seconds: 8);
  static const _cacheTtl = Duration(minutes: 5);
  static const _maxItems = 5;

  // Source -> list of feed URLs (RSS or Atom)
  static final Map<String, List<String>> _sources = {
    'All': [
      // BBC World
      'https://feeds.bbci.co.uk/news/world/rss.xml',
      // NYT World
      'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
      // NPR
      'https://feeds.npr.org/1001/rss.xml',
      // Google News
      'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en',
    ],
    'BBC': ['https://feeds.bbci.co.uk/news/world/rss.xml'],
    'NYT': ['https://rss.nytimes.com/services/xml/rss/nyt/World.xml'],
    'NPR': ['https://feeds.npr.org/1001/rss.xml'],
    'Google News': ['https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en'],
  };



  String _selected = 'All';
  bool _loading = true;
  String? _error;
  List<_Article> _items = const [];
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenFetch();
  }

  Future<void> _loadFromCacheThenFetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _cacheKey(_selected);
    final raw = prefs.getString(cacheKey);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final savedAt = DateTime.tryParse(m['savedAt'] as String);
        final list = (m['items'] as List)
            .map((e) => _Article.fromJson(e as Map<String, dynamic>))
            .toList();
        if (savedAt != null && DateTime.now().difference(savedAt) < _cacheTtl) {
          setState(() {
            _items = list;
            _lastUpdated = savedAt;
            _loading = false;
          });
          // Kick off a silent refresh for freshness
          _fetchAndCache(silent: true);
          return;
        } else {
          setState(() {
            _items = list;
            _lastUpdated = savedAt;
          });
        }
      } catch (_) {
        // ignore cache parse errors
      }
    }
    await _fetchAndCache();
  }

  Future<void> _fetchAndCache({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final feeds = _sources[_selected]!;
      final lists = await Future.wait(
        feeds.map(
              (u) => _fetchFeed(u).timeout(
            _httpTimeout,
            onTimeout: () => const <_Article>[],
          ),
        ),
      );

      final all = lists.expand((e) => e).toList()
        ..sort((a, b) => (b.published ?? DateTime(0)).compareTo(a.published ?? DateTime(0)));

      // De-dup by title
      final seen = <String>{};
      final deduped = <_Article>[];
      for (final a in all) {
        final t = (a.title ?? '').trim();
        if (t.isEmpty || seen.contains(t)) continue;
        seen.add(t);
        deduped.add(a);
        if (deduped.length == _maxItems) break;
      }

      // If nothing loaded (timeouts / blocked), surface a friendly error
      if (deduped.isEmpty) {
        throw Exception('No headlines found (network timeout or feeds unavailable).');
      }

      final now = DateTime.now();
      setState(() {
        _items = deduped;
        _lastUpdated = now;
      });

      final prefs = await SharedPreferences.getInstance();
      final data = {
        'savedAt': now.toIso8601String(),
        'items': deduped.map((e) => e.toJson()).toList(),
      };
      await prefs.setString(_cacheKey(_selected), jsonEncode(data));
    } catch (e) {
      if (!silent) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (!silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<_Article>> _fetchFeed(String url) async {
    final res = await http
        .get(Uri.parse(url), headers: {'User-Agent': 'WidgetPacksApp/1.0 (+https://example.com)'})
        .timeout(_httpTimeout);
    if (res.statusCode != 200) return [];
    final body = utf8.decode(res.bodyBytes);

    // Try RSS
    try {
      final rss = RssFeed.parse(body);
      final items = rss.items ?? const <RssItem>[];
      return items
          .map((i) => _Article(
        title: i.title,
        link: i.link,
        source: rss.title,
        published: i.pubDate != null ? DateTime.tryParse(i.pubDate!) : null,
      ))
          .toList();
    } catch (_) {}

    // Try Atom
    try {
      final atom = AtomFeed.parse(body);
      final items = atom.items ?? const <AtomItem>[];
      return items.map((i) {
        final pub = _tryParseDate(i.published) ?? _tryParseDate(i.updated);
        final link = (i.links != null && i.links!.isNotEmpty) ? i.links!.first.href : null;
        return _Article(
          title: i.title,
          link: link,
          source: atom.title,
          published: pub,
        );
      }).toList();
    } catch (_) {}

    return [];
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.inAppBrowserView,
      webViewConfiguration: const WebViewConfiguration(enableJavaScript: true),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  String _cacheKey(String source) => 'top_news_cache::$source';

  Future<void> _onRefresh() async {
    await _fetchAndCache();
  }

  void _changeSource(String src) {
    if (_selected == src) return;
    setState(() {
      _selected = src;
    });
    _loadFromCacheThenFetch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top News'),
        actions: [
          // Source picker
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selected,
                alignment: Alignment.centerRight,
                onChanged: (v) => _changeSource(v!),
                items: _sources.keys
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAndCache),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Error: $_error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _fetchAndCache,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ))
          : RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            if (i == 0) {
              return _Header(
                source: _selected,
                lastUpdated: _lastUpdated,
              );
            }
            final a = _items[i - 1];
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String source;
  final DateTime? lastUpdated;
  const _Header({required this.source, required this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final ts = lastUpdated == null
        ? '—'
        : '${lastUpdated!.hour.toString().padLeft(2, '0')}:${lastUpdated!.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source: $source', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text('Last updated: $ts', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Article {
  final String? title;
  final String? link;
  final String? source;
  final DateTime? published;
  _Article({this.title, this.link, this.source, this.published});

  Map<String, dynamic> toJson() => {
    'title': title,
    'link': link,
    'source': source,
    'published': published?.toIso8601String(),
  };

  factory _Article.fromJson(Map<String, dynamic> m) => _Article(
    title: m['title'] as String?,
    link: m['link'] as String?,
    source: m['source'] as String?,
    published: m['published'] != null
        ? DateTime.tryParse(m['published'] as String)
        : null,
  );
}
