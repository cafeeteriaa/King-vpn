import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/http_response_policy.dart';

void main() {
  group('HTTP list response acceptance', () {
    test('accepts only non-empty HTTP 200 responses', () {
      expect(isUsableHttpListResponse(200, 'vless://example'), isTrue);
      expect(isUsableHttpListResponse(200, '  config-data  '), isTrue);
    });

    test('rejects error pages even when they contain response text', () {
      expect(isUsableHttpListResponse(403, 'access denied'), isFalse);
      expect(isUsableHttpListResponse(404, 'not found'), isFalse);
      expect(isUsableHttpListResponse(500, 'temporary error'), isFalse);
    });

    test('rejects empty and whitespace-only successful responses', () {
      expect(isUsableHttpListResponse(200, ''), isFalse);
      expect(isUsableHttpListResponse(200, ' \r\n\t '), isFalse);
      expect(isUsableHttpListResponse(204, ''), isFalse);
    });
  });
}
