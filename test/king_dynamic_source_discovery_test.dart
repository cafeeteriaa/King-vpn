import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_dynamic_source_discovery.dart';

void main() {
  group('KING dynamic source discovery policy', () {
    test('accepts subscription-like text artifacts within the size budget', () {
      expect(KingDynamicSourceDiscovery.isCandidatePath('sub/all.txt', size: 900), isTrue);
      expect(KingDynamicSourceDiscovery.isCandidatePath('configs/vless.yaml', size: 900), isTrue);
      expect(KingDynamicSourceDiscovery.isCandidatePath('output/proxy_nodes.json', size: 900), isTrue);
    });

    test('rejects documentation, hidden paths, unrelated files and oversized blobs', () {
      expect(KingDynamicSourceDiscovery.isCandidatePath('README.md', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('docs/sub.txt', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('.github/sub.txt', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('vendor/.git/sub.txt', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('src/main.dart', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('../sub/all.txt', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('/sub/all.txt', size: 10), isFalse);
      expect(KingDynamicSourceDiscovery.isCandidatePath('sub/all.txt', size: 1500001), isFalse);
    });

    test('only canonical HTTPS raw GitHub file URLs are accepted', () {
      const valid = 'https://raw.githubusercontent.com/owner/repo/main/sub/all.txt';
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl(valid), valid);
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl('http://raw.githubusercontent.com/owner/repo/main/sub.txt'), isNull);
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl('https://evil.example/owner/repo/main/sub.txt'), isNull);
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl('https://raw.githubusercontent.com/owner/repo/main/../secret'), isNull);
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl('https://raw.githubusercontent.com/owner/repo/main/%2e%2e%2fsecret'), isNull);
      expect(KingDynamicSourceDiscovery.normalizeFeedUrl('https://raw.githubusercontent.com/owner/repo/main/sub.txt?token=x'), isNull);
    });
  });
}
