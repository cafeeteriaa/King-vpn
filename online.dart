part of 'main.dart';

// ONLINE COUNTER ============================================================
// تعداد کاربران آنلاین از روی Worker کلادفلر. فقط یک شناسه‌ی تصادفی ارسال
// می‌شود (بدون ایمیل، شماره یا هر اطلاعات شخصی).
// آدرس Worker را این‌جا بگذار، مثل: https://king-online.xxxx.workers.dev
const String onlineApiUrl = 'https://king-online.javdaniebrahim.workers.dev';

final ValueNotifier<int?> onlineNotifier = ValueNotifier<int?>(null);
String? _onlineId;
Timer? _onlineTimer;

Future<String> _onlineGetId() async {
  final cur = _onlineId;
  if (cur != null) return cur;
  final p = await SharedPreferences.getInstance();
  var id = p.getString('online_id');
  if (id == null || id.length < 8) {
    final r = Random.secure();
    const a = 'abcdefghijklmnopqrstuvwxyz0123456789';
    id = List.generate(24, (_) => a[r.nextInt(a.length)]).join();
    await p.setString('online_id', id);
  }
  _onlineId = id;
  return id;
}

Future<void> onlinePing() async {
  if (!onlineApiUrl.startsWith('https://')) return;
  try {
    final id = await _onlineGetId();
    final r = await http
        .get(Uri.parse('$onlineApiUrl/ping?id=$id'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      if (j is Map && j['online'] is int) {
        onlineNotifier.value = j['online'] as int;
      }
    }
  } catch (e) {
    logError(e);
  }
}

// هر ۴ دقیقه یک بار (سمت Worker: ۶ دقیقه‌ی اخیر = آنلاین)
void onlineStart() {
  if (_onlineTimer != null) return;
  unawaited(onlinePing());
  _onlineTimer =
      Timer.periodic(const Duration(minutes: 4), (_) => onlinePing());
}

class OnlineBadge extends StatelessWidget {
  const OnlineBadge({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
        valueListenable: onlineNotifier,
        builder: (_, n, __) {
          if (n == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                const SizedBox(width: 6),
                Text('$n نفر آنلاین',
                    style: const TextStyle(fontSize: 13, color: _uiText)),
              ],
            ),
          );
        },
      );
}
