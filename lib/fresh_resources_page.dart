import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fresh_resource_store.dart';

/// Visible manager for the phone's reusable fresh-resource folder.
class FreshResourcesPage extends StatefulWidget {
  const FreshResourcesPage({super.key});

  @override
  State<FreshResourcesPage> createState() => _FreshResourcesPageState();
}

class _FreshResourcesPageState extends State<FreshResourcesPage> {
  final TextEditingController _importController = TextEditingController();
  List<String> _links = <String>[];
  Map<String, Object?> _metadata = <String, Object?>{};
  String _path = 'در حال خواندن مسیر...';
  static const int _pageSize = 100;
  int _pageOffset = 0;
  int _totalCount = 0;
  bool _hasMore = false;
  bool _busy = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final values = await Future.wait<Object>([
        FreshResourceStore.readPage(offset: _pageOffset, limit: _pageSize),
        FreshResourceStore.metadata(),
        FreshResourceStore.storagePath,
      ]);
      if (!mounted) return;
      final page = values[0] as FreshResourcePage;
      final metadata = values[1] as Map<String, Object?>;
      setState(() {
        _links = page.items;
        _hasMore = page.hasMore;
        _metadata = metadata;
        _totalCount = (metadata['count'] as num?)?.toInt() ?? 0;
        _path = values[2] as String;
        _message = '';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خواندن پوشه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePage(int delta) async {
    final nextOffset = _pageOffset + delta * _pageSize;
    if (nextOffset < 0 || (delta > 0 && !_hasMore)) return;
    setState(() => _pageOffset = nextOffset);
    await _refresh();
  }

  Future<void> _importText() async {
    final before = _totalCount;
    final incoming = _importController.text
        .split(RegExp(r'[\r\n\s]+'))
        .where((value) => value.trim().isNotEmpty);
    try {
      final total = await FreshResourceStore.merge(incoming, source: 'manual-import');
      if (!mounted) return;
      _importController.clear();
      await _refresh();
      if (mounted) {
        setState(() => _message = 'ذخیره انجام شد؛ تعداد کل منابع: $total (تغییر خالص: ${total - before}).');
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'ذخیره انجام نشد: $error');
    }
  }

  Future<void> _copyAll() async {
    if (_totalCount == 0) return;
    try {
      // Clipboard is an OS-wide text payload; keep full-copy as an explicit
      // action while normal browsing remains paginated.
      final allLinks = await FreshResourceStore.readLinks();
      await Clipboard.setData(ClipboardData(text: allLinks.join('\n')));
      if (mounted) setState(() => _message = 'لینک همه منابع کپی شد.');
    } catch (error) {
      if (mounted) setState(() => _message = 'کپی کامل انجام نشد: $error');
    }
  }

  Future<void> _clear() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌کردن منابع تازه؟'),
        content: const Text('فقط پوشه منابع تازه پاک می‌شود. پوشه سرورهای شخصی و بانک IP نت ملی دست‌نخورده می‌مانند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کن')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await FreshResourceStore.clear();
      if (!mounted) return;
      _pageOffset = 0;
      await _refresh();
      if (!mounted) return;
      setState(() => _message = 'پوشه منابع تازه پاک شد.');
    } catch (error) {
      if (mounted) setState(() => _message = 'پاک‌سازی پوشه انجام نشد: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final updated = _metadata['updatedAt']?.toString() ?? 'هنوز ثبت نشده';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پوشه منابع تازه'),
          actions: [
            IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.auto_awesome, size: 52),
                    const SizedBox(height: 8),
                    Text('${_totalCount} منبع ذخیره‌شده',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text('آخرین به‌روزرسانی: $updated', textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    SelectableText(_path, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    const Text(
                      'اتصال آنلاین: منابع عمومی را دریافت می‌کند و نسخه تازه را در همین پوشه ذخیره می‌کند.\n'
                      'اتصال آفلاین: بدون دانلود اینترنتی، از کانفیگ‌های ذخیره‌شده همین پوشه استفاده می‌کند.\n'
                      'سرور شخصی آفلاین: از پوشه جداگانه «سرورهای شخصی» استفاده می‌کند؛ این دو پوشه با هم قاطی نمی‌شوند.\n'
                      'بانک IP نت ملی نیز مستقل باقی می‌ماند و جایگزین‌هایش در همان بخش خودش نگهداری می‌شوند.',
                      style: TextStyle(height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _importController,
              minLines: 3,
              maxLines: 7,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'افزودن کانفیگ‌ها (هر لینک در یک خط)',
                hintText: 'vless://...\nvmess://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _importText, icon: const Icon(Icons.save), label: const Text('ذخیره در پوشه منابع تازه')),
            OutlinedButton.icon(onPressed: _totalCount == 0 ? null : _copyAll, icon: const Icon(Icons.copy), label: const Text('کپی همه کانفیگ‌ها')),
            OutlinedButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline), label: const Text('پاک‌کردن فقط منابع تازه')),
            if (_links.isNotEmpty) ...[
              const Divider(),
              Text('نمایش ${_pageOffset + 1} تا ${_pageOffset + _links.length} از $_totalCount',
                  textAlign: TextAlign.center),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || _pageOffset == 0 ? null : () => _changePage(-1),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('صفحه قبل'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || !_hasMore ? null : () => _changePage(1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('صفحه بعد'),
                  ),
                ],
              ),
              ..._links.asMap().entries.map((entry) => ListTile(
                    dense: true,
                    leading: Text('${_pageOffset + entry.key + 1}'),
                    title: SelectableText(entry.value, textDirection: TextDirection.ltr),
                    trailing: IconButton(
                      tooltip: 'کپی این کانفیگ',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: entry.value));
                        if (mounted) setState(() => _message = 'کانفیگ کپی شد.');
                      },
                    ),
                  )),
            ],
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (_message.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_message)),
            const SizedBox(height: 8),
            const Text('برای تعداد کانفیگ‌ها سقف ثابت داخل برنامه اعمال نمی‌شود. موجودی کامل ذخیره و بازیابی می‌شود؛ ظرفیت نهایی فقط به فضای ذخیره‌سازی آزاد دستگاه و سلامت فایل‌سیستم وابسته است. هر لینک پیش از ذخیره از نظر طرح URI پشتیبانی‌شده بررسی می‌شود.'),
          ],
        ),
      ),
    );
  }
}
