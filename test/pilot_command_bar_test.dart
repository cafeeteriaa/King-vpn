import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  testWidgets('cancel command remains usable during a pending command and wins over stale reply',
      (tester) async {
    final status = ValueNotifier<String>('');
    addTearDown(status.dispose);
    final pending = Completer<String>();
    final commands = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PilotCommandBar(
          onSubmit: (command) {
            commands.add(command);
            return command == 'long-running'
                ? pending.future
                : Future<String>.value('درخواست لغو شد');
          },
          localStatus: status,
          pilotOn: true,
          connected: false,
          busy: true,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'long-running');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('لغو عملیات'), findsOneWidget);

    await tester.tap(find.text('لغو عملیات'));
    await tester.pump();
    expect(commands, <String>['long-running', 'لغو جستجو']);
    expect(find.text('درخواست لغو شد'), findsOneWidget);

    pending.complete('پاسخ قدیمی فرمان قبلی');
    await tester.pump();
    expect(find.text('درخواست لغو شد'), findsOneWidget);
  });
}
