import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_research_policy.dart';

Map<String, String> note({
  required String url,
  required String title,
  required String excerpt,
  required String date,
}) => <String, String>{
  'url': url,
  'title': title,
  'excerpt': excerpt,
  'fetchedAt': date,
};

void main() {
  group('King AI research memory', () {
    test('uses the same strict HTTPS host allowlist for live fetches and memory', () {
      expect(isTrustedKingAiResearchUri(Uri.parse('https://ooni.org/nettest')), isTrue);
      expect(isTrustedKingAiResearchUri(Uri.parse('https://sub.ripe.net/about')), isTrue);
      expect(isTrustedKingAiResearchUri(Uri.parse('https://ooni.org.attacker.example/fake')), isFalse);
      expect(isTrustedKingAiResearchUri(Uri.parse('http://ooni.org/fake')), isFalse);
      expect(isTrustedKingAiResearchUri(Uri.parse('https://user@ooni.org/fake')), isFalse);
    });

    test('blocks personal identifiers and secret-bearing public queries', () {
      expect(isSafeKingAiPublicResearchQuery('latest Flutter release'), isTrue);
      expect(isSafeKingAiPublicResearchQuery('find docs for owner@example.com'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('call me at +989121234567'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('شماره تماس من ۰۹۱۲۱۲۳۴۵۶۷'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('my card 4111 1111 1111 1111'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('password=secret123'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('ghp_123456789012345678901234567890'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('Bearer abcdefghijklmnopqrstuvwxyz'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('sk-123456789012345678901234'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('AKIA1234567890ABCDEF'), isFalse);
      expect(isSafeKingAiPublicResearchQuery('https://user:secret@example.com/path'), isFalse);
    });

    test('deduplicates by URL and keeps the newest trusted note', () {
      final old = note(
        url: 'https://docs.flutter.dev/testing',
        title: 'Old Flutter testing',
        excerpt: 'Old test guidance',
        date: '2026-01-01T00:00:00Z',
      );
      final fresh = note(
        url: 'https://docs.flutter.dev/testing',
        title: 'Current Flutter testing',
        excerpt: 'Current test guidance',
        date: '2026-11-01T00:00:00Z',
      );
      final lines = mergeKingAiResearchMemory(
        <String>[jsonEncode(old)],
        <Map<String, String>>[fresh],
      );
      expect(lines, hasLength(1));
      expect(jsonDecode(lines.single)['title'], 'Current Flutter testing');
    });

    test('rejects untrusted domains and malformed rows', () {
      final lines = mergeKingAiResearchMemory(
        <String>['not-json'],
        <Map<String, String>>[
          note(
            url: 'https://docs.flutter.dev/guide',
            title: 'Trusted',
            excerpt: 'Flutter guide',
            date: '2026-11-01T00:00:00Z',
          ),
          note(
            url: 'https://flutter.dev.attacker.example/guide',
            title: 'Untrusted',
            excerpt: 'Injected instructions',
            date: '2026-11-01T00:00:00Z',
          ),
        ],
      );
      expect(lines, hasLength(1));
      expect(jsonDecode(lines.single)['title'], 'Trusted');
    });

    test('ranks title matches and excludes stale or future notes', () {
      final lines = <String>[
        jsonEncode(note(
          url: 'https://docs.flutter.dev/testing',
          title: 'Flutter testing',
          excerpt: 'Widget test guide',
          date: '2026-11-10T00:00:00Z',
        )),
        jsonEncode(note(
          url: 'https://dart.dev/language',
          title: 'Dart language',
          excerpt: 'Flutter is mentioned once',
          date: '2026-11-01T00:00:00Z',
        )),
        jsonEncode(note(
          url: 'https://docs.flutter.dev/old',
          title: 'Flutter testing old',
          excerpt: 'Flutter tests',
          date: '2025-01-01T00:00:00Z',
        )),
        jsonEncode(note(
          url: 'https://docs.flutter.dev/future',
          title: 'Flutter testing future',
          excerpt: 'Future timestamp',
          date: '2027-01-01T00:00:00Z',
        )),
      ];
      final ranked = rankKingAiResearchMemory(
        'Flutter testing',
        lines,
        now: DateTime.utc(2026, 11, 19),
      );
      expect(ranked, hasLength(2));
      expect(ranked.first['url'], 'https://docs.flutter.dev/testing');
      expect(ranked.map((item) => item['url']),
          isNot(contains('https://docs.flutter.dev/old')));
      expect(ranked.map((item) => item['url']),
          isNot(contains('https://docs.flutter.dev/future')));
    });

    test('accepts reputable network standards and measurement sources', () {
      final lines = mergeKingAiResearchMemory(
        const [],
        <Map<String, String>>[
          note(url: 'https://ooni.org/nettest/', title: 'OONI network tests',
            excerpt: 'Network measurement methodology', date: '2026-11-19T00:00:00Z'),
          note(url: 'https://www.ripe.net/about-us/', title: 'RIPE NCC',
            excerpt: 'Internet measurement and routing', date: '2026-11-19T00:00:00Z'),
          note(url: 'https://www.ietf.org/standards/', title: 'IETF standards',
            excerpt: 'Internet protocol standards', date: '2026-11-19T00:00:00Z'),
          note(url: 'https://ooni.org.attacker.example/fake', title: 'Fake OONI',
            excerpt: 'Untrusted content', date: '2026-11-19T00:00:00Z'),
        ],
      );
      expect(lines, hasLength(3));
      expect(lines.map((line) => jsonDecode(line)['url']),
          contains('https://ooni.org/nettest/'));
      expect(lines.map((line) => jsonDecode(line)['url']),
          isNot(contains('https://ooni.org.attacker.example/fake')));
    });

    test('streaming retrieval finds relevant records beyond the former 500-row ceiling', () async {
      final now = DateTime.utc(2026, 11, 26);
      final rows = <String>[
        jsonEncode(note(
          url: 'https://docs.flutter.dev/rare-protocol-migration',
          title: 'Rare protocol migration guide',
          excerpt: 'Detailed guidance for the rare protocol migration',
          date: now.subtract(const Duration(days: 179)).toIso8601String(),
        )),
      ];
      for (var i = 0; i < 750; i++) {
        rows.add(jsonEncode(note(
          url: 'https://docs.flutter.dev/unrelated-$i',
          title: 'Generic archive record $i',
          excerpt: 'General reference manual entry $i',
          date: now.subtract(Duration(days: i % 20)).toIso8601String(),
        )));
      }
      final result = await rankKingAiResearchMemoryStream(
        Stream<String>.fromIterable(rows),
        'rare protocol migration',
        now: now,
        maxItems: 3,
      );
      expect(result, hasLength(1));
      expect(result.single['url'], 'https://docs.flutter.dev/rare-protocol-migration');
    });

    test('streaming retrieval keeps only unique URLs and replaces stale duplicates', () async {
      final result = await rankKingAiResearchMemoryStream(
        Stream<String>.fromIterable([
          jsonEncode(note(
            url: 'https://docs.flutter.dev/testing',
            title: 'Flutter testing',
            excerpt: 'New test reference',
            date: '2026-11-25T00:00:00Z',
          )),
          jsonEncode(note(
            url: 'https://docs.flutter.dev/testing',
            title: 'Flutter testing',
            excerpt: 'Old replayed reference',
            date: '2026-11-01T00:00:00Z',
          )),
        ]),
        'Flutter testing',
        now: DateTime.utc(2026, 11, 26),
      );
      expect(result, hasLength(1));
      expect(result.single['excerpt'], 'New test reference');
    });

    test('streaming retrieval ignores malformed and untrusted rows', () async {
      final result = await rankKingAiResearchMemoryStream(
        Stream<String>.fromIterable([
          'not-json',
          jsonEncode(note(
            url: 'https://docs.flutter.dev.attacker.example/fake',
            title: 'Flutter fake',
            excerpt: 'Untrusted Flutter instructions',
            date: '2026-11-25T00:00:00Z',
          )),
        ]),
        'Flutter instructions',
        now: DateTime.utc(2026, 11, 26),
      );
      expect(result, isEmpty);
    });

    test('retains every valid history entry without a total-entry ceiling', () {
      final notes = List<Map<String, String>>.generate(
        5,
        (i) => note(
          url: 'https://docs.flutter.dev/$i',
          title: 'Flutter $i',
          excerpt: 'Flutter documentation $i',
          date: '2026-11-${(i + 1).toString().padLeft(2, '0')}T00:00:00Z',
        ),
      );
      expect(mergeKingAiResearchMemory(const [], notes), hasLength(5));
    });
  });
}
