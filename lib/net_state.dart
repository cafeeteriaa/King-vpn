part of 'main.dart';

// =============================================================================
// ماشین حالت شبکه (فقط تشخیص و نمایش؛ هیچ سوئیچ خودکاری انجام نمی‌دهد)
// چهار حالت: اینترنت آزاد / نت ملی / فیلترشدن پروتکل فعلی / قطعی کامل
// ورودی‌ها از همان شمارنده‌های موجود برنامه گرفته می‌شوند.
// =============================================================================

enum _NetState { globalOpen, nationalFallback, dpiBlocked, chaos }

_NetState _netStateNow({
  required bool connected,
  required bool national,
  required int tunBadNow,
  required int pingRounds,
}) {
  if (!connected && pingRounds >= badPingMaxRounds) return _NetState.chaos;
  if (!connected) {
    return national ? _NetState.nationalFallback : _NetState.dpiBlocked;
  }
  if (tunBadNow >= 2 || pingRounds >= 2) return _NetState.dpiBlocked;
  return national ? _NetState.nationalFallback : _NetState.globalOpen;
}

String _netStateLabel(_NetState s) => switch (s) {
      _NetState.globalOpen => 'اینترنت آزاد',
      _NetState.nationalFallback => 'نت ملی',
      _NetState.dpiBlocked => 'پروتکل فیلتر شده',
      _NetState.chaos => 'قطعی کامل',
    };
