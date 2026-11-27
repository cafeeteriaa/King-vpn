import 'package:flutter_test/flutter_test.dart';
import '../lib/king_resource_intelligence.dart';

void main() {
  group('KingResourceIntelligence', () {
    test('national mode prioritizes domestic public sources', () {
      final ordered = KingResourceIntelligence.orderSources(
        const <String>[
          'https://raw.githubusercontent.com/example/configs/main/list.txt',
          'https://example.ir/configs.txt',
        ],
        nationalMode: true,
      );
      expect(ordered.first, 'https://example.ir/configs.txt');
      expect(ordered.length, 2);
    });

    test('www subdomains of domestic hosts are classified as domestic', () {
      final source = KingResourceIntelligence.describe(
        'https://www.aparat.com/configs.txt',
        nationalMode: true,
      );
      expect(source.kind, KingResourceSourceKind.domesticPublic);
    });

    test('user-provided sources remain available and are prioritized', () {
      const paidOrPrivate = 'https://provider.example/subscription';
      final ordered = KingResourceIntelligence.orderSources(
        const <String>[
          'https://public.example/configs.txt',
          paidOrPrivate,
        ],
        nationalMode: true,
        userProvidedSources: const <String>[paidOrPrivate],
      );
      expect(ordered.first, paidOrPrivate);
      final source = KingResourceIntelligence.describe(
        paidOrPrivate,
        userProvided: true,
        nationalMode: true,
      );
      expect(source.access, KingResourceAccess.userSuppliedAccess);
    });

    test('global mode prioritizes user sources then community sources', () {
      final ordered = KingResourceIntelligence.orderSources(
        const <String>[
          'https://public.example/configs.txt',
          'https://example.ir/configs.txt',
          'https://owned.example/subscription',
        ],
        nationalMode: false,
        userProvidedSources: const <String>['https://owned.example/subscription'],
      );
      expect(ordered.first, 'https://owned.example/subscription');
      expect(ordered[1], 'https://public.example/configs.txt');
    });

    test('ordering is stable for equal-priority sources', () {
      final input = <String>[
        'https://one.example/a',
        'https://two.example/b',
        'https://three.example/c',
      ];
      expect(
        KingResourceIntelligence.orderSources(input, nationalMode: false),
        input,
      );
    });

    test('no source-count cap silently discards configured sources', () {
      final input = List<String>.generate(
        750,
        (i) => 'https://source$i.example/config.txt',
      );
      final result = KingResourceIntelligence.orderSources(
        input,
        nationalMode: true,
      );
      expect(result.length, input.length);
      expect(result.toSet().length, input.length);
    });

    test('URLs with embedded credentials are not classified as public sources', () {
      final source = KingResourceIntelligence.describe(
        'https://user:secret@example.ir/configs.txt',
        nationalMode: true,
      );
      expect(source.kind, KingResourceSourceKind.unknown);
      expect(source.access, KingResourceAccess.unknown);
    });

    test('malformed and non-web sources are retained as unknown', () {
      const value = 'file:///private/config.txt';
      final source = KingResourceIntelligence.describe(
        value,
        nationalMode: true,
      );
      expect(source.kind, KingResourceSourceKind.unknown);
      expect(
        KingResourceIntelligence.orderSources(
          const <String>[value],
          nationalMode: true,
        ),
        const <String>[value],
      );
    });
  });
}
