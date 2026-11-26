import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart' as app;

void main() {
  test('IPv6 CIDR cursors enumerate the entire small range in batches', () {
    final first = app.natExpandAddressRangeBatch(
      '2001:db8::/126',
      cursor: '0',
      limit: 2,
    );
    expect(first.addresses, ['2001:db8::', '2001:db8::1']);
    expect(first.nextCursor, '2');

    final second = app.natExpandAddressRangeBatch(
      '2001:db8::/126',
      cursor: first.nextCursor,
      limit: 2,
    );
    expect(second.addresses, ['2001:db8::2', '2001:db8::3']);
    expect(second.nextCursor, '0');
  });

  test('IPv6 inclusive ranges and large offsets use BigInt cursors', () {
    final range = app.natExpandAddressRangeBatch(
      '2001:db8::10-2001:db8::12',
      cursor: '1',
      limit: 2,
    );
    expect(range.addresses, ['2001:db8::11', '2001:db8::12']);

    final large = app.natExpandAddressRangeBatch(
      '2001:db8::/64',
      cursor: '18446744073709551617',
      limit: 2,
    );
    expect(large.addresses, hasLength(2));
    expect(large.nextCursor, '18446744073709551619');
  });

  test('IPv4 CIDR cursors remain compatible', () {
    final first = app.natExpandAddressRangeBatch(
      '192.0.2.0/30',
      cursor: '0',
      limit: 3,
    );
    expect(first.addresses, ['192.0.2.0', '192.0.2.1', '192.0.2.2']);
    expect(first.nextCursor, '3');
  });
}
