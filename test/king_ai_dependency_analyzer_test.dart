import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/king_ai_dependency_analyzer.dart';

void main() {
  test('resolves Dart relative and project package imports', () {
    final result = KingAiDependencyAnalyzer.analyze({
      'lib/a.dart': "import 'b.dart'; import 'package:king_vpn/c.dart';",
      'lib/b.dart': 'class B {}',
      'lib/c.dart': 'class C {}',
    });
    final edges = result['edges'] as Map<String, List<String>>;
    expect(edges['lib/a.dart'], ['lib/b.dart', 'lib/c.dart']);
  });

  test('scopes dependency edges to the current inference batch', () {
    final graph = KingAiDependencyAnalyzer.analyze({
      'lib/a.dart': "import 'b.dart';",
      'lib/b.dart': 'class B {}',
      'lib/c.dart': "import 'd.dart';",
      'lib/d.dart': 'class D {}',
    });
    final batch = KingAiDependencyAnalyzer.forBatch(
      graph,
      {'lib/a.dart'},
    );
    final edges = batch['edges'] as Map<String, List<String>>;
    expect(edges.keys, ['lib/a.dart']);
    expect(edges['lib/a.dart'], ['lib/b.dart']);
    expect(batch['scope'], contains('other batches'));
  });

  test('reports unresolved project imports and detects cycles', () {
    final result = KingAiDependencyAnalyzer.analyze({
      'lib/a.dart': "import 'b.dart'; import 'missing.dart';",
      'lib/b.dart': "import 'a.dart';",
    });
    expect((result['unresolved'] as Map).containsKey('lib/a.dart'), isTrue);
    expect((result['cycles'] as List).isNotEmpty, isTrue);
  });

  test('resolves Python module imports', () {
    final result = KingAiDependencyAnalyzer.analyze({
      'tools/a.py': 'from . import b\nimport json',
      'tools/b.py': 'VALUE = 1',
    });
    final edges = result['edges'] as Map<String, List<String>>;
    expect(edges['tools/a.py'], contains('tools/b.py'));
  });
}
