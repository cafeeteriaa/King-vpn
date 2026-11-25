import 'package:flutter_test/flutter_test.dart';
import '../lib/failover_retry_policy.dart';

void main() {
  group('failover busy retry policy', () {
    test('backoff stage advances and then saturates without ending retries', () {
      expect(nextFailoverRetryStage(-1), 1);
      expect(nextFailoverRetryStage(0), 1);
      expect(nextFailoverRetryStage(1), 2);
      expect(nextFailoverRetryStage(2), 3);
      expect(nextFailoverRetryStage(3), 4);
      expect(nextFailoverRetryStage(4), 4);
      expect(nextFailoverRetryStage(1000000), 4);
    });

    test('retry delay grows exponentially and remains bounded', () {
      expect(failoverBusyRetryDelay(0), const Duration(seconds: 60));
      expect(failoverBusyRetryDelay(1), const Duration(seconds: 10));
      expect(failoverBusyRetryDelay(2), const Duration(seconds: 20));
      expect(failoverBusyRetryDelay(3), const Duration(seconds: 40));
      expect(failoverBusyRetryDelay(4), const Duration(seconds: 60));
      expect(failoverBusyRetryDelay(99), const Duration(seconds: 60));
    });
  });
}
