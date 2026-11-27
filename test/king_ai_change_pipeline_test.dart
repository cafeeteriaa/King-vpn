import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/king_ai_change_pipeline.dart';

void main() {
  group('KingAiWorkPlan', () {
    test('parses a dependency-ordered multi-stage plan', () {
      final plan = KingAiWorkPlan.parse('''
```json
{
  "summary": "A cohesive scanner and reliability improvement.",
  "stages": [
    {"id": "core", "task": "Refactor the scanner core and preserve its public contract."},
    {"id": "integration", "task": "Integrate the updated scanner core into its existing caller."},
    {"id": "tests", "task": "Add regression tests for cancellation and mode isolation."}
  ]
}
```
''');
      expect(plan.summary, contains('scanner'));
      expect(plan.stages, hasLength(3));
      expect(plan.stages.map((stage) => stage.id), ['core', 'integration', 'tests']);
    });

    test('rejects duplicate stage ids and more than six stages', () {
      const duplicate = '{"summary":"plan","stages":['
          '{"id":"core","task":"Implement the core behavior safely."},'
          '{"id":"core","task":"Integrate the core behavior safely."}]}';
      expect(() => KingAiWorkPlan.parse(duplicate), throwsFormatException);

      final tooMany = {
        'summary': 'plan',
        'stages': [
          for (var i = 0; i < 7; i++)
            {'id': 'stage$i', 'task': 'Implement stage number $i with tests.'},
        ],
      };
      expect(() => KingAiWorkPlan.parse(jsonEncode(tooMany)), throwsFormatException);
    });

    test('rejects malformed or oversized stage descriptions', () {
      expect(
        () => KingAiWorkPlan.parse(
          '{"summary":"x","stages":[{"id":"core","task":"short"}]}',
        ),
        throwsFormatException,
      );
      expect(
        () => KingAiWorkPlan.parse(
          jsonEncode({
            'summary': 'plan',
            'stages': [
              {'id': 'core', 'task': 'x' * 1201},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });

  group('KingAiPatchBundle', () {
    test('aggregates separate three-file passes into one cohesive bundle', () {
      final bundle = KingAiPatchBundle();
      bundle.addStage(
        stageIndex: 0,
        sourceFiles: const {
          'lib/core.dart': 'old-core',
          'test/core_test.dart': 'old-test',
        },
        changes: const {
          'lib/core.dart': 'new-core',
          'test/core_test.dart': 'new-test',
        },
      );
      bundle.addStage(
        stageIndex: 1,
        sourceFiles: const {
          'lib/integration.dart': 'old-integration',
          'test/integration_test.dart': 'old-integration-test',
        },
        changes: const {
          'lib/integration.dart': 'new-integration',
          'test/integration_test.dart': 'new-integration-test',
        },
      );

      expect(bundle.completedStages, 2);
      expect(bundle.changedFileCount, 4);
      expect(bundle.changes['lib/core.dart'], 'new-core');
      expect(bundle.changes['lib/integration.dart'], 'new-integration');
    });

    test('allows a later stage to extend a prior file only from its latest output', () {
      final bundle = KingAiPatchBundle();
      bundle.addStage(
        stageIndex: 0,
        sourceFiles: const {'lib/shared.dart': 'v1'},
        changes: const {'lib/shared.dart': 'v2'},
      );
      bundle.addStage(
        stageIndex: 1,
        sourceFiles: const {'lib/shared.dart': 'v2'},
        changes: const {'lib/shared.dart': 'v3'},
      );
      expect(bundle.changes['lib/shared.dart'], 'v3');
      expect(bundle.changedFileCount, 1);
    });

    test('rejects a stale or conflicting follow-up stage', () {
      final bundle = KingAiPatchBundle();
      bundle.addStage(
        stageIndex: 0,
        sourceFiles: const {'lib/shared.dart': 'v1'},
        changes: const {'lib/shared.dart': 'v2'},
      );
      expect(
        () => bundle.addStage(
          stageIndex: 1,
          sourceFiles: const {'lib/shared.dart': 'v1'},
          changes: const {'lib/shared.dart': 'v3'},
        ),
        throwsStateError,
      );
      expect(bundle.changes['lib/shared.dart'], 'v2');
      expect(bundle.completedStages, 1);
    });

    test('rejects out-of-order stages and paths outside the source allowlist', () {
      final bundle = KingAiPatchBundle();
      expect(
        () => bundle.addStage(
          stageIndex: 1,
          sourceFiles: const {'lib/core.dart': 'old'},
          changes: const {'lib/core.dart': 'new'},
        ),
        throwsStateError,
      );
      expect(
        () => bundle.addStage(
          stageIndex: 0,
          sourceFiles: const {'../secrets.txt': 'old'},
          changes: const {'../secrets.txt': 'new'},
        ),
        throwsFormatException,
      );
      expect(bundle.isEmpty, isTrue);
      expect(bundle.completedStages, 0);
    });

    test('rejects changes outside supplied context and more than three files per stage', () {
      final bundle = KingAiPatchBundle();
      expect(
        () => bundle.addStage(
          stageIndex: 0,
          sourceFiles: const {'lib/a.dart': 'a'},
          changes: const {'lib/b.dart': 'b'},
        ),
        throwsFormatException,
      );
      expect(
        () => bundle.addStage(
          stageIndex: 0,
          sourceFiles: const {
            'lib/a.dart': 'a',
            'lib/b.dart': 'b',
            'lib/c.dart': 'c',
            'lib/d.dart': 'd',
          },
          changes: const {
            'lib/a.dart': 'A',
            'lib/b.dart': 'B',
            'lib/c.dart': 'C',
            'lib/d.dart': 'D',
          },
        ),
        throwsArgumentError,
      );
    });


    test('detects stale input when a prior stage intentionally produced an empty file', () {
      final bundle = KingAiPatchBundle();
      bundle.addStage(
        stageIndex: 0,
        sourceFiles: const {'lib/empty.dart': 'original'},
        changes: const {'lib/empty.dart': ''},
      );
      expect(
        () => bundle.addStage(
          stageIndex: 1,
          sourceFiles: const {'lib/empty.dart': 'original'},
          changes: const {'lib/empty.dart': 'later'},
        ),
        throwsStateError,
      );
      expect(bundle.changes['lib/empty.dart'], isEmpty);
      expect(bundle.completedStages, 1);
    });

    test('ignores no-op outputs and counts completed empty stages', () {
      final bundle = KingAiPatchBundle();
      bundle.addStage(
        stageIndex: 0,
        sourceFiles: const {'lib/core.dart': 'same'},
        changes: const {'lib/core.dart': 'same'},
      );
      bundle.addStage(
        stageIndex: 1,
        sourceFiles: const {'test/core_test.dart': 'same'},
        changes: const {},
      );
      expect(bundle.isEmpty, isTrue);
      expect(bundle.completedStages, 2);
    });
  });
}
