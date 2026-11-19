import 'dart:convert';
import 'package:flutter/material.dart';
import 'king_local_ai.dart';
import 'king_ai_background.dart';
import 'king_ai_owner_auth.dart';

/// In-app control surface for the local coding model and guarded GitHub PR workflow.
class KingAiConsolePage extends StatefulWidget {
  const KingAiConsolePage({super.key});
  @override
  State<KingAiConsolePage> createState() => _KingAiConsolePageState();
}

class _KingAiConsolePageState extends State<KingAiConsolePage> {
  static const String _owner = 'cafeeteriaa';
  static const String _repository = 'King-vpn';
  final KingLocalAi _ai = KingLocalAi.instance;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _pullController = TextEditingController();
  final TextEditingController _ownerPasswordController = TextEditingController();
  final TextEditingController _ownerConfirmController = TextEditingController();
  final TextEditingController _ownerNewPasswordController = TextEditingController();
  final TextEditingController _ownerNewConfirmController = TextEditingController();
  final TextEditingController _featureRequestController = TextEditingController();
  final KingAiOwnerAuth _ownerAuth = KingAiOwnerAuth.instance;
  bool _ownerConfigured = false;
  bool _ownerUnlocked = false;
  bool _busy = false;
  bool _hasToken = false;
  double? _progress;
  String _output = 'کلید GitHub را ذخیره و مدل محلی را بارگذاری کن.';

  @override
  void initState() {
    super.initState();
    _refreshTokenState();
    _refreshOwnerState();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _pullController.dispose();
    _ownerPasswordController.dispose();
    _ownerConfirmController.dispose();
    _ownerNewPasswordController.dispose();
    _ownerNewConfirmController.dispose();
    _featureRequestController.dispose();
    super.dispose();
  }

  Future<void> _refreshTokenState() async {
    try {
      final available = await _ai.hasGitHubToken();
      if (mounted) setState(() => _hasToken = available);
    } catch (error) {
      if (mounted) setState(() => _output = 'خطا در بررسی امن کلید GitHub: $error');
    }
  }

  Future<void> _refreshOwnerState() async {
    try {
      final configured = await _ownerAuth.isConfigured;
      if (mounted) {
        setState(() {
          _ownerConfigured = configured;
          _ownerUnlocked = _ownerAuth.hasActiveSession;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _output = 'خطا در بررسی وضعیت مالک: $error');
    }
  }

  Future<void> _setupOwnerPassword() async {
    final password = _ownerPasswordController.text;
    if (password != _ownerConfirmController.text) {
      setState(() => _output = 'رمز و تکرار آن یکسان نیستند.');
      return;
    }
    try {
      await _ownerAuth.setInitialPassword(password);
      _ownerPasswordController.clear();
      _ownerConfirmController.clear();
      await _refreshOwnerState();
      if (mounted) setState(() => _output = 'رمز مالک روی همین دستگاه به‌صورت امن ثبت شد.');
    } catch (error) {
      if (mounted) setState(() => _output = 'ثبت رمز مالک انجام نشد: $error');
    }
  }

  Future<void> _unlockOwner() async {
    final password = _ownerPasswordController.text;
    _ownerPasswordController.clear();
    try {
      final accepted = await _ownerAuth.authenticate(password);
      await _refreshOwnerState();
      if (mounted) {
        setState(() => _output = accepted
            ? 'دسترسی مالک برای ۱۵ دقیقه فعال شد.'
            : 'احراز هویت ناموفق بود یا موقتاً قفل شده است.');
      }
    } catch (error) {
      if (mounted) setState(() => _output = 'احراز هویت انجام نشد: $error');
    }
  }

  Future<void> _changeOwnerPassword() async {
    final password = _ownerNewPasswordController.text;
    if (password != _ownerNewConfirmController.text) {
      setState(() => _output = 'رمز جدید و تکرار آن یکسان نیستند.');
      return;
    }
    try {
      await _ownerAuth.changePassword(password);
      _ownerNewPasswordController.clear();
      _ownerNewConfirmController.clear();
      await _refreshOwnerState();
      if (mounted) setState(() => _output = 'رمز مالک با موفقیت تغییر کرد.');
    } catch (error) {
      if (mounted) setState(() => _output = 'تغییر رمز مالک انجام نشد: $error');
    }
  }

  Future<void> _lockOwner() async {
    _ownerAuth.lock();
    await _refreshOwnerState();
    if (mounted) setState(() => _output = 'دسترسی مالک قفل شد.');
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _output = '$label...';
    });
    try {
      final result = await action();
      if (mounted) {
        setState(() => _output = const JsonEncoder.withIndent('  ').convert(result));
      }
    } catch (error) {
      if (mounted) setState(() => _output = 'خطا: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _requireOwnerSession(String action) async {
    if (_ownerAuth.hasActiveSession) return true;
    if (mounted) {
      setState(() => _output = 'برای $action ابتدا مالک اصلی باید در پنل امن احراز هویت کند.');
    }
    await _refreshOwnerState();
    return false;
  }

  Future<void> _saveToken() async {
    if (_ownerConfigured && !await _requireOwnerSession('تغییر کلید GitHub')) return;

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _output = 'ابتدا کلید GitHub را وارد کن.');
      return;
    }
    await _run('ذخیره امن کلید', () async {
      await _ai.saveGitHubToken(token);
      _tokenController.clear();
      await _refreshTokenState();
      return {'status': 'token_saved_securely', 'token_exposed': false};
    });
  }

  Future<void> _submitFeatureRequest() async {
    if (!_ownerAuth.hasActiveSession) {
      setState(() => _output = 'برای افزودن قابلیت، احراز هویت مالک لازم است.');
      await _refreshOwnerState();
      return;
    }
    final task = _featureRequestController.text.trim();
    if (task.length < 12) {
      setState(() => _output = 'درخواست قابلیت را دقیق‌تر بنویس (حداقل ۱۲ نویسه).');
      return;
    }
    await _run('تحلیل درخواست مالک و ساخت PR بازبینی', () async {
      final result = await _ai.createOwnerFeatureProposal(
        task: task,
        owner: _owner,
        repository: _repository,
      );
      if (result['status'] == 'review_pr_created') {
        _featureRequestController.clear();
      }
      return result;
    });
  }

  Future<void> _loadModel() async {
    await _run('دانلود/بارگذاری مدل محلی', () async {
      await _ai.loadModel(onProgress: (value) {
        if (mounted) setState(() => _progress = value.clamp(0.0, 1.0).toDouble());
      });
      return {'status': 'model_loaded', 'model': KingLocalAi.modelId, 'loaded': _ai.isLoaded};
    });
    if (mounted) setState(() => _progress = null);
  }

  int? get _pullNumber => int.tryParse(_pullController.text.trim());

  Future<void> _inspect() async {
    final number = _pullNumber;
    if (number == null || number < 1) {
      setState(() => _output = 'شماره Pull Request معتبر نیست.');
      return;
    }
    await _run('بررسی شواهد CI', () => _ai.inspectPullRequestCi(
      owner: _owner, repository: _repository, pullNumber: number,
    ));
  }

  Future<void> _repair() async {
    if (!_ownerAuth.hasActiveSession) {
      setState(() => _output = 'برای درخواست اصلاح کد، ابتدا مالک اصلی باید احراز هویت شود.');
      await _refreshOwnerState();
      return;
    }
    final number = _pullNumber;
    if (number == null || number < 1) {
      setState(() => _output = 'شماره Pull Request معتبر نیست.');
      return;
    }
    if (!_ai.isLoaded) {
      setState(() => _output = 'ابتدا مدل محلی را بارگذاری کن.');
      return;
    }
    await _run('تحلیل و پیشنهاد اصلاح در شاخه مستقل', () => _ai.repairFromFailedCi(
      owner: _owner, repository: _repository, pullNumber: number,
    ));
  }

  Future<void> _enableBackground() async {
    if (!await _requireOwnerSession('فعال‌سازی ترمیم خودکار پس‌زمینه')) return;

    final number = _pullNumber;
    if (number == null || number < 1) {
      setState(() => _output = 'شماره Pull Request معتبر نیست.');
      return;
    }
    if (!_hasToken || !_ai.isLoaded) {
      setState(() => _output = 'برای فعال‌سازی پس‌زمینه، ابتدا GitHub را متصل و مدل را در حالت foreground بارگذاری کن.');
      return;
    }
    await _run('فعال‌سازی ترمیم خودکار پس‌زمینه', () async {
      await KingAiBackgroundSupervisor.enable(number);
      return {
        'status': 'background_repair_scheduled',
        'pullRequest': number,
        'initialCheck': 'scheduled immediately as one-off work',
        'fallbackFrequency': '15 minutes minimum (best effort; Android may defer)',
        'constraints': ['network connected', 'battery not low'],
        'modelDownloadInBackground': false,
      };
    });
  }

  Future<void> _enableAutomaticDiscovery() async {
    if (!await _requireOwnerSession('فعال‌سازی کشف خودکار مخزن')) return;

    if (!_hasToken || !_ai.isLoaded) {
      setState(() => _output = 'برای کشف و ترمیم خودکار، ابتدا GitHub را متصل و مدل محلی را در حالت foreground بارگذاری کن.');
      return;
    }
    await _run('فعال‌سازی کشف خودکار PRهای دارای خطای CI', () async {
      await KingAiBackgroundSupervisor.enableAutomaticDiscovery();
      return {
        'status': 'automatic_repository_repair_scheduled',
        'repository': 'cafeeteriaa/King-vpn',
        'scanLimit': 10,
        'initialCheck': 'scheduled immediately as one-off work',
        'fallbackFrequency': '15 minutes minimum (best effort; Android may defer)',
        'constraints': ['network connected', 'battery not low'],
      };
    });
  }

  Future<void> _disableBackground() async {
    if (!await _requireOwnerSession('توقف ترمیم پس‌زمینه')) return;

    await _run('غیرفعال‌سازی ترمیم پس‌زمینه', () async {
      await KingAiBackgroundSupervisor.disable();
      return {'status': 'background_repair_disabled'};
    });
  }

  Future<void> _clearToken() async {
    if (!await _requireOwnerSession('پاک‌کردن کلید GitHub')) return;

    await _run('پاک‌کردن کلید ذخیره‌شده', () async {
      await KingAiBackgroundSupervisor.disable();
      await _ai.clearGitHubToken();
      await _refreshTokenState();
      return {'status': 'token_cleared', 'background_repair': 'disabled'};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('هوش مصنوعی داخلی کینگ')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مدل کدنویسی محلی Qwen 1.5B',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_ai.isLoaded ? 'مدل آماده است' : 'مدل هنوز بارگذاری نشده'),
                if (_progress != null) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _progress),
                  Text('${(_progress! * 100).toStringAsFixed(0)}٪'),
                ],
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: _busy ? null : _loadModel,
                  child: const Text('دانلود و بارگذاری مدل محلی (حدود ۱٫۱ گیگابایت)'),
                )),
              ]),
            )),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مالک اصلی و مجوز توسعه', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(!_ownerConfigured
                    ? 'رمز مالک هنوز روی این دستگاه تعیین نشده است.'
                    : (_ownerUnlocked ? 'دسترسی مالک فعال است (حداکثر ۱۵ دقیقه).' : 'دسترسی مالک قفل است.')),
                TextField(
                  controller: _ownerPasswordController,
                  obscureText: true,
                  maxLength: 128,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _ownerConfigured ? 'رمز مالک' : 'رمز جدید مالک',
                  ),
                ),
                if (!_ownerConfigured)
                  TextField(
                    controller: _ownerConfirmController,
                    obscureText: true,
                    maxLength: 128,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'تکرار رمز مالک'),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (!_ownerConfigured)
                    FilledButton(
                      onPressed: _busy ? null : _setupOwnerPassword,
                      child: const Text('ثبت رمز مالک روی دستگاه'),
                    )
                  else if (!_ownerUnlocked)
                    FilledButton(
                      onPressed: _busy ? null : _unlockOwner,
                      child: const Text('احراز هویت مالک'),
                    )
                  else
                    OutlinedButton(
                      onPressed: _busy ? null : _lockOwner,
                      child: const Text('قفل‌کردن دسترسی مالک'),
                    ),
                ]),
                if (_ownerUnlocked) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ownerNewPasswordController,
                    obscureText: true,
                    maxLength: 128,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'رمز جدید مالک'),
                  ),
                  TextField(
                    controller: _ownerNewConfirmController,
                    obscureText: true,
                    maxLength: 128,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'تکرار رمز جدید'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _changeOwnerPassword,
                    child: const Text('تغییر رمز مالک'),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'رمز فقط روی همین دستگاه ثبت می‌شود و در چت یا گزارش‌ها ارسال نمی‌شود. حداقل ۱۲ نویسه؛ پس از ۵ تلاش ناموفق، تأخیر افزایشی اعمال می‌شود. اولین ثبت فقط یک‌بار ممکن است؛ برای درخواست تغییر کد باید مالک احراز هویت شود.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                const Divider(height: 24),
                const Text('درخواست قابلیت از مالک', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('این مسیر فقط پس از احراز هویت مالک فعال می‌شود. کینگ کد را با مدل محلی پیشنهاد می‌دهد و فقط یک Pull Request برای بازبینی می‌سازد؛ هیچ تغییری مستقیم روی main اعمال نمی‌شود.'),
                TextField(
                  controller: _featureRequestController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'قابلیت موردنظر را توضیح بده',
                    hintText: 'مثلاً یک قابلیت جدید برای مدیریت هوشمند اتصال...',
                    alignLabelWithHint: true,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _busy || !_ownerUnlocked || !_hasToken || !_ai.isLoaded
                        ? null
                        : _submitFeatureRequest,
                    child: const Text('ساخت پیشنهاد کد و Pull Request'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('اتصال امن GitHub', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_hasToken ? 'کلید GitHub در حافظه امن دستگاه ذخیره است.' : 'هنوز کلید GitHub ذخیره نشده است.'),
                TextField(
                  controller: _tokenController, obscureText: true,
                  autocorrect: false, enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'GitHub Personal Access Token',
                    hintText: 'github_pat_… یا ghp_…',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: _busy ? null : _saveToken,
                      child: const Text('ذخیره امن کلید')),
                  OutlinedButton(onPressed: _busy || !_hasToken ? null : _clearToken,
                      child: const Text('پاک‌کردن کلید')),
                ]),
                const SizedBox(height: 6),
                Text('مجوزهای لازم برای همین مخزن: Contents (خواندن/نوشتن)، Pull requests (خواندن/نوشتن)، Actions (خواندن) و Checks (خواندن). کلید در گزارش‌ها نمایش داده نمی‌شود.',
                    style: theme.textTheme.bodySmall),
              ]),
            )),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('بررسی و ترمیم CI مخزن King VPN',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('مخزن متصل: cafeeteriaa/King-vpn'),
                TextField(
                  controller: _pullController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'شماره Pull Request', hintText: 'مثلاً 12',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonal(onPressed: _busy || !_hasToken ? null : _inspect,
                      child: const Text('بررسی CI')),
                  FilledButton(onPressed: _busy || !_hasToken || !_ai.isLoaded ? null : _repair,
                      child: const Text('تحلیل و ساخت PR اصلاحی')),
                ]),
                const SizedBox(height: 10),
                const Text(
                  'ترمیم خودکار: بلافاصله یک بررسی اولیه زمان‌بندی می‌شود؛ سپس بررسی دوره‌ای با حداقل فاصله ۱۵ دقیقه به‌عنوان پشتیبان اجرا می‌شود. هر دو تابع محدودیت‌های زمان‌بندی اندروید، اتصال شبکه و وضعیت باتری هستند.',
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: _busy || !_hasToken || !_ai.isLoaded ? null : _enableAutomaticDiscovery,
                    child: const Text('کشف و ترمیم خودکار کل مخزن'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || !_hasToken || !_ai.isLoaded ? null : _enableBackground,
                    child: const Text('ترمیم خودکار یک PR مشخص'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _disableBackground,
                    child: const Text('توقف ترمیم پس‌زمینه'),
                  ),
                ]),
              ]),
            )),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('گزارش عملیات', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_busy) const LinearProgressIndicator(),
                SelectableText(_output),
              ]),
            )),
          ],
        ),
      ),
    );
  }
}
