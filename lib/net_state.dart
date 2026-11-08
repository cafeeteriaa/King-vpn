part of 'main.dart';

// =============================================================================
// ماشین حالت شبکه (فقط تشخیص و نمایش؛ هیچ سوئیچ خودکاری انجام نمی‌دهد)
// سه حالت: اینترنت آزاد / فیلترشدن پروتکل فعلی / قطعی کامل (بدون نت ملی؛ جدید)
// ورودی‌ها از همان شمارنده‌های موجود برنامه گرفته می‌شوند.
// =============================================================================

enum _NetState { globalOpen, dpiBlocked, chaos }

_NetState _netStateNow({
  required bool connected,
  required int tunBadNow,
  required int pingRounds,
}) {
  if (!connected && pingRounds >= badPingMaxRounds) return _NetState.chaos;
  if (!connected) return _NetState.dpiBlocked;
  if (tunBadNow >= 2 || pingRounds >= 2) return _NetState.dpiBlocked;
  return _NetState.globalOpen;
}

String _netStateLabel(_NetState s) => switch (s) {
      _NetState.globalOpen => 'اینترنت آزاد',
      _NetState.dpiBlocked => 'پروتکل فیلتر شده',
      _NetState.chaos => 'قطعی کامل',
    };
