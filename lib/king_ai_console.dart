part of 'main.dart';

/// In-app control surface for the local coding model and guarded GitHub PR workflow.
class KingAiConsolePage extends StatefulWidget {
  const KingAiConsolePage({
    super.key,
    this.initialFeatureRequest,
    this.initialIdeaAnalysis,
    this.speakResponses = false,
  });

  final String? initialFeatureRequest;
  final String? initialIdeaAnalysis;
  final bool speakResponses;

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
  bool _initialRequestSubmitted = false;
  bool _initialIdeaAnalysisSubmitted = false;
  bool _ownerConfigured = false;
  bool _ownerUnlocked = false;
  bool _busy = false;
  bool _hasToken = false;
  double? _progress;
  String _output = 'کلید GitHub را ذخیره و مدل محلی را بارگذاری کن.';

  @override
  void initState() {
    super.initState();
    _featureRequestController.text = widget.initialIdeaAnalysis ?? widget.initialFeatureRequest ?? '';
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
    if (widget.speakResponses) unawaited(KingVoiceOutput.instance.stop());
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
      if (_ownerAuth.hasActiveSession) {
        await _maybeAnalyzeInitialIdea();
        await _maybeSubmitInitialFeatureRequest();
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
      if (mounted) {
        _ownerPasswordController.clear();
        _ownerConfirmController.clear();
      }
      await _refreshOwnerState();
      if (mounted) setState(() => _output = 'رمز مالک روی همین دستگاه به‌صورت امن ثبت شد.');
      await _maybeSubmitInitialFeatureRequest();
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
            ? 'دسترسی مالک برای حداکثر ۲ دقیقه فعال شد.'
            : 'احراز هویت ناموفق بود یا موقتاً قفل شده است.');
      }
      if (accepted) await _maybeSubmitInitialFeatureRequest();
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
      if (mounted) {
        _ownerNewPasswordController.clear();
        _ownerNewConfirmController.clear();
      }
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
      final rendered = result is String
          ? result
          : const JsonEncoder.withIndent('  ').convert(result);
      if (mounted) setState(() => _output = rendered);
      if (widget.speakResponses) {
        final summary = result is String
            ? result
            : result is Map && result['summary'] is String
                ? result['summary'].toString()
                : rendered;
        await KingVoiceOutput.instance.speakPersian(summary);
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
    if (!mounted) return;
    if (_ownerConfigured && !await _reauthenticateOwnerForCodeChange()) return;
    if (!mounted) return;

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _output = 'ابتدا کلید GitHub را وارد کن.');
      return;
    }
    await _run('ذخیره امن کلید', () async {
      await _ai.saveGitHubToken(token);
      if (mounted) _tokenController.clear();
      await _refreshTokenState();
      return {'status': 'token_saved_securely', 'token_exposed': false};
    });
    await _maybeSubmitInitialFeatureRequest();
  }

  Future<void> _maybeAnalyzeInitialIdea() async {
    if (!mounted || _initialIdeaAnalysisSubmitted ||
        (widget.initialIdeaAnalysis?.trim().length ?? 0) < 12 ||
        !_ownerAuth.hasActiveSession) {
      return;
    }
    if (!_ai.isLoaded) {
      if (mounted) {
        setState(() => _output =
            'ایده مالک محفوظ است. برای تحلیل محلی، ابتدا مدل کینگ را بارگذاری کن.');
      }
      return;
    }
    _initialIdeaAnalysisSubmitted = true;
    await _analyzeFeatureRequest();
  }

  Future<void> _analyzeFeatureRequest() async {
    if (!mounted) return;
    if (!_ownerAuth.hasActiveSession) {
      setState(() => _output = 'تحلیل ایده فقط برای مالک احراز هویت‌شده فعال است.');
      await _refreshOwnerState();
      return;
    }
    final task = _featureRequestController.text.trim();
    if (task.length < 12) {
      setState(() => _output = 'ایده را دقیق‌تر بنویس (حداقل ۱۲ نویسه).');
      return;
    }
    await _run('تحلیل ایده مالک؛ بدون تغییر سورس یا ساخت PR',
        () => _ai.analyzeOwnerIdea(task: task));
  }

  /// A direct owner request sent from the command bar is carried into this
  /// secure console. Once the owner session, GitHub token and local model are
  /// ready, submit it automatically instead of making the owner press a second
  /// button. No request is submitted before authentication.
  /// A warm owner session alone is not enough to authorize a source write.
  /// Require a fresh password proof for every user-originated code request.
  Future<bool> _reauthenticateOwnerForCodeChange() async {
    final controller = TextEditingController();
    try {
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تأیید دوباره مالک'),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              maxLength: 128,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'رمز مالک را برای همین درخواست وارد کن',
              ),
              onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('تأیید مالک'),
              ),
            ],
          ),
        ),
      );
      if (password == null || password.isEmpty) return false;
      final valid = await _ownerAuth.authenticate(password);
      if (mounted) {
        setState(() {
          _ownerUnlocked = valid;
          _output = valid
              ? 'هویت مالک برای همین درخواست دوباره تأیید شد.'
              : 'رمز مالک نادرست است؛ درخواست کدنویسی لغو شد.';
        });
      }
      return valid && mounted;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _maybeSubmitInitialFeatureRequest() async {
    if (!mounted || _initialRequestSubmitted ||
        (widget.initialFeatureRequest?.trim().length ?? 0) < 12 ||
        !_ownerAuth.hasActiveSession) {
      return;
    }
    if (!_hasToken || !_ai.isLoaded) {
      if (mounted) {
        setState(() => _output =
            'درخواست مالک محفوظ است. برای اجرای خودکار، اتصال GitHub و بارگذاری مدل محلی را کامل کن.');
      }
      return;
    }
    _initialRequestSubmitted = true;
    if (!await _reauthenticateOwnerForCodeChange()) {
      // Cancellation or a failed fresh proof must not permanently consume the
      // one-shot initial request; a later authenticated retry may submit it.
      _initialRequestSubmitted = false;
      return;
    }
    await _submitFeatureRequest(ownerReauthenticated: true);
  }

  Future<void> _submitFeatureRequest({bool ownerReauthenticated = false}) async {
    if (!mounted) return;
    if (!_ownerAuth.hasActiveSession) {
      setState(() => _output = 'برای افزودن قابلیت، احراز هویت مالک لازم است.');
      await _refreshOwnerState();
      return;
    }
    if (!ownerReauthenticated &&
        !await _reauthenticateOwnerForCodeChange()) {
      return;
    }
    if (!mounted) return;
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
      if (result['status'] == 'review_pr_created' && mounted) {
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
    await _maybeAnalyzeInitialIdea();
    await _maybeSubmitInitialFeatureRequest();
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
    if (!await _reauthenticateOwnerForCodeChange()) return;
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
    if (!await _reauthenticateOwnerForCodeChange()) return;

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
    if (!await _reauthenticateOwnerForCodeChange()) return;

    if (!_hasToken || !_ai.isLoaded) {
      setState(() => _output = 'برای کشف و ترمیم خودکار، ابتدا GitHub را متصل و مدل محلی را در حالت foreground بارگذاری کن.');
      return;
    }
    await _run('فعال‌سازی کشف خودکار PRهای دارای خطای CI', () async {
      await KingAiBackgroundSupervisor.enableAutonomousMaintenance();
      return {
        'status': 'autonomous_maintenance_scheduled',
        'repository': 'cafeeteriaa/King-vpn',
        'scanLimit': 10,
        'officialIranNetworkResearch': 'every 6 hours (best effort)',
        'autonomousSourceAudit': 'daily; creates a draft PR only',
        'ciRepair': 'every 15 minutes minimum (best effort)',
        'codeChanges': 'isolated review PR only; never auto-merge or publish',
        'initialCheck': 'scheduled immediately as one-off work',
        'fallbackFrequency': '15 minutes minimum (best effort; Android may defer)',
        'constraints': ['network connected', 'battery not low'],
      };
    });
  }

  Future<void> _disableBackground() async {
    if (!await _reauthenticateOwnerForCodeChange()) return;

    await _run('غیرفعال‌سازی ترمیم پس‌زمینه', () async {
      await KingAiBackgroundSupervisor.disable();
      return {'status': 'background_repair_disabled'};
    });
  }

  Future<void> _clearToken() async {
    if (!await _reauthenticateOwnerForCodeChange()) return;

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
                      onPressed: _busy || !_hasToken ? null : _setupOwnerPassword,
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
                if (!_ownerConfigured)
                  Text(
                    'برای ثبت اولیه، ابتدا کلید GitHub حساب مالک مخزن را در بخش اتصال امن پایین ذخیره کن؛ هویت حساب به‌صورت آنلاین بررسی می‌شود.',
                    style: theme.textTheme.bodySmall,
                  ),
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
                  child: OutlinedButton.icon(
                    onPressed: _busy || !_ownerUnlocked || !_ai.isLoaded
                        ? null
                        : _analyzeFeatureRequest,
                    icon: const Icon(Icons.psychology_alt),
                    label: const Text('فقط تحلیل ایده (بدون تغییر کد)'),
                  ),
                ),
                const SizedBox(height: 8),
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
                    child: const Text('خودبهسازی خودکار و مستمر پروژه'),
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
