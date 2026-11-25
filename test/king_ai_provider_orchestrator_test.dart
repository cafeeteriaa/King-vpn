import 'package:flutter_test/flutter_test.dart';

import '../lib/king_ai_provider_orchestrator.dart';

void main() {
  group('KING AI provider catalog', () {
    test('contains distinct providers with HTTPS endpoints and models', () {
      final providers = KingAiProviderOrchestrator.providers;
      final ids = providers.map((provider) => provider.id).toSet();

      expect(ids.length, providers.length);
      expect(providers, isNotEmpty);
      for (final provider in providers) {
        expect(provider.endpoint, startsWith('https://'));
        expect(provider.defaultModel, isNotEmpty);
        expect(provider.title, isNotEmpty);
      }
    });

    test('separates text-only and vision-capable provider profiles', () {
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.deepSeek).supportsVision,
        isFalse,
      );
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.openAi).supportsVision,
        isTrue,
      );
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.anthropic).supportsVision,
        isTrue,
      );
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.gemini).supportsVision,
        isTrue,
      );
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.groq).supportsVision,
        isFalse,
      );
      expect(
        KingAiProviderOrchestrator.descriptor(KingAiProviderId.cerebras).supportsVision,
        isFalse,
      );
    });

    test('marks OpenRouter free-model availability as non-guaranteed', () {
      final provider = KingAiProviderOrchestrator.descriptor(
        KingAiProviderId.openRouter,
      );
      expect(provider.note, contains('دائمی'));
    });
  });
}
