import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/nat_ultra.dart';

void main() {
  group('natHotNext request bounds', () {
    test('non-positive batch sizes are no-ops', () async {
      expect(await natHotNext(0), isEmpty);
      expect(await natHotNext(-1), isEmpty);
    });
  });
}
