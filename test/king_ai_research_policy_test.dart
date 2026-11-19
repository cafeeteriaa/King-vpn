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

    test('bounds retained history', () {
      final notes = List<Map<String, String>>.generate(
        5,
        (i) => note(
          url: 'https://docs.flutter.dev/$i',
          title: 'Flutter $i',
          excerpt: 'Flutter documentation $i',
          date: '2026-11-${(i + 1).toString().padLeft(2, '0')}T00:00:00Z',
        ),
      );
      expect(mergeKingAiResearchMemory(const [], notes, maxEntries: 3),
          hasLength(3));
    });
  });
}
