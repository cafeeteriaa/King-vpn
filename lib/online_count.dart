import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'prefs_store.dart';

const String kOnlineBase = 'https://king-online.javdaniebrahim.workers.dev';

class OnlineCounter {
  static final ValueNotifier<int?> count = ValueNotifier<int?>(null);
  static Timer? _timer;
  static String? _id;

  static Future<String> _getId() async {
    if (_id != null) return _id!;
    final p = await SharedPreferences.getInstance();
    var id = p.getString('king_uid');
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{8,40}$').hasMatch(id)) {
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final r = Random.secure();
      id = List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
      await p.setString('king_uid', id);
    }
    _id = id;
    return id;
  }

  static Future<void> pingOnce() async {
    try {
      final id = await _getId();
      final res = await http
          .get(Uri.parse('$kOnlineBase/ping?id=$id'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final n = (jsonDecode(res.body) as Map)['online'];
        if (n is int) count.value = n;
      }
    } catch (_) {}
  }

  static void start() {
    _timer?.cancel();
    unawaited(pingOnce());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => pingOnce());
  }
}

class OnlineCountBadge extends StatelessWidget {
  const OnlineCountBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: OnlineCounter.count,
      builder: (context, n, child) => Text(
        n == null ? '...' : '$n نفر آنلاین',
        style: const TextStyle(fontSize: 12, color: Color(0xFFD9AE55)),
      ),
    );
  }
}
