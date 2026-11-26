import 'dart:convert';

const Set<String> _kingAiResearchHosts = <String>{
  'developer.android.com',
  'source.android.com',
  'developers.google.com',
  'docs.flutter.dev',
  'api.flutter.dev',
  'dart.dev',
  'pub.dev',
  'kotlinlang.org',
  'docs.gradle.org',
  'github.com',
  'huggingface.co',
  'ooni.org',
  'ripe.net',
  'apnic.net',
  'ietf.org',
  'rfc-editor.org',
  'iana.org',
  'cloudflare.com',
};

bool isTrustedKingAiResearchUri(Uri uri) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase();
  return _kingAiResearchHosts.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );
}

/// Prevent private identifiers from being sent to public web search.
/// This is deliberately conservative: uncertain queries stay local.
bool isSafeKingAiPublicResearchQuery(String prompt) {
  final sensitivePatterns = <RegExp>[
    RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
    RegExp(r'(?<![A-Za-z0-9])(?:\+?\d[\d\s().-]{7,}\d|[۰-۹][۰-۹\s().-]{7,}[۰-۹])(?![A-Za-z0-9])'),
    RegExp(r'(?:\d[ -]?){13,19}'),
    RegExp(r'(خیابان|کوچه|پلاک|واحد|آدرس دقیق|street address|apartment number)', caseSensitive: false),
    RegExp(r'(رمز|پسورد|کلمه عبور|توکن|کلید خصوصی|شماره کارت|شماره حساب|حساب بانکی|کد ملی|اطلاعات پزشکی|password|api.?key|access.?token|private.?key|credit.?card|bank account)', caseSensitive: false),
    RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'),
    RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/-]{16,}', caseSensitive: false),
    RegExp(r'sk-[A-Za-z0-9_-]{20,}'),
    RegExp(r'xox[baprs]-[A-Za-z0-9-]{10,}'),
    RegExp(r'AKIA[A-Z0-9]{16}'),
    RegExp(r'AIza[0-9A-Za-z_-]{30,}'),
    RegExp(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'),
    RegExp(r'https?://[^/\s:@]+:[^@\s]+@'),
  ];
  return !sensitivePatterns.any((pattern) => pattern.hasMatch(prompt));
}

bool _trustedKingAiResearchNote(Map<String, String> note) {
  final uri = Uri.tryParse(note['url'] ?? '');
  return uri != null && isTrustedKingAiResearchUri(uri);
}

/// Merge research notes by canonical URL, discard malformed/untrusted entries,
/// and keep a bounded JSONL history. Newer validated notes replace old copies.
List<String> mergeKingAiResearchMemory(
  List<String> existingLines,
  List<Map<String, String>> incoming, {
  int maxEntries = 200,
}) {
  final byUrl = <String, Map<String, String>>{};
  for (final line in existingLines) {
    try {
      final raw = jsonDecode(line);
      if (raw is! Map) continue;
      final note = raw.map((key, value) =>
          MapEntry(key.toString(), value.toString()));
      if (!_trustedKingAiResearchNote(note)) continue;
      final title = note['title']?.trim() ?? '';
      final excerpt = note['excerpt'] ?? '';
      final fetchedAt = DateTime.tryParse(note['fetchedAt'] ?? '');
      if (title.isEmpty || fetchedAt == null || excerpt.isEmpty) continue;
      note['excerpt'] = excerpt.substring(0, excerpt.length.clamp(0, 2600).toInt());
      byUrl[note['url']!] = note;
    } catch (_) {
      // Corrupt lines are ignored; they never become model context.
    }
  }
  for (final source in incoming) {
    final note = Map<String, String>.from(source);
    if (!_trustedKingAiResearchNote(note)) continue;
    final title = note['title']?.trim() ?? '';
    final excerpt = note['excerpt'] ?? '';
    final fetchedAt = DateTime.tryParse(note['fetchedAt'] ?? '');
    if (title.isEmpty || fetchedAt == null || excerpt.isEmpty) continue;
    note['title'] = title;
    note['excerpt'] = excerpt.substring(0, excerpt.length.clamp(0, 2600).toInt());
    byUrl[note['url']!] = note;
  }
  final entries = byUrl.values.toList()
    ..sort((a, b) => DateTime.parse(b['fetchedAt']!)
        .compareTo(DateTime.parse(a['fetchedAt']!)));
  final bounded = entries.take(maxEntries.clamp(1, 500).toInt()).toList();
  return bounded.map(jsonEncode).toList();
}


/// Validate one persisted research record without loading or merging the full
/// history. This is shared by append-only storage and streaming retrieval.
bool isValidKingAiResearchNote(Map<String, String> note) {
  if (!_trustedKingAiResearchNote(note)) return false;
  final title = note['title']?.trim() ?? '';
  final excerpt = note['excerpt'] ?? '';
  final fetchedAt = DateTime.tryParse(note['fetchedAt'] ?? '');
  return title.isNotEmpty && excerpt.isNotEmpty && fetchedAt != null;
}

/// Rank an arbitrarily long JSONL stream while retaining only the best
/// [maxItems] unique URLs in memory. The history itself is never capped or
/// materialized as a List. Newer duplicates replace older copies.
Future<List<Map<String, String>>> rankKingAiResearchMemoryStream(
  Stream<String> lines,
  String query, {
  DateTime? now,
  int maxItems = 3,
}) async {
  final current = now ?? DateTime.now().toUtc();
  final words = query.toLowerCase()
      .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
      .where((word) => word.length > 3)
      .toSet();
  if (words.isEmpty) return const <Map<String, String>>[];
  final limit = maxItems < 1 ? 1 : maxItems;
  final ranked = <({double score, Map<String, String> note})>[];

  await for (final line in lines) {
    try {
      final raw = jsonDecode(line);
      if (raw is! Map) continue;
      final note = raw.map((key, value) =>
          MapEntry(key.toString(), value.toString()));
      if (!isValidKingAiResearchNote(note)) continue;
      final fetchedAt = DateTime.parse(note['fetchedAt']!).toUtc();
      final age = current.difference(fetchedAt);
      if (age.isNegative || age > const Duration(days: 180)) continue;
      final title = note['title']!.toLowerCase();
      final excerpt = note['excerpt']!.toLowerCase();
      final titleHits = words.where(title.contains).length;
      final bodyHits = words.where(excerpt.contains).length;
      if (titleHits + bodyHits == 0) continue;
      final freshness = 1.0 - (age.inDays / 180.0);
      final score = titleHits * 3.0 + bodyHits + freshness;
      final url = note['url']!;
      ranked.removeWhere((entry) => entry.note['url'] == url);
      ranked.add((score: score, note: note));
      ranked.sort((a, b) => b.score.compareTo(a.score));
      if (ranked.length > limit) ranked.removeRange(limit, ranked.length);
    } catch (_) {
      // Corrupt or hostile rows are skipped; they never enter model context.
    }
  }
  return ranked.map((entry) => entry.note).toList(growable: false);
}

/// Retrieve only fresh, official-domain notes. Title matches weigh more than
/// body matches; recency breaks ties so stale documentation does not dominate.
List<Map<String, String>> rankKingAiResearchMemory(
  String query,
  List<String> lines, {
  DateTime? now,
  int maxItems = 3,
}) {
  final current = now ?? DateTime.now().toUtc();
  final words = query.toLowerCase()
      .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
      .where((word) => word.length > 3)
      .toSet();
  if (words.isEmpty) return const <Map<String, String>>[];
  final ranked = <({double score, Map<String, String> note})>[];
  for (final line in lines) {
    try {
      final raw = jsonDecode(line);
      if (raw is! Map) continue;
      final note = raw.map((key, value) =>
          MapEntry(key.toString(), value.toString()));
      if (!_trustedKingAiResearchNote(note)) continue;
      final fetchedAt = DateTime.tryParse(note['fetchedAt'] ?? '');
      if (fetchedAt == null) continue;
      final age = current.difference(fetchedAt.toUtc());
      if (age.isNegative || age > const Duration(days: 180)) continue;
      final title = (note['title'] ?? '').toLowerCase();
      final excerpt = (note['excerpt'] ?? '').toLowerCase();
      final titleHits = words.where(title.contains).length;
      final bodyHits = words.where(excerpt.contains).length;
      if (titleHits + bodyHits == 0) continue;
      final freshness = 1.0 - (age.inDays / 180.0);
      final score = titleHits * 3.0 + bodyHits + freshness;
      ranked.add((score: score, note: note));
    } catch (_) {
      // Ignore malformed local-memory rows.
    }
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return ranked.take(maxItems.clamp(1, 10).toInt())
      .map((item) => item.note)
      .toList();
}
