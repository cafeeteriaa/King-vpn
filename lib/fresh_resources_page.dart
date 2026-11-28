import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

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
  int _totalCount = 0;
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
      final metadata = await FreshResourceStore.metadata();
      final preview = await FreshResourceStore.readPreview(limit: 100);
      final path = await FreshResourceStore.storagePath;
      if (!mounted) return;
      setState(() {
        _links = preview;
        _metadata = metadata;
        _path = path;
        _totalCount = (_metadata['count'] as int?) ?? 0;
        _message = '';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'خواندن پوشه ناموفق بود: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Iterable<String> _splitImportLines(String text) sync* {
    var start = 0;
    for (final match in RegExp(r'[\r\n\s]+').allMatches(text)) {
      if (match.start > start) yield text.substring(start, match.start);
      start = match.end;
    }
    if (start < text.length) yield text.substring(start);
  }

  Future<void> _importText() async {
    final before = _totalCount;
    final incoming = _splitImportLines(_importController.text)
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
    if (_links.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _links.join('\n')));
    if (mounted) setState(() => _message = '۱۰۰ کانفیگ اولِ فهرست کپی شد؛ برای جلوگیری از مصرف شدید حافظه، کل بانک چندمیلیونی در کلیپ‌بورد بارگذاری نمی‌شود.');
  }

  Future<void> _exportAll() async {
    if (_busy || _totalCount == 0) return;
    setState(() {
      _busy = true;
      _message = 'در حال ساخت خروجی جریانی از کل بانک؛ حافظهٔ برنامه با همهٔ کانفیگ‌ها پر نمی‌شود...';
    });
    File? output;
    try {
      final temporary = await getTemporaryDirectory();
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      output = File('${temporary.path}/kingvpn-offline-resources-$stamp.txt');
      final sink = output.openWrite();
      var exported = 0;
      try {
        await for (final link in FreshResourceStore.streamLinks()) {
          sink.writeln(link);
          exported++;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (exported == 0) {
        await output.delete();
        if (mounted) setState(() => _message = 'بانک منابع خالی است.');
        return;
      }
      final outputPath = output.path;
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'KING VPN offline resources',
          text: 'خروجی کامل منابع آفلاین KING VPN؛ تعداد: $exported',
          files: <XFile>[XFile(outputPath)],
        ),
      );
      if (!mounted) return;
      switch (result.status) {
        case ShareResultStatus.success:
          setState(() => _message = 'فایل کامل $exported کانفیگ ساخته و به پنجرهٔ اشتراک‌گذاری تحویل شد.');
          break;
        case ShareResultStatus.dismissed:
          setState(() => _message = 'فایل کامل ساخته شد؛ پنجرهٔ اشتراک‌گذاری بسته شد. مسیر فایل: ${outputPath}');
          break;
        case ShareResultStatus.unavailable:
          setState(() => _message = 'فایل کامل ساخته شد اما اشتراک‌گذاری در این دستگاه در دسترس نیست. مسیر فایل: ${outputPath}');
          break;
      }
    } catch (error) {
      if (output != null) {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _message = 'ساخت یا اشتراک‌گذاری خروجی کامل انجام نشد: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    await FreshResourceStore.clear();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    setState(() => _message = 'پوشه منابع تازه پاک شد.');
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
                    Text('$_totalCount منبع ذخیره‌شده • نمایش ${_links.length} مورد اول',
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
                hintText: 'vless://...\\nvmess://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: _busy ? null : _importText, icon: const Icon(Icons.save), label: const Text('ذخیره در پوشه منابع تازه')),
            OutlinedButton.icon(onPressed: _links.isEmpty ? null : _copyAll, icon: const Icon(Icons.copy), label: const Text('کپی ۱۰۰ کانفیگ اول')),
            OutlinedButton.icon(onPressed: _busy || _totalCount == 0 ? null : _exportAll, icon: const Icon(Icons.ios_share), label: const Text('خروجی کامل بانک کانفیگ‌ها')),
            OutlinedButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline), label: const Text('پاک‌کردن فقط منابع تازه')),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (_message.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_message)),
            const SizedBox(height: 8),
            Text('تعداد کانفیگ‌ها سقف عددی ثابت ندارد؛ داده‌ها در ۲۵۶ بخش روی دیسک ذخیره و به‌صورت جریانی خوانده می‌شوند. ظرفیت عملی به فضای ذخیره‌سازی دستگاه وابسته است و کل مجموعه در RAM بارگذاری نمی‌شود.'),
          ],
        ),
      ),
    );
  }
}
