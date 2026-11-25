import 'package:flutter_test/flutter_test.dart';
import 'package:king_vpn/proc_stat_cpu.dart';

String statLine({
  required String command,
  required String state,
  required String userTicks,
  required String systemTicks,
}) {
  // Fields after comm begin at field 3 (state). Supply fields 3..15.
  final fields = <String>[
    state, // 3
    '1', // 4 ppid
    '1', // 5 pgrp
    '1', // 6 session
    '0', // 7 tty_nr
    '0', // 8 tpgid
    '0', // 9 flags
    '0', // 10 minflt
    '0', // 11 cminflt
    '0', // 12 majflt
    '0', // 13 cmajflt
    userTicks, // 14 utime
    systemTicks, // 15 stime
  ];
  return '123 ($command) ${fields.join(' ')}';
}

void main() {
  group('Android proc stat CPU parser', () {
    test('reads utime and stime after the command field', () {
      expect(
        parseProcStatCpuTicks(statLine(
          command: 'king_vpn',
          state: 'S',
          userTicks: '120',
          systemTicks: '35',
        )),
        155,
      );
    });

    test('handles spaces and parentheses inside process command', () {
      expect(
        parseProcStatCpuTicks(statLine(
          command: 'king vpn (worker)',
          state: 'R',
          userTicks: '500',
          systemTicks: '25',
        )),
        525,
      );
    });

    test('normalizes repeated whitespace in kernel stat fields', () {
      const input = '123 (king vpn) S   1 1 1 0 0 0 0 0 0 0 200   40';
      expect(parseProcStatCpuTicks(input), 240);
    });

    test('rejects truncated or malformed counters', () {
      expect(parseProcStatCpuTicks('123 (king_vpn) S 1 2'), isNull);
      expect(
        parseProcStatCpuTicks(
          '123 (king_vpn) S 1 1 1 0 0 0 0 0 0 0 nope 4',
        ),
        isNull,
      );
      expect(parseProcStatCpuTicks('123 king_vpn S 1 1 1 0 0 0 0 0 0 0 1 2'), isNull);
    });
  });
}
