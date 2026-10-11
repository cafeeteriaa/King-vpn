part of 'main.dart';

// DONATE ====================================================================
// صفحه‌ی حمایت مالی: فقط USDT روی شبکه‌ی TRON (TRC20).
// آدرس کیف پول (آدرس عمومی). برای تغییر فقط همین‌جا را عوض کن.
const String donateWallet = 'TQVfshcLxdCnBTcziiQ1Q5XDXMMoZCAZHq';

// آدرس معتبر ترون: با T شروع می‌شود و ۳۴ کاراکتر base58 است.
bool _donateAddrOk(String a) =>
    RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(a);

void donateSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var copied = false;
      return StatefulBuilder(builder: (ctx, setS) {
        final ok = _donateAddrOk(donateWallet);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite, color: _uiGold, size: 24),
                      SizedBox(width: 8),
                      Text('حمایت از ما',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _uiGold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'اگر برنامه برایت مفید بود، می‌توانی با یک مبلغ دلخواه از '
                    'ادامه‌ی توسعه و هزینه‌ی سرورها حمایت کنی. ممنون از لطفت 🙏',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.7),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _uiCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x77D9AE55)),
                    ),
                    child: const Text(
                      'ارز: USDT (تتر)  •  شبکه: TRON (TRC20)',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: _uiText),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (ok) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _uiCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        donateWallet,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                            color: _uiText),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: Icon(copied ? Icons.check : Icons.copy),
                      label: Text(copied ? 'کپی شد ✓' : 'کپی آدرس کیف پول'),
                      onPressed: () async {
                        await Clipboard.setData(
                            const ClipboardData(text: donateWallet));
                        setS(() => copied = true);
                      },
                    ),
                  ] else
                    const Text(
                      'آدرس کیف پول هنوز تنظیم نشده است.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ فقط USDT روی شبکه‌ی TRC20 بفرست. ارسال روی شبکه‌ی دیگر '
                    'باعث از بین رفتن پول می‌شود.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        );
      });
    },
  );
}
