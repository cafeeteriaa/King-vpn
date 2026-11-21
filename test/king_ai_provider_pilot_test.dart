import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_provider_pilot.dart';

void main() {
  group('King AI provider pilot', () {
    test('routes coding requests to code-capable free providers first', () {
      final order = KingAiProviderPilot.priorityForPrompt(
        'لطفاً این باگ Dart را در کد برنامه اصلاح کن',
      );
      expect(order.first, KingAiProvider.groq);
      expect(order[1], KingAiProvider.mistral);
      expect(order, contains(KingAiProvider.gemini));
      expect(order, contains(KingAiProvider.openRouter));
      expect(order, contains(KingAiProvider.cloudflare));
    });

    test('routes general requests to Gemini first and retains fallbacks', () {
      final order = KingAiProviderPilot.priorityForPrompt(
        'لطفاً درباره تاریخچه نجوم توضیح بده',
      );
      expect(order.first, KingAiProvider.gemini);
      expect(order, hasLength(KingAiProvider.values.length));
      expect(order.toSet(), KingAiProvider.values.toSet());
    });

    test('provider pilot never changes the VPN pilot strategy', () {
      // The provider router has no imports or references to network-health,
      // VPN service, route selection, or connection settings.
      expect(KingAiProviderPilot.priorityForPrompt('سلام').first,
          KingAiProvider.gemini);
    });
  });
}
