import 'package:flutter_test/flutter_test.dart';
import '../lib/self_repair_policy.dart';

void main() {
  group('Source patch path allowlist', () {
    test('accepts only lib, test and tools paths', () {
      for (final path in ['lib/a.dart', 'test/a_test.dart', 'tools/repair.py']) {
        expect(isAllowedSourcePatchPath(path), isTrue, reason: path);
      }
    });

    test('rejects repository metadata, dependencies and Android files', () {
      for (final path in [
        'README.md',
        '.github/workflows/build.yml',
        'pubspec.yaml',
        'android/app/src/main/kotlin/MainActivity.kt',
      ]) {
        expect(isAllowedSourcePatchPath(path), isFalse, reason: path);
      }
    });

    test('rejects traversal, dot segments, empty segments and backslashes', () {
      for (final path in [
        '../secret.dart',
        'lib/../secret.dart',
        'lib/./secret.dart',
        'lib//secret.dart',
        r'lib\..\secret.dart',
        '/lib/secret.dart',
      ]) {
        expect(isAllowedSourcePatchPath(path), isFalse, reason: path);
      }
    });
  });

  group('Source patch gate', () {
    PatchGateInput safeInput(List<String> paths) => PatchGateInput(
          signedByTrustedKey: true,
          testsPassed: true,
          staticAnalysisPassed: true,
          rollbackSnapshotExists: true,
          changedFiles: paths,
          diffLines: 10,
        );

    test('accepts a fully verified patch inside allowed roots', () {
      expect(
        validateSourcePatch(safeInput(['lib/a.dart', 'test/a_test.dart'])).status,
        PatchGateStatus.accepted,
      );
    });

    test('rejects an otherwise verified patch outside allowed roots', () {
      final result = validateSourcePatch(safeInput(['.github/workflows/build.yml']));
      expect(result.status, PatchGateStatus.rejected);
      expect(result.reasons.any((reason) => reason.contains('محدوده مجاز')), isTrue);
    });
  });
}
