import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_provider_pilot.dart';

void main() {
  group('King AI private helper pilot', () {
    test('coding work prioritizes code-capable helpers', () {
      final order = KingAiProviderPilot.priorityForTask(KingAiTaskKind.coding);
      expect(order.first, KingAiProvider.groq);
      expect(order[1], KingAiProvider.mistral);
      expect(order.toSet(), KingAiProvider.values.toSet());
    });

    test('audio work prioritizes speech-oriented helper', () {
      final order = KingAiProviderPilot.priorityForTask(KingAiTaskKind.audio);
      expect(order.first, KingAiProvider.groq);
    });

    test('image and video tasks have dedicated helper routing', () {
      expect(KingAiProviderPilot.priorityForTask(KingAiTaskKind.image).first,
          KingAiProvider.openRouter);
      expect(KingAiProviderPilot.priorityForTask(KingAiTaskKind.video).first,
          KingAiProvider.openRouter);
    });

    test('complex tasks may consult two helpers while general chat uses one', () {
      expect(KingAiProviderPilot.helperCountForTask(KingAiTaskKind.general), 1);
      expect(KingAiProviderPilot.helperCountForTask(KingAiTaskKind.coding), 2);
      expect(KingAiProviderPilot.helperCountForTask(KingAiTaskKind.image), 2);
      expect(KingAiProviderPilot.helperCountForTask(KingAiTaskKind.video), 2);
    });

    test('provider pool exposes no direct ask/chat method', () {
      // The public integration point is a King-internal peer-review operation.
      expect(KingAiProviderPilot.instance.consultKing, isA<Function>());
    });

    test('provider pilot has no VPN service dependency', () {
      // Provider routing is independent of the local VPN Smart Pilot.
      expect(KingAiProviderPilot.priorityForTask(KingAiTaskKind.research).first,
          KingAiProvider.mistral);
    });
  });
}
