import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fresh_resource_store.dart';

/// Bounded, paged manager for the phone's reusable fresh-resource folder.
class FreshResourcesPage extends StatefulWidget {
  const FreshResourcesPage({super.key});

  @override
  State<FreshResourcesPage> createState() => _FreshResourcesPageState();
}

class _FreshResourcesPageState extends State<FreshResourcesPage> {
  final TextEditingController _importController = TextEditingController();
  List<String> _links = <String>[];
  Map<String, Object?> _metadata = <String, Object?>{};
  FreshResourceCursor? _cursor;
  String _path = 'در حال خواندن مسیر...';
  bool _busy = true;
  bool _hasNext = false;
  String _message = '';
  int _totalCount = 0;
  int _storageBytes = 0;
  int _pageNumber = 1;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _importController.dispose();
    unawaited(_cursor?.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _cursor?.close();
      final metadata = await FreshResourceStore.metadata();
      final path = await FreshResourceStore.storagePath;
      final bytes = await FreshResourceStore.storageBytes;
      final cursor = await FreshResourceStore.openCursor(startAtByte: 0);
      final firstPage = await (cursor?.nextPage() ?? Future<List<String>>.value(<String>[]));
      if (cursor?.isDone == true) {
        await cursor!.close();
      }
      if (!mounted) {
        await cursor?.close();
        return;
      }
      setState(() {
        _cursor = cursor?.isDone == true ? null : cursor;
        _links = firstPage;
        _metadata = metadata;
        _path = path;
        _storageBytes = bytes;
        _totalCount = (metadata['count'] as num?)?.toInt() ?? 0;
        _hasNext = cursor != null && !cursor.isDone;
        _pageNumber = 1;
        _message = '';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خواندن پوشه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nextPage() async {
    final cursor = _cursor;
    if (_busy || cursor == null) return;
    setState(() => _busy = true);
    try {
      final page = await cursor.nextPage();
      if (cursor.isDone) {
        await cursor.close();
        _cursor = null;
      }
      if (!mounted) return;
      setState(() {
        _links = page;
        _pageNumber++;
        _hasNext = _cursor != null;
        _message = page.isEmpty ? 'صفحه دیگری برای نمایش وجود ندارد.' : '';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خواندن صفحه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPage() async {
    if (_links.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _links.join('\n')));
    if (mounted) setState(() => _message = 'کانفیگ‌های همین صفحه کپی شدند.');
  }

  Future<void> _copyAll() async {
    if (_links.isEmpty || _totalCount > FreshResourceStore.defaultPageSize) return;
    await Clipboard.setData(ClipboardData(text: _links.join('\n')));
    if (mounted) setState(() => _message = 'تمام منابع پوشه کپی شدند.');
  }

  Future<void> _importText() async {
    final incoming = _importController.text
        .split(RegExp(r'[\r\n\s]+'))
        .where((value) => value.trim().isNotEmpty);
    try {
      final total = await FreshResourceStore.merge(incoming, source: 'manual-import');
      if (!mounted) return;
      _importController.clear();
      await _refresh();
      if (mounted) {
        setState(() => _message = 'ذخیره انجام شد؛ تعداد کل منابع: $total.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'ذخیره انجام نشد: $error');
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
    await _cursor?.close();
    _cursor = null;
    await FreshResourceStore.clear();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    setState(() => _message = 'پوشه منابع تازه پاک شد.');
  }

  @override
  Widget build(BuildContext context) {
    final updated = _metadata['updatedAt']?.toString() ?? 'هنوز ثبت نشده';
    final countText = _totalCount.toString();
    final mb = (_storageBytes / (1024 * 1024)).toStringAsFixed(1);
    final canCopyAll = _totalCount <= FreshResourceStore.defaultPageSize && _links.isNotEmpty;
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
                    Text('$countText منبع ذخیره‌شده',
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text('حجم پوشه: $mb مگابایت', textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text('آخرین به‌روزرسانی: $updated', textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    SelectableText(_path, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    const Text(
                      'اتصال آنلاین: منابع عمومی را دریافت می‌کند و نسخه تازه را در همین پوشه ذخیره می‌کند.\n'
                      'اتصال آفلاین: بدون دانلود اینترنتی، کانفیگ‌ها را صفحه‌به‌صفحه از همین پوشه می‌خواند.\n'
                      'سرور شخصی و بانک IP نت ملی مستقل باقی می‌مانند و با این پوشه مخلوط نمی‌شوند.',
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
            OutlinedButton.icon(onPressed: _busy || _links.isEmpty ? null : _copyPage, icon: const Icon(Icons.copy), label: const Text('کپی صفحه فعلی')),
            if (canCopyAll)
              OutlinedButton.icon(onPressed: _busy ? null : _copyAll, icon: const Icon(Icons.copy_all), label: const Text('کپی همه منابع')),
            if (_hasNext)
              OutlinedButton.icon(onPressed: _busy ? null : _nextPage, icon: const Icon(Icons.navigate_next), label: Text('صفحه بعدی ($_pageNumber)')),
            OutlinedButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline), label: const Text('پاک‌کردن فقط منابع تازه')),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (_links.isNotEmpty)
              Text('نمایش ${_links.length} کانفیگ در صفحه $_pageNumber از حداکثر ${FreshResourceStore.defaultPageSize}'),
            if (_message.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_message)),
            const SizedBox(height: 8),
            Text('ظرفیت پوشه: حداکثر ${FreshResourceStore.maxEntries} کانفیگ و ۵۰۰ مگابایت؛ هرکدام زودتر پر شود. خواندن و جستجوی آفلاین صفحه‌به‌صفحه انجام می‌شود تا حافظه گوشی با چند میلیون ورودی اشباع نشود.'),
          ],
        ),
      ),
    );
  }
}
