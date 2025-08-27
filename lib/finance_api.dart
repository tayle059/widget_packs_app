import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StockQuote {
  final String symbol;
  final String shortName; // company name (may be empty)
  final double? price;
  final double? changePercent; // day change %
  final String currency;
  final String source; // "Yahoo" or "Stooq"

  StockQuote({
    required this.symbol,
    required this.shortName,
    required this.price,
    required this.changePercent,
    required this.currency,
    required this.source,
  });
}

class SearchResult {
  final String symbol;
  final String shortName;
  final String exch; // e.g., NASDAQ, NYSE
  SearchResult({required this.symbol, required this.shortName, required this.exch});
}

class FinanceApi {
  static const _ua = 'Mozilla/5.0 (WidgetPacksApp)';
  static const _quoteBase = 'https://query1.finance.yahoo.com/v7/finance/quote';
  static const _searchBase = 'https://query2.finance.yahoo.com/v1/finance/search';
  // ADD this helper inside FinanceApi:
  static List<String> _stooqVariants(String symbol) {
    // Stooq likes lowercase, dash instead of dot for classes, and often ".us" for US stocks.
    final s = symbol.toLowerCase();
    final withDash = s.replaceAll('.', '-'); // BRK.B -> brk-b
    // Try a few combinations commonly used by Stooq:
    return [
      '$withDash.us',
      '$s.us',
      withDash, // no market suffix
      s,
    ];
  }

  /// Primary: Yahoo Finance (multi-symbol).
  static Future<List<StockQuote>> _fetchQuotesYahoo(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    final uri = Uri.parse('$_quoteBase?symbols=${symbols.join(",")}');
    final res = await http.get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Yahoo HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['quoteResponse']?['result'] as List? ?? []);
    return results.map((m) {
      final mm = m as Map<String, dynamic>;
      return StockQuote(
        symbol: (mm['symbol'] ?? '') as String,
        shortName: (mm['shortName'] ?? '') as String,
        price: (mm['regularMarketPrice'] as num?)?.toDouble(),
        changePercent: (mm['regularMarketChangePercent'] as num?)?.toDouble(),
        currency: (mm['currency'] ?? '') as String,
        source: 'Yahoo',
      );
    }).toList();
  }

  /// Per-symbol fallback: Stooq CSV (free, no key). We try SYMBOL.us for US tickers.
  /// Returns null if not found.
  static Future<StockQuote?> _fetchQuoteStooq(String symbol) async {
    for (final variant in _stooqVariants(symbol)) {
      final url = 'https://stooq.com/q/l/?s=$variant&f=sd2t2ohlcvn&h&e=csv';
      try {
        final res = await http
            .get(Uri.parse(url), headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;

        final lines = const LineSplitter().convert(res.body);
        if (lines.length < 2) continue;

        final header = lines.first.split(',');
        final row = lines[1].split(',');

        // 'N/D' means not available; try next variant
        if (row.isEmpty || row.any((c) => c.trim().toUpperCase() == 'N/D')) {
          continue;
        }

        final map = <String, String>{};
        for (var i = 0; i < header.length && i < row.length; i++) {
          map[header[i]] = row[i];
        }

        final close = double.tryParse(map['Close'] ?? '');
        final open = double.tryParse(map['Open'] ?? '');
        double? pct;
        if (close != null && open != null && open != 0) {
          pct = ((close - open) / open) * 100;
        }

        return StockQuote(
          symbol: (map['Symbol'] ?? symbol).toUpperCase(),
          shortName: (map['Name'] ?? '').trim(),
          price: close,
          changePercent: pct,
          currency: 'USD', // Stooq CSV doesn’t include currency; assume USD for US listings
          source: 'Stooq',
        );
      } catch (_) {
        // try next variant
      }
    }
    return null;
  }

  /// Public: fetch quotes for many symbols with Yahoo -> Stooq fallback.
  static Future<List<StockQuote>> fetchQuotes(List<String> symbols) async {
    final up = symbols.map((s) => s.toUpperCase()).toList();

    // Try Yahoo first (may fail on emulator networks)
    List<StockQuote> fromYahoo = [];
    try {
      fromYahoo = await _fetchQuotesYahoo(up);
    } catch (_) {
      // ignore, we’ll fill with fallbacks
    }

    // Index Yahoo results by symbol
    final bySym = {for (final q in fromYahoo) q.symbol.toUpperCase(): q};

    // For any missing symbols (or where price is null), try Stooq
    final results = <StockQuote>[];
    for (final s in up) {
      final q = bySym[s];
      if (q != null && q.price != null) {
        results.add(q);
        continue;
      }
      final alt = await _fetchQuoteStooq(s);
      if (alt != null) {
        results.add(alt);
      } else {
        // As last resort, return a placeholder so UI shows the row
        results.add(StockQuote(
          symbol: s,
          shortName: '',
          price: null,
          changePercent: null,
          currency: '',
          source: q == null ? 'None' : q.source,
        ));
      }
    }
    return results;
  }

  /// Search via Yahoo (best free option for autocomplete).
  static Future<List<SearchResult>> search(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse('$_searchBase?q=${Uri.encodeQueryComponent(query)}&quotesCount=$limit&newsCount=0');
    final res = await http.get(uri, headers: {'User-Agent': _ua, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final quotes = (data['quotes'] as List? ?? []);
    return quotes.map((q) {
      final mm = q as Map<String, dynamic>;
      return SearchResult(
        symbol: (mm['symbol'] ?? '') as String,
        shortName: (mm['shortname'] ?? mm['longname'] ?? mm['symbol'] ?? '') as String,
        exch: (mm['exchDisp'] ?? '') as String,
      );
    }).toList();
  }
}
