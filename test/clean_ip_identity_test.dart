import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart' as app;

void main() {
  test('accepts a complete Cloudflare trace over the validated TLS path', () {
    const response = 'HTTP/1.1 200 OK\\r\\n'
        'server: cloudflare\\r\\n'
        'cf-ray: abc123-FRA\\r\\n'
        'content-type: text/plain\\r\\n'
        '\\r\\n'
        'ip=203.0.113.10\\n'
        'colo=FRA\\n'
        'http=http/1.1\\n';
    expect(app.isValidCloudflareTraceResponse(response), isTrue);
  });

  test('rejects spoofable or incomplete trace responses', () {
    const spoofedBody = 'HTTP/1.1 200 OK\\r\\n'
        'server: nginx\\r\\n'
        '\\r\\n'
        'cloudflare ip=203.0.113.10 colo=FRA http=http/1.1';
    const missingRay = 'HTTP/1.1 200 OK\\r\\n'
        'server: cloudflare\\r\\n'
        '\\r\\n'
        'ip=203.0.113.10\\ncolo=FRA\\nhttp=http/1.1';
    const notFound = 'HTTP/1.1 404 Not Found\\r\\n'
        'server: cloudflare\\r\\n'
        'cf-ray: abc123-FRA\\r\\n'
        '\\r\\n'
        'ip=203.0.113.10\\ncolo=FRA\\nhttp=http/1.1';

    expect(app.isValidCloudflareTraceResponse(spoofedBody), isFalse);
    expect(app.isValidCloudflareTraceResponse(missingRay), isFalse);
    expect(app.isValidCloudflareTraceResponse(notFound), isFalse);
  });
}
