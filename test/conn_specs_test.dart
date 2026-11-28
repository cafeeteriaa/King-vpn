import 'package:flutter_test/flutter_test.dart';
import '../lib/conn_specs.dart';

void main() {
  test('repairs stray percent characters without changing valid escapes', () {
    final uri = parseConfigUri(
      'vless://00000000-0000-4000-8000-000000000001@example.com:443'
      '?security=tls&type=ws&path=%2Fedge%zz&host=cdn.example.com',
    );

    expect(uri, isNotNull);
    expect(uri!.host, 'example.com');
    expect(uri.queryParameters['path'], '/edge%zz');
    expect(uri.queryParameters['host'], 'cdn.example.com');
  });

  test('describes a valid endpoint even when its path has a stray percent', () {
    final spec = describeConfig(
      'vless://00000000-0000-4000-8000-000000000001@example.com:443'
      '?security=tls&type=ws&path=%2Fedge%zz#test',
    );

    expect(spec.host, 'example.com');
    expect(spec.port, '443');
    expect(spec.path, '/edge%zz');
  });
}
