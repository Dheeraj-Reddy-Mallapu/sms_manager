import 'package:sms_manager/src/data/local/database_helper.dart';
import 'package:sms_manager/src/data/models/sms_message.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Query intent — structured result of parsing a raw search string
// ─────────────────────────────────────────────────────────────────────────────

class QueryIntent {
  final int? startTime;
  final int? endTime;
  final List<String> senderHints; // address LIKE patterns
  final String ftsQuery;          // sanitized FTS4 MATCH string
  final String? notTerm;          // post-filter exclusion (FTS4 doesn't support NOT)
  final bool onlyUnread;
  final bool onlyStarred;

  const QueryIntent({
    this.startTime,
    this.endTime,
    this.senderHints = const [],
    this.ftsQuery = '',
    this.notTerm,
    this.onlyUnread = false,
    this.onlyStarred = false,
  });

  bool get isEmpty =>
      startTime == null &&
      endTime == null &&
      senderHints.isEmpty &&
      ftsQuery.isEmpty &&
      !onlyUnread &&
      !onlyStarred;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sender alias map — normalises brand names to known SMS sender ID patterns
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<String>> _senderAliases = {
  // Banks
  'sbi': ['SBI'],
  'hdfc': ['HDFC'],
  'icici': ['ICICI'],
  'axis': ['AXIS'],
  'kotak': ['KOTAK'],
  'indusind': ['INDUS'],
  'yes bank': ['YESBNK', 'YES'],
  'idfc': ['IDFC'],
  'rbl': ['RBL'],
  'au bank': ['AUSFIN'],
  'federal bank': ['FEDBK'],
  'citi': ['CITI'],
  'hsbc': ['HSBC'],
  'pnb': ['PNB'],
  'bob': ['BARODB', 'BARODA'],
  'canara': ['CANBNK'],
  'union bank': ['UNIONB'],
  'central bank': ['CENTBK'],
  'indian bank': ['INDBNK'],
  // Payments / Wallets
  'paytm': ['PAYTM'],
  'phonepe': ['PHONEPE', 'PhonePe'],
  'gpay': ['GPAY'],
  'google pay': ['GPAY'],
  'mobikwik': ['MOBIKW'],
  'freecharge': ['FREECHARGE'],
  // Telcos
  'jio': ['JIO', 'RJIO'],
  'airtel': ['AIRTEL'],
  'vi': ['VI', 'VODAFONE', 'IDEA'],
  'vodafone': ['VODAFONE'],
  'bsnl': ['BSNL'],
  // E-commerce
  'amazon': ['AMAZON', 'AMZNIN'],
  'flipkart': ['FLIPKT', 'FKISKU'],
  'myntra': ['MYNTRA'],
  'meesho': ['MEESHO'],
  'ajio': ['AJIO'],
  'nykaa': ['NYKAA'],
  'snapdeal': ['SNAPDL'],
  // Delivery / Logistics
  'delhivery': ['DELHIV'],
  'bluedart': ['BLUEDART'],
  'dtdc': ['DTDC'],
  'ecom express': ['ECOMEX'],
  'xpressbees': ['XPRESSBEES'],
  // Food
  'zomato': ['ZOMATO'],
  'swiggy': ['SWIGGY'],
  // Travel
  'irctc': ['IRCTCS', 'IRTCTS'],
  'makemytrip': ['MAKEMY', 'MMT'],
  'goibibo': ['GOIBIB'],
  'cleartrip': ['CLEARB'],
  'indigo': ['INDIGP'],
  'air india': ['AIRIND'],
  'spicejet': ['SPIJET'],
  'uber': ['UBERIN'],
  'ola': ['OLACAB'],
  'rapido': ['RAPIDO'],
  'redbus': ['REDBUS'],
  // Grocery
  'bigbasket': ['BIGBSK'],
  'blinkit': ['BLINKT'],
  // Health
  'apollo': ['APPLLO'],
  'practo': ['PRACTO'],
  'netmeds': ['NETMED'],
  'medplus': ['MEDPLS'],
  '1mg': ['1MG'],
  // Govt
  'uidai': ['UIDAIA'],
  'aadhaar': ['UIDAIA'],
  'income tax': ['ITATAX', 'ITAXXX'],
  'epf': ['EPFINB'],
};

List<String> _resolveSender(String token) {
  // Check multi-word aliases first
  for (final entry in _senderAliases.entries) {
    if (token == entry.key) return entry.value;
  }
  // Return token itself uppercased as a fallback (address LIKE '%TOKEN%')
  return [token.toUpperCase()];
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Query Parser
// ─────────────────────────────────────────────────────────────────────────────

class SmartQueryParser {
  static QueryIntent parse(String rawQuery) {
    String q = rawQuery.trim().toLowerCase();
    int? startTime;
    int? endTime;
    String? notTerm;
    bool onlyUnread = false;
    bool onlyStarred = false;
    final senderHints = <String>[];

    final now = DateTime.now();

    // ── 1. TEMPORAL ────────────────────────────────────────────────────────

    // "N days/weeks/months ago"
    final agoRe = RegExp(r'(\d+)\s+(day|days|week|weeks|month|months)\s+ago');
    final agoMatch = agoRe.firstMatch(q);
    if (agoMatch != null) {
      final n = int.parse(agoMatch.group(1)!);
      final unit = agoMatch.group(2)!;
      q = q.replaceFirst(agoMatch.group(0)!, ' ');
      final offset = unit.startsWith('day')
          ? Duration(days: n)
          : unit.startsWith('week')
          ? Duration(days: n * 7)
          : Duration(days: n * 30);
      final d = now.subtract(offset);
      startTime = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      endTime =
          DateTime(d.year, d.month, d.day, 23, 59, 59).millisecondsSinceEpoch;
    }

    // Common relative keywords — ordered from most specific to least
    final relativeMap = <String, int? Function()>{
      'yesterday': () {
        final d = now.subtract(const Duration(days: 1));
        startTime = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
        endTime = DateTime(d.year, d.month, d.day, 23, 59, 59)
            .millisecondsSinceEpoch;
        return null;
      },
      'today': () {
        startTime = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'this week': () {
        // Monday of current week
        final monday = now.subtract(Duration(days: now.weekday - 1));
        startTime =
            DateTime(monday.year, monday.month, monday.day).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'last week': () {
        startTime =
            now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'past week': () {
        startTime =
            now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'this month': () {
        startTime = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'last month': () {
        startTime =
            now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'past month': () {
        startTime =
            now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'this year': () {
        startTime = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
        endTime = now.millisecondsSinceEpoch;
        return null;
      },
      'last year': () {
        startTime = DateTime(now.year - 1, 1, 1).millisecondsSinceEpoch;
        endTime =
            DateTime(now.year - 1, 12, 31, 23, 59, 59).millisecondsSinceEpoch;
        return null;
      },
      'weekend': () {
        // Most recent Saturday
        final daysToSat = (now.weekday % 7 == 6)
            ? 0
            : (now.weekday == 7 ? 1 : now.weekday + 1);
        final sat = now.subtract(Duration(days: daysToSat));
        final sun = sat.add(const Duration(days: 1));
        startTime = DateTime(sat.year, sat.month, sat.day).millisecondsSinceEpoch;
        endTime =
            DateTime(sun.year, sun.month, sun.day, 23, 59, 59)
                .millisecondsSinceEpoch;
        return null;
      },
    };

    if (startTime == null) {
      for (final entry in relativeMap.entries) {
        if (q.contains(entry.key)) {
          q = q.replaceAll(entry.key, ' ');
          entry.value();
          break;
        }
      }
    }

    // Named weekdays
    const weekdays = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    if (startTime == null) {
      for (final entry in weekdays.entries) {
        if (q.contains(entry.key)) {
          q = q.replaceAll(entry.key, ' ');
          final daysBack = (now.weekday - entry.value + 7) % 7;
          final d = now.subtract(Duration(days: daysBack == 0 ? 7 : daysBack));
          startTime = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
          endTime =
              DateTime(d.year, d.month, d.day, 23, 59, 59)
                  .millisecondsSinceEpoch;
          break;
        }
      }
    }

    // Named months with optional year: "jan 2024", "march", "january 2023"
    const monthNames = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };

    if (startTime == null) {
      // "month year" pattern first
      final monthYearRe = RegExp(
        r'\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept?|october|oct|november|nov|december|dec)\s+(\d{4})\b',
      );
      final myMatch = monthYearRe.firstMatch(q);
      if (myMatch != null) {
        final month = monthNames[myMatch.group(1)!]!;
        final year = int.parse(myMatch.group(2)!);
        q = q.replaceFirst(myMatch.group(0)!, ' ');
        startTime = DateTime(year, month, 1).millisecondsSinceEpoch;
        final nextMonth = month == 12
            ? DateTime(year + 1, 1, 1)
            : DateTime(year, month + 1, 1);
        endTime =
            nextMonth
                .subtract(const Duration(milliseconds: 1))
                .millisecondsSinceEpoch;
      } else {
        // Single month name — longest match first to avoid "mar" matching in "march"
        final sortedMonths = monthNames.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final name in sortedMonths) {
          final re = RegExp(r'\b' + name + r'\b');
          if (re.hasMatch(q)) {
            q = q.replaceAll(re, ' ');
            final month = monthNames[name]!;
            // Use previous year if the month hasn't happened yet this year
            final year = month > now.month ? now.year - 1 : now.year;
            startTime = DateTime(year, month, 1).millisecondsSinceEpoch;
            final nextMonth = month == 12
                ? DateTime(year + 1, 1, 1)
                : DateTime(year, month + 1, 1);
            endTime =
                nextMonth
                    .subtract(const Duration(milliseconds: 1))
                    .millisecondsSinceEpoch;
            break;
          }
        }
      }
    }

    // ── 2. FLAGS ──────────────────────────────────────────────────────────

    if (q.contains('unread')) {
      onlyUnread = true;
      q = q.replaceAll('unread', ' ');
    }
    if (RegExp(r'\b(starred|important)\b').hasMatch(q)) {
      onlyStarred = true;
      q = q.replaceAll(RegExp(r'\b(starred|important)\b'), ' ');
    }

    // ── 3. SENDER HINTS ──────────────────────────────────────────────────

    // "from <brand>" — extract sender hint then remove "from" prefix
    final fromRe = RegExp(r'\bfrom\s+(\w+(?:\s+\w+)?)\b');
    final fromMatch = fromRe.firstMatch(q);
    if (fromMatch != null) {
      final brand = fromMatch.group(1)!.trim();
      q = q.replaceFirst(fromMatch.group(0)!, ' ');
      senderHints.addAll(_resolveSender(brand));
    }

    // Also check standalone brand names in the remaining query
    for (final entry in _senderAliases.entries) {
      if (q.contains(entry.key)) {
        // Don't remove — keep as FTS token too; just add sender hint
        senderHints.addAll(entry.value);
      }
    }

    // ── 4. NOT TERM ──────────────────────────────────────────────────────

    // "not <word>" or "-<word>"
    final notRe = RegExp(r'\bnot\s+(\w+)\b|-(\w+)');
    final notMatch = notRe.firstMatch(q);
    if (notMatch != null) {
      notTerm = notMatch.group(1) ?? notMatch.group(2);
      q = q.replaceFirst(notMatch.group(0)!, ' ');
    }

    // ── 5. BUILD FTS QUERY from remaining tokens ──────────────────────────

    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();

    String ftsQuery = '';
    if (q.isNotEmpty) {
      // Preserve quoted phrases
      final phrases = <String>[];
      q = q.replaceAllMapped(RegExp(r'"([^"]+)"'), (m) {
        phrases.add('"${m.group(1)}"');
        return ' ';
      });

      q = q.trim();

      // Detect explicit OR between words
      final hasOr = RegExp(r'\bor\b').hasMatch(q);

      // Tokenise — keep only meaningful tokens (length > 1, not stop-words)
      final stopWords = {'is', 'in', 'at', 'on', 'to', 'by', 'an', 'of', 'for', 'the', 'a'};
      final tokens = q
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && t.length > 1 && !stopWords.contains(t))
          .toList();

      final parts = <String>[...phrases];

      if (hasOr) {
        // Re-join with OR, add prefix wildcard per token
        final orTokens = <String>[];
        for (final t in tokens) {
          if (t == 'or') continue;
          orTokens.add('$t*');
        }
        parts.add(orTokens.join(' OR '));
      } else {
        // AND (implicit in FTS4 — space-separated = all must appear)
        parts.addAll(tokens.map((t) => '$t*'));
      }

      ftsQuery = parts.where((p) => p.isNotEmpty).join(' ');
    }

    return QueryIntent(
      startTime: startTime,
      endTime: endTime,
      senderHints: senderHints.toSet().toList(),
      ftsQuery: ftsQuery,
      notTerm: notTerm,
      onlyUnread: onlyUnread,
      onlyStarred: onlyStarred,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart Search Service
// ─────────────────────────────────────────────────────────────────────────────

class SmartSearchService {
  SmartSearchService._();
  static final SmartSearchService instance = SmartSearchService._();

  Future<List<SmsMessage>> search(
    String rawQuery, [
    List<String> filterChips = const [],
  ]) async {
    if (rawQuery.trim().isEmpty) return [];

    final intent = SmartQueryParser.parse(rawQuery);

    // Apply UI filter chips on top of parsed intent
    final onlyUnread = intent.onlyUnread || filterChips.contains('Unread');
    final onlyStarred = intent.onlyStarred || filterChips.contains('Starred');
    final wantsOtp = filterChips.contains('OTP');
    final wantsLink = filterChips.contains('Has Link');
    final wantsFinance = filterChips.contains('Finance');

    final db = await DatabaseHelper.instance.database;

    // ── Build WHERE conditions ─────────────────────────────────────────────
    final conditions = <String>[];
    final args = <dynamic>[];

    if (intent.startTime != null) {
      conditions.add('m.date >= ?');
      args.add(intent.startTime);
    }
    if (intent.endTime != null) {
      conditions.add('m.date <= ?');
      args.add(intent.endTime);
    }
    if (onlyUnread) conditions.add('m.read = 0');
    if (onlyStarred) conditions.add('m.isStarred = 1');

    if (wantsOtp) {
      conditions.add("(m.body LIKE '%otp%' OR m.body LIKE '%code%' OR m.body LIKE '%pin%')");
    }
    if (wantsLink) {
      conditions.add("(m.body LIKE '%http%' OR m.body LIKE '%.com/%' OR m.body LIKE '%.in/%' OR m.body LIKE '%bit.ly%')");
    }
    if (wantsFinance) {
      conditions.add("(m.body LIKE '%rs.%' OR m.body LIKE '%inr%' OR m.body LIKE '%debited%' OR m.body LIKE '%credited%' OR m.body LIKE '%a/c%')");
    }

    // Sender hints: address matches any of the hints OR body contains sender name
    if (intent.senderHints.isNotEmpty) {
      final parts = intent.senderHints
          .map((h) => "m.address LIKE '%${h.replaceAll("'", "''")}%'")
          .join(' OR ');
      conditions.add('($parts)');
    }

    final whereExtra = conditions.isNotEmpty
        ? 'AND ${conditions.join(' AND ')}'
        : '';

    List<Map<String, dynamic>> rows;

    if (intent.ftsQuery.isNotEmpty) {
      // FTS4 path — keyword + filters
      final sanitizedFts =
          intent.ftsQuery.replaceAll('"', '""'); // escape double quotes
      try {
        rows = await db.rawQuery(
          '''
          SELECT m.*
          FROM messages_fts f
          INNER JOIN messages m ON f.docid = m.id
          WHERE f.messages_fts MATCH ? $whereExtra
          ORDER BY m.date DESC
          LIMIT 150
          ''',
          [sanitizedFts, ...args],
        );
      } catch (_) {
        // FTS syntax error (e.g. user typed a partial query) — fall back to plain filter
        final fallbackConditions = List<String>.from(conditions);
        final fallbackArgs = List<dynamic>.from(args);
        final likePattern = '%${rawQuery.replaceAll("'", "''")}%';
        fallbackConditions.add("(m.body LIKE ? OR m.address LIKE ? OR m.contactName LIKE ?)");
        fallbackArgs.addAll([likePattern, likePattern, likePattern]);
        rows = await _plainQuery(fallbackConditions, fallbackArgs, db);
      }
    } else if (conditions.isNotEmpty) {
      // No keyword query — pure filter (date range / unread / sender)
      rows = await _plainQuery(conditions, args, db);
    } else {
      // Nothing parsed — return empty rather than dumping all messages
      return [];
    }

    var messages = rows.map((r) => SmsMessage.fromMap(Map<String, dynamic>.from(r))).toList();

    // ── Post-filter: NOT term (FTS4 doesn't support NOT natively) ─────────
    if (intent.notTerm != null) {
      final notLower = intent.notTerm!.toLowerCase();
      messages = messages
          .where((m) => !m.body.toLowerCase().contains(notLower))
          .toList();
    }

    return messages;
  }

  Future<List<Map<String, dynamic>>> _plainQuery(
    List<String> conditions,
    List<dynamic> args,
    dynamic db,
  ) async {
    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    return await db.rawQuery(
      '''
      SELECT m.* FROM messages m
      $whereClause
      ORDER BY m.date DESC
      LIMIT 150
      ''',
      args,
    );
  }
}
