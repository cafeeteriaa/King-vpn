import 'package:flutter_test/flutter_test.dart';
import '../lib/personal_folder_store.dart';

void main() {
  group('PersonalFolderStore snapshot codec', () {
    test('round-trips Unicode and embedded line breaks without record loss', () {
      final input = <String>[
        'vless://one@example.com:443?remarks=سلام',
        'vmess://two@example.com:443?remarks=line\\nbreak',
        'trojan://three@example.com:443',
      ];
      final encoded = PersonalFolderStore.encodeSnapshot(input);
      expect(PersonalFolderStore.decodeSnapshot(encoded), input);
    });

    test('deduplicates case-insensitively while preserving first occurrence', () {
      final encoded = PersonalFolderStore.encodeSnapshot(<String>[
        'vless://A@example.com:443',
        'VLESS://a@example.com:443',
        'trojan://b@example.com:443',
      ]);
      expect(PersonalFolderStore.decodeSnapshot(encoded), <String>[
        'vless://A@example.com:443',
        'trojan://b@example.com:443',
      ]);
    });

    test('distinguishes a valid empty snapshot from corrupt content', () {
      expect(PersonalFolderStore.decodeSnapshot(''), isEmpty);
      expect(PersonalFolderStore.decodeSnapshot('not-json\\n'), isNull);
      expect(PersonalFolderStore.decodeSnapshot('42\\n'), isNull);
    });

    test('retains inventories beyond former fixed folder limits', () {
      final input = List<String>.generate(
        6000,
        (i) => 'vless://node$i@example.com:443',
      );
      final decoded = PersonalFolderStore.decodeSnapshot(
        PersonalFolderStore.encodeSnapshot(input),
      );
      expect(decoded, hasLength(6000));
      expect(decoded, input);
    });
  });
}
