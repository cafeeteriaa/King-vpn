import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/cf_trace_validation.dart';

void main() {
  group('Cloudflare trace response validation', () {
    test('accepts a successful trace response with required fields', () {
      const response = 'HTTP/1.1 200 OK\r\n'
          'content-type: text/plain\r\n'
          'connection: close\r\n\r\n'
          'fl=iad\n'
          'h=cloudflare.com\n'
          'ip=203.0.113.10\n'
          'ts=1730000000.000\n';
      expect(isValidCloudflareTraceResponse(response), isTrue);
    });

    test('rejects forbidden responses even when the body mentions Cloudflare', () {
      const response = 'HTTP/1.1 403 Forbidden\r\n\r\n'
          'cloudflare access denied';
      expect(isValidCloudflareTraceResponse(response), isFalse);
    });

    test('rejects redirects and non-trace success pages', () {
      expect(
        isValidCloudflareTraceResponse(
          'HTTP/1.1 301 Moved Permanently\r\n\r\nfl=iad\nip=203.0.113.10\nts=1',
        ),
        isFalse,
      );
      expect(
        isValidCloudflareTraceResponse(
          'HTTP/1.1 200 OK\r\n\r\nWelcome to Cloudflare',
        ),
        isFalse,
      );
    });

    test('rejects malformed or incomplete responses', () {
      expect(isValidCloudflareTraceResponse('cloudflare fl=iad ip=1 ts=1'), isFalse);
      expect(
        isValidCloudflareTraceResponse(
          'HTTP/1.1 200 OK\r\n\r\nfl=iad\nip=203.0.113.10',
        ),
        isFalse,
      );
    });
  });
}
