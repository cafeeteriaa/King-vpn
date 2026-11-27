import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/fresh_resource_store.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

late Directory _temporarySupportDirectory;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _temporarySupportDirectory =
        await Directory.systemTemp.createTemp('king-vpn-resource-store-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _pathProviderChannel,
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return _temporarySupportDirectory.path;
        }
        return null;
      },
    );
  });

  setUp(() async {
    await FreshResourceStore.clear();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await _temporarySupportDirectory.exists()) {
      await _temporarySupportDirectory.delete(recursive: true);
    }
  });

  group('FreshResourceStore normalization', () {
    test('accepts supported V2Ray URI schemes', () {
      expect(
        FreshResourceStore.normalizeLinks([
          'vless://id@example.com:443',
          'vmess://eyJ2IjoiMiJ9',
          'trojan://secret@example.com:443',
          'ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388',
          'hysteria2://secret@example.com:443',
          'tuic://id:password@example.com:443',
        ]),
        hasLength(6),
      );
    });

    test('rejects arbitrary text and unsafe schemes', () {
      expect(
        FreshResourceStore.normalizeLinks([
          'not a config',
          'https://example.com',
          'file:///etc/passwd',
          '',
        ]),
        isEmpty,
      );
    });

    test('deduplicates case-insensitively', () {
      final values = FreshResourceStore.normalizeLinks([
        'vless://id@example.com:443',
        'VLESS://id@example.com:443',
        'vmess://abc',
      ]);
      expect(values, hasLength(2));
    });

    test('retains every distinct entry beyond the former 20000-entry ceiling', () {
      final links = List<String>.generate(
        20005,
        (index) => 'vless://id$index@example.com:443',
      );

      final normalized = FreshResourceStore.normalizeLinks(links);

      expect(normalized, hasLength(20005));
      expect(normalized.first, 'vless://id0@example.com:443');
      expect(normalized.last, 'vless://id20004@example.com:443');
    });

    test('accepts supported links longer than the former 65536-character ceiling', () {
      final longLink =
          'vless://id@example.com:443?metadata=' + ('x' * 65537);

      expect(longLink.length, greaterThan(65536));
      expect(FreshResourceStore.normalizeLink(longLink), longLink);
    });
  });

  group('FreshResourceStore persistence and concurrency', () {
    test('replaces a snapshot and keeps metadata count in sync', () async {
      await FreshResourceStore.saveSnapshot([
        'vless://old@example.com:443',
      ]);
      final total = await FreshResourceStore.saveSnapshot([
        'vless://new-a@example.com:443',
        'vless://new-b@example.com:443',
      ]);

      expect(total, 2);
      expect(await FreshResourceStore.readLinks(), [
        'vless://new-a@example.com:443',
        'vless://new-b@example.com:443',
      ]);
      expect((await FreshResourceStore.metadata())['count'], 2);
    });

    test('concurrent merges preserve additions from every caller', () async {
      await FreshResourceStore.saveSnapshot([
        'vless://base@example.com:443',
      ]);

      await Future.wait<int>([
        FreshResourceStore.merge(['vless://first@example.com:443']),
        FreshResourceStore.merge(['vless://second@example.com:443']),
      ]);

      final links = await FreshResourceStore.readLinks();
      expect(links, containsAll([
        'vless://base@example.com:443',
        'vless://first@example.com:443',
        'vless://second@example.com:443',
      ]));
      expect(links, hasLength(3));
      expect((await FreshResourceStore.metadata())['count'], 3);
    });

    test('failed temporary write preserves the previous snapshot and queue recovers', () async {
      await FreshResourceStore.saveSnapshot([
        'vless://preserve@example.com:443',
      ]);

      final storePath = await FreshResourceStore.storagePath;
      final blockingDirectory = Directory('$storePath/configs.txt.tmp');
      await blockingDirectory.create();

      await expectLater(
        FreshResourceStore.saveSnapshot([
          'vless://must-not-replace@example.com:443',
        ]),
        throwsA(isA<FileSystemException>()),
      );

      expect(await FreshResourceStore.readLinks(), [
        'vless://preserve@example.com:443',
      ]);

      await blockingDirectory.delete();
      await FreshResourceStore.merge([
        'vless://after-recovery@example.com:443',
      ]);

      expect(await FreshResourceStore.readLinks(), containsAll([
        'vless://preserve@example.com:443',
        'vless://after-recovery@example.com:443',
      ]));
    });

    test('clear is serialized and removes only this store snapshot', () async {
      await FreshResourceStore.saveSnapshot([
        'vless://clear-me@example.com:443',
      ]);

      await FreshResourceStore.clear();

      expect(await FreshResourceStore.readLinks(), isEmpty);
      expect(await FreshResourceStore.metadata(), isEmpty);
    });
  });
}
