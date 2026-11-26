# بازبینی چرخهٔ آزادسازی TUN برای libbox

آزادسازی مالکیت libbox فقط به Stream رویداد Dart وابسته نیست. اسکریپت build، API وضعیت native را در وابستگی پین‌شده عمومی می‌کند و KingVpnEngineCoordinator مستقیماً به ServiceState گوش می‌دهد.

توقف libbox از طریق VpnService انجام می‌شود؛ coordinator تا دریافت وضعیت Stopped منتظر می‌ماند. در upstream، وضعیت Stopped پس از بستن tun file descriptor و CommandServer منتشر می‌شود. سپس قفل libbox آزاد می‌شود. این مسیر هنگام بسته‌شدن Activity یا بازسازی Flutter engine نیز کار می‌کند.

اگر سرویس وضعیت توقف را در مهلت handoff اعلام نکند، مالکیت آزاد نمی‌شود و موتور بعدی شروع نخواهد شد.
