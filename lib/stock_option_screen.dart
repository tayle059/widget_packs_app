import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'finance_api.dart';

class StockOptionScreen extends StatefulWidget {
  const StockOptionScreen({super.key});

  @override
  State<StockOptionScreen> createState() => _StockOptionScreenState();
}

class _StockOptionScreenState extends State<StockOptionScreen> {
  static const _prefKey = 'stock_tickers';
  static const _refreshInterval = Duration(minutes: 1);
  static const _searchDebounceMs = 300;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _addCtrl = TextEditingController();

  Timer? _autoRefreshTimer;
  Timer? _searchDebounce;
  bool _loadingBatch = false;            // top linear loader
  bool _firstBuild = true;

  List<String> _tickers = [];
  Map<String, StockQuote> _quotes = {};  // SYMBOL -> quote
  List<SearchResult> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _initAndRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAndRefresh() async {
    // On entering the widget, "reset" transient UI state and grab fresh quotes.
    _quotes.clear();
    _searchCtrl.clear();
    setState(() => _suggestions = []);

    await _loadTickers();     // loads (and seeds) saved list
    await _fetchQuotes();     // first batch fetch
    _startAutoRefresh();      // background refresh
  }

  Future<void> _loadTickers() async {
    final prefs = await SharedPreferences.getInstance();
    _tickers = prefs.getStringList(_prefKey) ?? [];
    if (_tickers.isEmpty) {
      _tickers = ['AAPL', 'MSFT', 'TSLA']; // seed defaults first time
      await prefs.setStringList(_prefKey, _tickers);
    }
    if (mounted) setState(() {}); // reflect list immediately
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) => _fetchQuotes(silent: true));
  }

  Future<void> _fetchQuotes({bool silent = false}) async {
    if (_tickers.isEmpty) return;

    if (!silent) setState(() => _loadingBatch = true);
    try {
      final list = await FinanceApi.fetchQuotes(_tickers);
      if (!mounted) return;
      setState(() {
        for (final q in list) {
          _quotes[q.symbol.toUpperCase()] = q;
        }
      });

      // Auto retry any rows that still have null price (try once, individually)
      final pending = _tickers.where((s) {
        final q = _quotes[s];
        return q == null || q.price == null;
      }).toList();

      if (pending.isNotEmpty) {
        for (final sym in pending) {
          try {
            final one = await FinanceApi.fetchQuotes([sym]);
            if (one.isNotEmpty && mounted) {
              setState(() {
                _quotes[sym] = one.first;
              });
            }
          } catch (_) {
            // ignore; user can tap row to retry
          }
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quote fetch failed: $e')),
        );
      }
    } finally {
      if (mounted && !silent) setState(() => _loadingBatch = false);
    }
  }

  Future<void> _saveTickers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _tickers);
  }

  Future<void> _addTicker(String sym) async {
    final s = sym.trim().toUpperCase();
    if (s.isEmpty) return;
    final valid = RegExp(r'^[A-Z.\-]{1,10}$');
    if (!valid.hasMatch(s)) {
      _snack('Ticker looks invalid');
      return;
    }
    if (_tickers.contains(s)) {
      _snack('Already on your list');
      return;
    }
    setState(() => _tickers.add(s));
    await _saveTickers();

    // Reset that row to a loading state, then fetch just this one
    setState(() => _quotes.remove(s));
    try {
      final q = await FinanceApi.fetchQuotes([s]);
      if (q.isNotEmpty && mounted) {
        setState(() => _quotes[s] = q.first);
      }
    } catch (e) {
      if (mounted) _snack('Couldn’t fetch $s: $e');
    }
  }

  Future<void> _removeTicker(String sym) async {
    setState(() {
      _tickers.remove(sym);
      _quotes.remove(sym);
    });
    await _saveTickers();
  }

  void _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _tickers.removeAt(oldIndex);
      _tickers.insert(newIndex, item);
    });
    await _saveTickers();
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- Autocomplete (Yahoo search) ----------
  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: _searchDebounceMs), () async {
      final q = text.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      try {
        final res = await FinanceApi.search(q, limit: 8);
        if (mounted) setState(() => _suggestions = res);
      } catch (_) {
        // ignore transient errors
      }
    });
  }

  void _applySuggestion(SearchResult r) {
    _addTicker(r.symbol);
    setState(() => _suggestions = []);
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // On very first build after push, ensure fresh fetch (extra safety)
    if (_firstBuild) {
      _firstBuild = false;
      // after frame, fetch again in case we navigated back to a cached widget
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchQuotes(silent: false);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Watchlist'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchQuotes(silent: false),
          ),
        ],
        bottom: _loadingBatch
            ? const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: LinearProgressIndicator(minHeight: 2),
        )
            : null,
      ),
      body: Column(
        children: [
          // Search + quick-add
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Autocomplete search
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search company or ticker (e.g., Apple or AAPL)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                      if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = _suggestions[i];
                              return ListTile(
                                dense: true,
                                title: Text('${s.symbol} • ${s.shortName}'),
                                subtitle: Text(s.exch),
                                onTap: () => _applySuggestion(s),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Quick add by exact symbol
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _addCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'AAPL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: _addTicker,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _addTicker(_addCtrl.text),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          // Watchlist
          Expanded(
            child: _tickers.isEmpty
                ? const Center(child: Text('No stocks yet. Search or add a ticker to begin.'))
                : RefreshIndicator(
              onRefresh: () => _fetchQuotes(silent: false),
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                itemCount: _tickers.length,
                onReorder: _reorder,
                buildDefaultDragHandles: false,
                itemBuilder: (context, i) {
                  final sym = _tickers[i];
                  final q = _quotes[sym];

                  final loadingRow = q == null || (q.price == null && q.source != 'None');

                  final priceStr = q?.price == null ? '—' : q!.price!.toStringAsFixed(2);
                  final changeStr = q?.changePercent == null
                      ? ''
                      : '${q!.changePercent! >= 0 ? '▲' : '▼'} ${q.changePercent!.toStringAsFixed(2)}%';
                  final changeColor = (q?.changePercent ?? 0) >= 0 ? Colors.green : Colors.red;

                  return ListTile(
                    key: ValueKey(sym),
                    tileColor: theme.colorScheme.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text('$sym ${q?.shortName != null && q!.shortName.isNotEmpty ? "• ${q.shortName}" : ""}'),
                    subtitle: Row(
                      children: [
                        if (loadingRow)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text('\$$priceStr'),
                        if (!loadingRow && changeStr.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            changeStr,
                            style: TextStyle(color: changeColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          q == null || (q.source).isEmpty ? '' : '(${q.source})',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    onTap: () async {
                      // Tap to retry this symbol only
                      try {
                        final fresh = await FinanceApi.fetchQuotes([sym]);
                        if (fresh.isNotEmpty && mounted) {
                          setState(() => _quotes[sym] = fresh.first);
                        } else if (mounted) {
                          _snack('No quote data for $sym');
                        }
                      } catch (e) {
                        if (mounted) _snack('Retry failed for $sym: $e');
                      }
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeTicker(sym),
                        ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

